#!/usr/bin/env python3
"""
Test harness for iterating on Ollama receipt OCR prompts.

Sends each receipt image to Ollama with a given prompt, parses the JSON
response, and compares extracted values against hand-verified ground truth.

Usage:
    python test_ollama_prompt.py
"""

import base64
import json
import re
import sys
import time
from pathlib import Path

import urllib.request
import urllib.error

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

OLLAMA_URL = "http://localhost:11434/api/chat"
OLLAMA_MODEL = "gemma4:latest"
RECEIPT_DIR = Path(__file__).parent

# Ground truth from receipts.md
GROUND_TRUTH = {
    "costco.jpg":          {"category": "Groceries",  "total": 505.41, "tax": 37.44},
    "dunkin-donuts.jpg":   {"category": "Food",       "total": 23.15,  "tax": 1.79},
    "dunkin-donuts-2.jpg": {"category": "Food",       "total": 3.01,   "tax": 0.22},
    "target.jpg":          {"category": "Groceries",  "total": 17.04,  "tax": 0.46},
    "walmart-1.webp":      {"category": "Household",  "total": 35.36,  "tax": 2.54},
    "walmart-2.webp":      {"category": "Clothing",   "total": 29.73,  "tax": 2.30},
}

# Category synonyms — ground truth uses casual names, model uses formal list
CATEGORY_SYNONYMS = {
    "Food": ["Dining", "Food", "Food & Drink", "Restaurant", "Fast Food"],
    "Groceries": ["Groceries", "Grocery", "Supermarket", "Home", "Shopping"],
    "Household": ["Home", "Household", "Home Improvement", "Home & Garden", "Groceries", "Shopping"],
    "Clothing": ["Shopping", "Clothing", "Apparel", "Clothes"],
}

TOLERANCE = 0.02  # $0.02 tolerance for float comparison


# ---------------------------------------------------------------------------
# Prompt to test (edit this between runs)
# ---------------------------------------------------------------------------

CATEGORY_LIST = (
    "Groceries, Dining, Transportation, Entertainment, Shopping, "
    "Healthcare, Utilities, Gas/Fuel, Travel, Education, "
    "Personal Care, Home, Insurance, Subscriptions, Other"
)

PROMPT = f"""Extract structured data from this receipt image. Return ONLY valid JSON with this schema:

{{
  "merchant_name": "string or null",
  "date": "YYYY-MM-DD or null",
  "subtotal": number or null,
  "tax_amount": number or null,
  "total_amount": number or null,
  "currency": "USD/MXN/EUR/etc or null",
  "items": [{{"description": "string", "quantity": number, "unit_price": number}}],  // max 5 items
  "payment_method": "cash/credit/debit/unknown",
  "category_suggestion": "one of: {CATEGORY_LIST}"
}}

Rules:
- Numbers must be plain (no $ or currency symbols).
- Set unreadable or missing fields to null.
- total_amount = the amount the customer actually paid. Look for "Total", "Payment", "Amount Due", or "CHARGE" amount. If a gift card or reward was used, the total is the amount after applying it. "Balance" on a gift card line is NOT the total.
- tax_amount = the dollar amount of sales tax charged. If the tax line shows both a taxable base and a tax amount (e.g. "TAX 8% on $5.28 $0.46"), the tax_amount is the LAST/smaller number ($0.46), not the taxable base. Look for "Tax", "Sales Tax", state names like "NY Tax" or "Nevada".
- Verify: subtotal + tax_amount should approximately equal total_amount. If they don't, re-read the numbers.
- For Spanish receipts: IVA = tax, TOTAL = total, SUBTOTAL = subtotal.
- items: include up to 5 items maximum. Skip the rest.
- category_suggestion: pick based on what was PURCHASED, not just the store name. Use "Groceries" for food and grocery items. Use "Dining" for restaurants and coffee shops. Use "Home" for household/cleaning supplies. Use "Shopping" for clothing, electronics, general merchandise.
- Return ONLY the JSON object. No explanation, no markdown fences, no extra text."""


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def load_image_base64(path: Path) -> str:
    """Read an image file and return base64-encoded string."""
    return base64.b64encode(path.read_bytes()).decode("utf-8")


def extract_json(text: str) -> dict | None:
    """Try to parse JSON from model output, handling markdown fences."""
    cleaned = text.strip()
    # Strip markdown fences
    if cleaned.startswith("```"):
        cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned)
        cleaned = re.sub(r"\s*```$", "", cleaned)
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        pass
    # Fallback: find first JSON object
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if match:
        try:
            return json.loads(match.group(0))
        except json.JSONDecodeError:
            pass
    return None


def call_ollama(image_b64: str, prompt: str) -> tuple[dict | None, str, float]:
    """Send image to Ollama, return (parsed_json, raw_text, elapsed_seconds)."""
    payload = {
        "model": OLLAMA_MODEL,
        "messages": [
            {
                "role": "user",
                "content": prompt,
                "images": [image_b64],
            }
        ],
        "stream": False,
        "options": {"temperature": 0.0},
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        OLLAMA_URL,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    start = time.time()
    with urllib.request.urlopen(req, timeout=360) as resp:
        body = json.loads(resp.read().decode("utf-8"))
    elapsed = time.time() - start
    raw = body["message"]["content"].strip()
    parsed = extract_json(raw)
    return parsed, raw, elapsed


def category_matches(expected: str, got: str | None) -> bool:
    """Check if the model's category is an acceptable match for ground truth."""
    if got is None:
        return False
    got_lower = got.strip().lower()
    # Direct match
    if got_lower == expected.lower():
        return True
    # Check synonyms
    synonyms = CATEGORY_SYNONYMS.get(expected, [expected])
    return any(s.lower() == got_lower for s in synonyms)


def amount_matches(expected: float, got) -> bool:
    """Check if extracted amount matches within tolerance."""
    if got is None:
        return False
    try:
        return abs(float(got) - expected) <= TOLERANCE
    except (ValueError, TypeError):
        return False


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 70)
    print(f"Ollama Receipt OCR Prompt Test — Model: {OLLAMA_MODEL}")
    print("=" * 70)

    results = []
    for filename, truth in GROUND_TRUTH.items():
        filepath = RECEIPT_DIR / filename
        if not filepath.exists():
            print(f"\n[SKIP] {filename} — file not found")
            continue

        print(f"\n{'─' * 60}")
        print(f"Testing: {filename}")
        print(f"  Expected: total={truth['total']}, tax={truth['tax']}, category={truth['category']}")

        try:
            img_b64 = load_image_base64(filepath)
            parsed, raw, elapsed = call_ollama(img_b64, PROMPT)
        except Exception as e:
            print(f"  ERROR: {e}")
            results.append({"file": filename, "total": False, "tax": False, "category": False, "json_ok": False})
            continue

        if parsed is None:
            print(f"  FAILED to parse JSON from response:")
            print(f"  Raw (first 300 chars): {raw[:300]}")
            results.append({"file": filename, "total": False, "tax": False, "category": False, "json_ok": False})
            continue

        got_total = parsed.get("total_amount")
        got_tax = parsed.get("tax_amount")
        got_cat = parsed.get("category_suggestion")

        total_ok = amount_matches(truth["total"], got_total)
        tax_ok = amount_matches(truth["tax"], got_tax)
        cat_ok = category_matches(truth["category"], got_cat)

        status = lambda ok: "PASS" if ok else "FAIL"
        print(f"  Got:      total={got_total} [{status(total_ok)}], tax={got_tax} [{status(tax_ok)}], category={got_cat} [{status(cat_ok)}]")
        print(f"  Time: {elapsed:.1f}s")

        if not (total_ok and tax_ok and cat_ok):
            # Show full parsed for debugging
            print(f"  Full response: {json.dumps(parsed, indent=2)[:500]}")

        results.append({"file": filename, "total": total_ok, "tax": tax_ok, "category": cat_ok, "json_ok": True})

    # Scorecard
    print(f"\n{'=' * 70}")
    print("SCORECARD")
    print(f"{'=' * 70}")
    n = len(results)
    json_ok = sum(1 for r in results if r["json_ok"])
    total_ok = sum(1 for r in results if r["total"])
    tax_ok = sum(1 for r in results if r["tax"])
    cat_ok = sum(1 for r in results if r["category"])

    print(f"  JSON parseable: {json_ok}/{n}")
    print(f"  Total correct:  {total_ok}/{n}")
    print(f"  Tax correct:    {tax_ok}/{n}")
    print(f"  Category match: {cat_ok}/{n}")
    print(f"  All correct:    {sum(1 for r in results if r['total'] and r['tax'] and r['category'])}/{n}")

    # Return exit code based on results
    all_pass = all(r["total"] and r["tax"] and r["category"] for r in results)
    sys.exit(0 if all_pass else 1)


if __name__ == "__main__":
    main()
