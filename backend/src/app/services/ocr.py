"""
Dual-mode OCR service for receipt data extraction.

Mode 1 (Cloud): Claude Haiku 4.5 Vision API -- high accuracy, bilingual (EN/ES).
Mode 2 (Ollama): Local LLM via Ollama (e.g. Gemma 4) -- medium accuracy, free/private.
Mode 3 (Offline): Tesseract OCR with Pillow preprocessing -- local fallback.
Dispatcher selects mode based on settings or explicit override.
"""

import base64
import io
import json
import logging
import re
from typing import Any

import anthropic
import httpx
import pytesseract
from PIL import Image, ImageEnhance, ImageFilter

from src.app.config import settings

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Shared constants
# ---------------------------------------------------------------------------

_CATEGORY_LIST = (
    "Groceries, Dining, Transportation, Entertainment, Shopping, "
    "Healthcare, Utilities, Gas/Fuel, Travel, Education, "
    "Personal Care, Home, Insurance, Subscriptions, Other"
)

# ---------------------------------------------------------------------------
# Claude Vision (cloud) extraction
# ---------------------------------------------------------------------------

_CLAUDE_RECEIPT_PROMPT = f"""You are a receipt data extractor. Analyze this receipt image and extract
structured data. The receipt may be in English or Spanish (or a mix).

Extract the following fields:
- merchant_name: The store or business name
- date: Transaction date in YYYY-MM-DD format
- subtotal: Subtotal before tax (number, no currency symbol)
- tax_amount: Tax / IVA / Impuesto amount (number, no currency symbol)
- total_amount: Final total (number, no currency symbol)
- currency: Three-letter currency code (USD, MXN, EUR, etc.)
- items: Array of line items, each with {{description, quantity, unit_price}}
- payment_method: How it was paid (cash/credit/debit/unknown)
- category_suggestion: The single best expense category from this list: {_CATEGORY_LIST}

Rules:
- If a field is unreadable or missing, set it to null.
- For Spanish receipts: IVA = tax, TOTAL = total, SUBTOTAL = subtotal.
- category_suggestion: pick based on the merchant type and items purchased.
- Return ONLY valid JSON. No explanation, no markdown fences."""


def extract_receipt_claude(image_base64: str) -> dict[str, Any]:
    """Send a base64-encoded JPEG to Claude Haiku 4.5 for receipt extraction.

    Returns a dict with extracted receipt fields, or an error dict on failure.
    """
    if not settings.anthropic_api_key:
        return {"error": "Anthropic API key not configured", "method": "claude"}

    try:
        client = anthropic.Anthropic(api_key=settings.anthropic_api_key)

        message = client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=1024,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": image_base64,
                            },
                        },
                        {
                            "type": "text",
                            "text": _CLAUDE_RECEIPT_PROMPT,
                        },
                    ],
                }
            ],
        )

        raw_text = message.content[0].text.strip()

        # Strip markdown fences if the model wraps them anyway
        if raw_text.startswith("```"):
            raw_text = re.sub(r"^```(?:json)?\s*", "", raw_text)
            raw_text = re.sub(r"\s*```$", "", raw_text)

        parsed = json.loads(raw_text)
        parsed["method"] = "claude"
        parsed["confidence"] = "high"
        parsed["needs_review"] = False
        return parsed

    except json.JSONDecodeError as exc:
        logger.warning("Claude returned non-JSON response: %s", exc)
        return {
            "error": "Failed to parse Claude response as JSON",
            "raw_response": raw_text[:500] if "raw_text" in dir() else None,
            "method": "claude",
            "needs_review": True,
        }
    except anthropic.BadRequestError as exc:
        # Covers blurry images, non-receipt images, content moderation
        logger.warning("Claude rejected the image: %s", exc)
        return {
            "error": f"Image rejected by Claude: {exc.message}",
            "method": "claude",
            "needs_review": True,
        }
    except anthropic.APIError as exc:
        logger.error("Claude API error: %s", exc)
        return {
            "error": f"Claude API error: {str(exc)}",
            "method": "claude",
            "needs_review": True,
        }
    except Exception as exc:
        logger.error("Unexpected error in Claude OCR: %s", exc, exc_info=True)
        return {
            "error": f"Unexpected OCR error: {str(exc)}",
            "method": "claude",
            "needs_review": True,
        }


# ---------------------------------------------------------------------------
# Ollama (local LLM) extraction
# ---------------------------------------------------------------------------

_OLLAMA_RECEIPT_PROMPT = f"""Extract structured data from this receipt image. Return ONLY valid JSON matching this exact schema:

{{
  "merchant_name": "string or null",
  "date": "YYYY-MM-DD or null",
  "subtotal": number or null,
  "tax_amount": number or null,
  "total_amount": number or null,
  "currency": "USD/MXN/EUR/etc or null",
  "items": [{{"description": "string", "quantity": number, "unit_price": number}}],
  "payment_method": "cash/credit/debit/unknown",
  "category_suggestion": "one of: {_CATEGORY_LIST}"
}}

Rules:
- Numbers must be plain (no $ or currency symbols).
- Set unreadable or missing fields to null.
- For Spanish receipts: IVA = tax, TOTAL = total, SUBTOTAL = subtotal.
- category_suggestion: pick the single best category from the list based on merchant type and items.
- Return ONLY the JSON object. No explanation, no markdown fences, no extra text."""


def _extract_json_from_text(text: str) -> str:
    """Try to extract a JSON object from text that may contain extra content."""
    # First try: strip markdown fences
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned)
        cleaned = re.sub(r"\s*```$", "", cleaned)

    # If it looks like valid JSON now, return it
    if cleaned.startswith("{"):
        return cleaned

    # Fallback: find the first JSON object in the text
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if match:
        return match.group(0)

    return cleaned


def extract_receipt_ollama(image_base64: str) -> dict[str, Any]:
    """Send a base64-encoded image to Ollama for receipt extraction.

    Uses the Ollama native /api/chat endpoint with vision support.
    Returns a dict with extracted receipt fields, or an error dict on failure.
    """
    if not settings.ollama_base_url:
        return {"error": "Ollama base URL not configured", "method": "ollama"}

    url = f"{settings.ollama_base_url.rstrip('/')}/api/chat"
    payload = {
        "model": settings.ollama_model,
        "messages": [
            {
                "role": "user",
                "content": _OLLAMA_RECEIPT_PROMPT,
                "images": [image_base64],
            }
        ],
        "stream": False,
        "options": {
            "temperature": 0.1,
        },
    }

    raw_text = ""
    try:
        with httpx.Client(timeout=120.0) as client:
            response = client.post(url, json=payload)
            response.raise_for_status()

        result = response.json()
        raw_text = result["message"]["content"].strip()

        cleaned = _extract_json_from_text(raw_text)
        parsed = json.loads(cleaned)
        parsed["method"] = "ollama"
        parsed["confidence"] = "medium"
        parsed["needs_review"] = True
        return parsed

    except httpx.ConnectError as exc:
        logger.warning(
            "Cannot connect to Ollama at %s: %s", settings.ollama_base_url, exc
        )
        return {
            "error": f"Cannot connect to Ollama at {settings.ollama_base_url} — is Ollama running?",
            "method": "ollama",
            "needs_review": True,
        }
    except httpx.TimeoutException as exc:
        logger.warning("Ollama request timed out: %s", exc)
        return {
            "error": "Ollama request timed out (model may still be loading)",
            "method": "ollama",
            "needs_review": True,
        }
    except httpx.HTTPStatusError as exc:
        logger.warning("Ollama HTTP error %s: %s", exc.response.status_code, exc)
        return {
            "error": f"Ollama HTTP error: {exc.response.status_code}",
            "method": "ollama",
            "needs_review": True,
        }
    except json.JSONDecodeError as exc:
        logger.warning("Ollama returned non-JSON: %s", exc)
        return {
            "error": "Failed to parse Ollama response as JSON",
            "raw_response": raw_text[:500] if raw_text else None,
            "method": "ollama",
            "needs_review": True,
        }
    except Exception as exc:
        logger.error("Unexpected Ollama OCR error: %s", exc, exc_info=True)
        return {
            "error": f"Unexpected Ollama error: {str(exc)}",
            "method": "ollama",
            "needs_review": True,
        }


# ---------------------------------------------------------------------------
# Tesseract (offline) extraction
# ---------------------------------------------------------------------------

# Regex patterns for English and Spanish receipt fields
_TOTAL_PATTERNS = [
    r"(?:GRAND\s*TOTAL|TOTAL\s*DUE|TOTAL|AMOUNT\s*DUE|MONTO\s*TOTAL|TOTAL\s*A\s*PAGAR)\s*[:$]?\s*\$?\s*([\d,]+\.?\d*)",
]
_TAX_PATTERNS = [
    r"(?:SALES?\s*TAX|TAX|IVA|IMPUESTO|I\.V\.A\.?)\s*[:$]?\s*\$?\s*([\d,]+\.?\d*)",
]
_SUBTOTAL_PATTERNS = [
    r"(?:SUBTOTAL|SUB\s*TOTAL|SUB-TOTAL)\s*[:$]?\s*\$?\s*([\d,]+\.?\d*)",
]
_DATE_PATTERNS = [
    r"(\d{4}[-/]\d{1,2}[-/]\d{1,2})",                     # 2026-03-29
    r"(\d{1,2}[-/]\d{1,2}[-/]\d{4})",                     # 03/29/2026 or 29/03/2026
    r"(\d{1,2}[-/]\d{1,2}[-/]\d{2})",                     # 03/29/26
    r"(\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\w*\s+\d{4})",  # 29 March 2026
]


def _search_patterns(text: str, patterns: list[str]) -> str | None:
    """Try each regex pattern against text, return first match group or None."""
    for pattern in patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            return match.group(1)
    return None


def _parse_amount(raw: str | None) -> float | None:
    """Clean a captured amount string into a float."""
    if raw is None:
        return None
    try:
        return float(raw.replace(",", ""))
    except (ValueError, TypeError):
        return None


def _preprocess_image(img: Image.Image) -> Image.Image:
    """Preprocess receipt image for better Tesseract accuracy."""
    # Convert to grayscale
    img = img.convert("L")
    # Increase contrast
    enhancer = ImageEnhance.Contrast(img)
    img = enhancer.enhance(2.0)
    # Sharpen to help with blurry receipts
    img = img.filter(ImageFilter.SHARPEN)
    # Light denoise via median filter
    img = img.filter(ImageFilter.MedianFilter(size=3))
    return img


def extract_receipt_tesseract(image_path: str) -> dict[str, Any]:
    """Extract receipt data using Tesseract OCR (offline fallback).

    Uses bilingual (eng+spa) language pack and receipt-optimized preprocessing.
    Returns a dict with extracted fields and needs_review=True.
    """
    try:
        img = Image.open(image_path)
        img = _preprocess_image(img)

        custom_config = "--psm 6 --oem 3"
        raw_text = pytesseract.image_to_string(img, lang="eng+spa", config=custom_config)

        total = _parse_amount(_search_patterns(raw_text, _TOTAL_PATTERNS))
        tax = _parse_amount(_search_patterns(raw_text, _TAX_PATTERNS))
        subtotal = _parse_amount(_search_patterns(raw_text, _SUBTOTAL_PATTERNS))
        date_str = _search_patterns(raw_text, _DATE_PATTERNS)

        # Try to extract merchant name from first non-empty line
        lines = [line.strip() for line in raw_text.split("\n") if line.strip()]
        merchant_name = lines[0] if lines else None

        return {
            "merchant_name": merchant_name,
            "date": date_str,
            "subtotal": subtotal,
            "tax_amount": tax,
            "total_amount": total,
            "currency": None,  # Tesseract can't reliably detect currency
            "items": [],  # Line-item parsing is unreliable with Tesseract
            "payment_method": None,
            "category_suggestion": None,
            "raw_text": raw_text,
            "method": "tesseract",
            "confidence": "low",
            "needs_review": True,
        }

    except FileNotFoundError:
        logger.error("Image file not found: %s", image_path)
        return {
            "error": f"Image file not found: {image_path}",
            "method": "tesseract",
            "needs_review": True,
        }
    except Exception as exc:
        logger.error("Tesseract OCR error: %s", exc, exc_info=True)
        return {
            "error": f"Tesseract OCR failed: {str(exc)}",
            "method": "tesseract",
            "raw_text": "",
            "needs_review": True,
        }


# ---------------------------------------------------------------------------
# Dispatcher
# ---------------------------------------------------------------------------

def extract_receipt(
    image_path: str = "",
    image_base64: str = "",
    mode: str = "auto",
) -> dict[str, Any]:
    """Dispatch receipt extraction to the appropriate OCR backend.

    Modes:
        auto    - Try Claude first; then Ollama; then Tesseract.
        cloud   - Claude Vision only.
        ollama  - Ollama (local LLM) only.
        offline - Tesseract only.
        manual  - Skip OCR entirely (user will enter data manually).

    Args:
        image_path:   Filesystem path to the receipt image (needed for Tesseract).
        image_base64: Base64-encoded JPEG (needed for Claude / Ollama).
        mode:         OCR mode override. Defaults to "auto".

    Returns:
        dict with extracted receipt fields or error information.
    """
    effective_mode = mode if mode != "auto" else settings.ocr_mode

    # Manual mode -- no OCR
    if effective_mode == "manual":
        return {
            "method": "manual",
            "needs_review": True,
            "message": "OCR skipped -- manual entry mode",
        }

    # Cloud-only mode
    if effective_mode == "cloud":
        if not image_base64:
            return {"error": "No base64 image provided for cloud OCR", "method": "cloud"}
        return extract_receipt_claude(image_base64)

    # Ollama-only mode
    if effective_mode == "ollama":
        if not image_base64:
            return {"error": "No base64 image provided for Ollama OCR", "method": "ollama"}
        return extract_receipt_ollama(image_base64)

    # Offline-only mode
    if effective_mode == "offline":
        if not image_path:
            return {"error": "No image path provided for offline OCR", "method": "tesseract"}
        return extract_receipt_tesseract(image_path)

    # Auto mode (default): Claude -> Ollama -> Tesseract
    if image_base64:
        result = extract_receipt_claude(image_base64)
        if "error" not in result:
            return result
        logger.info("Claude OCR failed, falling back to Ollama: %s", result.get("error"))

        result = extract_receipt_ollama(image_base64)
        if "error" not in result:
            return result
        logger.info("Ollama OCR failed, falling back to Tesseract: %s", result.get("error"))

    if image_path:
        return extract_receipt_tesseract(image_path)

    return {
        "error": "No image data provided (need image_path or image_base64)",
        "method": "none",
        "needs_review": True,
    }
