"""Tests for the bank CSV parser service."""

import pytest

from src.app.services.csv_parser import detect_bank_format, parse_bank_csv


# ---------------------------------------------------------------------------
# Bank format detection
# ---------------------------------------------------------------------------


async def test_detect_chase_format():
    """Headers with Chase-specific columns should detect as 'chase'."""
    headers = ["Posting Date", "Description", "Amount", "Type", "Balance"]
    assert detect_bank_format(headers) == "chase"


async def test_detect_bofa_format():
    """Headers with BofA-specific columns should detect as 'bofa'."""
    headers = ["Date", "Payee", "Amount", "Type"]
    assert detect_bank_format(headers) == "bofa"


async def test_detect_generic_fallback():
    """Random/unknown headers should fall back to 'generic'."""
    headers = ["Column1", "Column2", "Column3"]
    assert detect_bank_format(headers) == "generic"


# ---------------------------------------------------------------------------
# CSV parsing
# ---------------------------------------------------------------------------


async def test_parse_chase_csv():
    """Parse a sample Chase CSV into normalized transaction dicts."""
    csv_content = (
        "Posting Date,Description,Amount,Type,Balance\n"
        "01/15/2025,STARBUCKS COFFEE,-4.50,Sale,1995.50\n"
        "01/14/2025,PAYROLL DIRECT DEP,2500.00,Credit,2000.00\n"
        "01/13/2025,AMAZON.COM,-29.99,Sale,500.00\n"
    )

    transactions = parse_bank_csv(csv_content, bank_preset="chase")

    assert len(transactions) == 3

    # First row: Starbucks expense
    t0 = transactions[0]
    assert t0["date"] == "2025-01-15"
    assert "STARBUCKS" in t0["description"]
    assert t0["amount"] == 4.50
    assert t0["is_expense"] is True

    # Second row: Payroll credit
    t1 = transactions[1]
    assert t1["date"] == "2025-01-14"
    assert "PAYROLL" in t1["description"]
    assert t1["amount"] == 2500.00
    assert t1["is_expense"] is False

    # Third row: Amazon expense
    t2 = transactions[2]
    assert t2["date"] == "2025-01-13"
    assert t2["amount"] == 29.99
    assert t2["is_expense"] is True


async def test_parse_bofa_csv():
    """Parse a sample BofA CSV with the Payee/Amount columns."""
    csv_content = (
        "Date,Payee,Amount,Type\n"
        "01/20/2025,GROCERY STORE,-85.23,Debit\n"
        "01/19/2025,SALARY DEPOSIT,3000.00,Credit\n"
    )

    transactions = parse_bank_csv(csv_content, bank_preset="bofa")

    assert len(transactions) == 2

    # Grocery expense (negative amount)
    t0 = transactions[0]
    assert t0["date"] == "2025-01-20"
    assert "GROCERY" in t0["description"]
    assert t0["amount"] == 85.23
    assert t0["is_expense"] is True

    # Salary deposit (positive amount)
    t1 = transactions[1]
    assert t1["amount"] == 3000.00
    assert t1["is_expense"] is False


async def test_empty_csv():
    """An empty CSV (headers only, no data rows) should return an empty list."""
    csv_content = "Date,Description,Amount\n"

    transactions = parse_bank_csv(csv_content, bank_preset="generic")

    assert transactions == []
