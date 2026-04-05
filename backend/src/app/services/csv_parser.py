"""
Bank CSV parser service.

Auto-detects bank format from CSV headers, normalizes transactions into a
common schema, and handles the quirks of each bank's export format.
"""

import logging
import re
from datetime import datetime
from io import StringIO
from typing import Any

import pandas as pd

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Bank column mappings
# ---------------------------------------------------------------------------
# Each entry maps our canonical fields to the bank's actual CSV column names.
# "date_format" is the strptime format the bank uses for dates.

BANK_COLUMN_MAPS: dict[str, dict[str, Any]] = {
    "chase": {
        "date": "Posting Date",
        "description": "Description",
        "amount": "Amount",
        "type": "Type",
        "date_format": "%m/%d/%Y",
        # Chase: negative = expense, positive = payment/credit
        "negate": False,
    },
    "bofa": {
        "date": "Date",
        "description": "Payee",
        "amount": "Amount",
        "type": "Type",
        "date_format": "%m/%d/%Y",
        "negate": False,
    },
    "wells_fargo": {
        "date": "Date",
        "description": "Description",
        "amount": "Amount",
        "date_format": "%m/%d/%Y",
        "negate": False,
    },
    "citi": {
        "date": "Date",
        "description": "Description",
        "amount": "Debit",  # Citi splits Debit / Credit into separate columns
        "credit": "Credit",
        "date_format": "%m/%d/%Y",
        "negate": False,
    },
    "discover": {
        "date": "Trans. Date",
        "description": "Description",
        "amount": "Amount",
        "date_format": "%m/%d/%Y",
        # Discover: positive = expense, negative = credit/payment
        "negate": True,
    },
    "generic": {
        # Fallback: use positional column indices
        "date": 0,
        "description": 1,
        "amount": 2,
        "date_format": None,  # auto-detect
        "negate": False,
    },
}

# Keyword sets used for auto-detection of bank format
_BANK_HEADER_SIGNATURES: dict[str, set[str]] = {
    "chase": {"posting date", "description", "amount", "type", "balance"},
    "bofa": {"date", "payee", "amount", "type"},
    "wells_fargo": {"date", "description", "amount"},
    "citi": {"date", "description", "debit", "credit", "status"},
    "discover": {"trans. date", "post date", "description", "amount", "category"},
}


# ---------------------------------------------------------------------------
# Auto-detection
# ---------------------------------------------------------------------------

def detect_bank_format(headers: list[str]) -> str:
    """Auto-detect bank format by matching CSV header names against known signatures.

    Args:
        headers: List of column header strings from the CSV.

    Returns:
        Bank preset key (e.g. "chase", "bofa") or "generic" if unknown.
    """
    normalized = {h.strip().lower() for h in headers}

    best_match = "generic"
    best_score = 0

    for bank, signature in _BANK_HEADER_SIGNATURES.items():
        overlap = len(signature & normalized)
        # Require at least 2 matching headers and beat previous best
        if overlap >= 2 and overlap > best_score:
            best_score = overlap
            best_match = bank

    logger.info("Detected bank format: %s (score=%d, headers=%s)", best_match, best_score, headers)
    return best_match


# ---------------------------------------------------------------------------
# Amount / date helpers
# ---------------------------------------------------------------------------

def _parse_amount(raw: str) -> float:
    """Parse a monetary string into a float.

    Handles: "$1,234.56", "(1234.56)", "-1234.56", "1234.56 CR", etc.
    """
    if not raw or str(raw).strip().lower() in ("", "nan", "none"):
        return 0.0

    text = str(raw).strip()

    # Detect credit indicators
    is_credit = False
    if text.upper().endswith("CR"):
        is_credit = True
        text = text[:-2].strip()

    # Parentheses indicate negative in accounting format
    if text.startswith("(") and text.endswith(")"):
        text = "-" + text[1:-1]

    # Strip currency symbols, commas, whitespace
    text = re.sub(r"[$ ,]", "", text)

    try:
        value = float(text)
    except ValueError:
        logger.warning("Could not parse amount: %r", raw)
        return 0.0

    if is_credit:
        value = abs(value)
    return value


def _parse_date(raw: str, fmt: str | None = None) -> str:
    """Parse a date string and return YYYY-MM-DD format.

    If fmt is provided, use it directly. Otherwise try common formats.
    """
    text = str(raw).strip()
    if not text or text.lower() in ("nan", "none"):
        return ""

    formats_to_try = [fmt] if fmt else [
        "%m/%d/%Y",
        "%m/%d/%y",
        "%Y-%m-%d",
        "%m-%d-%Y",
        "%d/%m/%Y",
        "%d-%m-%Y",
        "%Y/%m/%d",
        "%b %d, %Y",
        "%B %d, %Y",
        "%d %b %Y",
        "%d %B %Y",
    ]

    for date_fmt in formats_to_try:
        if date_fmt is None:
            continue
        try:
            dt = datetime.strptime(text, date_fmt)
            return dt.strftime("%Y-%m-%d")
        except ValueError:
            continue

    # Last resort: let pandas try
    try:
        dt = pd.to_datetime(text)
        return dt.strftime("%Y-%m-%d")
    except Exception:
        logger.warning("Could not parse date: %r", raw)
        return text


# ---------------------------------------------------------------------------
# Core parser
# ---------------------------------------------------------------------------

def parse_bank_csv(content: str, bank_preset: str = "auto") -> list[dict[str, Any]]:
    """Parse bank CSV content into a normalized list of transaction dicts.

    Each transaction dict contains:
        date          - YYYY-MM-DD string
        description   - Transaction description
        amount        - Absolute dollar amount (always positive)
        is_expense    - True if money went out, False if money came in
        needs_categorization - Always True (user reviews after import)
        raw_amount    - Original signed amount for debugging

    Args:
        content:      Raw CSV file content as a string.
        bank_preset:  Bank format key, or "auto" for auto-detection.

    Returns:
        List of normalized transaction dicts.
    """
    try:
        df = pd.read_csv(StringIO(content))
    except Exception as exc:
        logger.error("Failed to read CSV: %s", exc)
        raise ValueError(f"Invalid CSV format: {str(exc)}") from exc

    # Strip whitespace from column headers
    df.columns = [col.strip() for col in df.columns]

    # Auto-detect bank if needed
    if bank_preset == "auto":
        bank_preset = detect_bank_format(df.columns.tolist())

    col_map = BANK_COLUMN_MAPS.get(bank_preset, BANK_COLUMN_MAPS["generic"])
    date_fmt = col_map.get("date_format")
    should_negate = col_map.get("negate", False)

    transactions: list[dict[str, Any]] = []

    for _, row in df.iterrows():
        try:
            # Resolve column reference (name or index)
            date_col = col_map["date"]
            desc_col = col_map["description"]
            amount_col = col_map["amount"]

            if isinstance(date_col, int):
                raw_date = str(row.iloc[date_col])
                raw_desc = str(row.iloc[desc_col])
                raw_amount = str(row.iloc[amount_col])
            else:
                raw_date = str(row.get(date_col, ""))
                raw_desc = str(row.get(desc_col, ""))
                raw_amount = str(row.get(amount_col, ""))

            # Citi-specific: merge Debit and Credit columns
            if bank_preset == "citi":
                credit_col = col_map.get("credit", "Credit")
                raw_credit = str(row.get(credit_col, ""))
                debit_amount = _parse_amount(raw_amount)
                credit_amount = _parse_amount(raw_credit)
                # Debit is expense, Credit is income
                if debit_amount and debit_amount != 0:
                    amount = -abs(debit_amount)
                elif credit_amount and credit_amount != 0:
                    amount = abs(credit_amount)
                else:
                    amount = 0.0
            else:
                amount = _parse_amount(raw_amount)

            if should_negate:
                amount = -amount

            # Skip rows with no meaningful data
            if amount == 0.0 and not raw_desc.strip():
                continue

            parsed_date = _parse_date(raw_date, date_fmt)

            transactions.append({
                "date": parsed_date,
                "description": raw_desc.strip(),
                "amount": round(abs(amount), 2),
                "is_expense": amount < 0,
                "raw_amount": round(amount, 2),
                "needs_categorization": True,
            })

        except Exception as exc:
            logger.warning("Skipping unparseable row %s: %s", row.to_dict(), exc)
            continue

    logger.info(
        "Parsed %d transactions from CSV (bank=%s, total_rows=%d)",
        len(transactions),
        bank_preset,
        len(df),
    )
    return transactions
