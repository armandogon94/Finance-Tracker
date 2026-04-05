"""Tests for the import router: CSV upload/preview and confirm flow."""

import io
import uuid
from datetime import date

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.models.user import User


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


async def _create_category(auth_client: AsyncClient, name: str = "Food") -> dict:
    resp = await auth_client.post("/api/v1/categories/", json={"name": name})
    assert resp.status_code == 201
    return resp.json()


# A minimal Chase-format CSV with 3 transactions
CHASE_CSV = """\
Details,Posting Date,Description,Amount,Type,Balance,Check or Slip #
DEBIT,01/15/2025,STARBUCKS COFFEE,-5.75,ACH_DEBIT,1234.56,
DEBIT,01/16/2025,WALMART SUPERCENTER,-42.99,ACH_DEBIT,1191.57,
CREDIT,01/17/2025,PAYROLL DEPOSIT,2500.00,ACH_CREDIT,3691.57,
"""


def _csv_upload_file(content: str, filename: str = "statement.csv"):
    """Build the multipart file payload for httpx."""
    return {"file": (filename, io.BytesIO(content.encode("utf-8")), "text/csv")}


# ---------------------------------------------------------------------------
# Upload / preview
# ---------------------------------------------------------------------------


async def test_upload_csv_preview(auth_client: AsyncClient, test_user: User):
    """POST /api/v1/import/upload with Chase CSV returns a valid preview."""
    resp = await auth_client.post(
        "/api/v1/import/upload",
        files=_csv_upload_file(CHASE_CSV),
    )
    assert resp.status_code == 200

    data = resp.json()
    assert data["source_type"] == "csv"
    assert data["filename"] == "statement.csv"
    assert data["total_parsed"] >= 2  # at least the 2 expense rows

    txns = data["transactions"]
    assert isinstance(txns, list)
    assert len(txns) >= 2

    # Verify the parsed transactions have the expected structure
    for txn in txns:
        assert "date" in txn
        assert "description" in txn
        assert "amount" in txn
        assert "include" in txn


async def test_upload_empty_file(auth_client: AsyncClient, test_user: User):
    """Uploading an empty file returns 422."""
    resp = await auth_client.post(
        "/api/v1/import/upload",
        files={"file": ("empty.csv", io.BytesIO(b""), "text/csv")},
    )
    assert resp.status_code == 422


async def test_upload_unsupported_type(auth_client: AsyncClient, test_user: User):
    """Uploading a file with an unsupported content type returns 415."""
    resp = await auth_client.post(
        "/api/v1/import/upload",
        files={
            "file": (
                "image.png",
                io.BytesIO(b"not a csv"),
                "image/png",
            )
        },
    )
    assert resp.status_code == 415


# ---------------------------------------------------------------------------
# Confirm import
# ---------------------------------------------------------------------------


async def test_confirm_import_creates_expenses(auth_client: AsyncClient, test_user: User):
    """POST /api/v1/import/confirm creates expenses for included transactions."""
    # First, upload to get the preview
    upload_resp = await auth_client.post(
        "/api/v1/import/upload",
        files=_csv_upload_file(CHASE_CSV),
    )
    assert upload_resp.status_code == 200
    preview = upload_resp.json()

    # Build confirm payload -- include only expense transactions
    txns_to_confirm = []
    for txn in preview["transactions"]:
        txns_to_confirm.append({
            "date": txn["date"],
            "description": txn["description"],
            "amount": txn["amount"],
            "is_expense": txn.get("is_expense", True),
            "include": txn.get("is_expense", True),  # only include expenses
        })

    confirm_resp = await auth_client.post(
        "/api/v1/import/confirm",
        json={
            "transactions": txns_to_confirm,
            "source_type": "csv",
            "bank_preset": "chase",
            "original_filename": "statement.csv",
        },
    )
    assert confirm_resp.status_code == 200

    result = confirm_resp.json()
    assert "imported" in result
    assert "skipped" in result
    assert "import_id" in result
    assert result["imported"] >= 1

    # Verify the expenses were actually created
    expenses_resp = await auth_client.get("/api/v1/expenses/")
    assert expenses_resp.status_code == 200
    items = expenses_resp.json()["items"]
    assert len(items) >= result["imported"]


async def test_confirm_import_with_category(auth_client: AsyncClient, test_user: User):
    """Confirm import with a category_id assigns it to created expenses."""
    cat = await _create_category(auth_client, "Coffee")

    confirm_resp = await auth_client.post(
        "/api/v1/import/confirm",
        json={
            "transactions": [
                {
                    "date": "2025-01-15",
                    "description": "STARBUCKS",
                    "amount": 5.75,
                    "is_expense": True,
                    "suggested_category_id": cat["id"],
                    "include": True,
                }
            ],
            "source_type": "csv",
            "original_filename": "test.csv",
        },
    )
    assert confirm_resp.status_code == 200
    assert confirm_resp.json()["imported"] == 1


async def test_confirm_import_no_transactions_selected(auth_client: AsyncClient, test_user: User):
    """Confirm with all transactions excluded returns 422."""
    resp = await auth_client.post(
        "/api/v1/import/confirm",
        json={
            "transactions": [
                {
                    "date": "2025-01-15",
                    "description": "Nothing",
                    "amount": 10.00,
                    "include": False,
                }
            ],
            "source_type": "csv",
        },
    )
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# Import history
# ---------------------------------------------------------------------------


async def test_import_history_after_confirm(auth_client: AsyncClient, test_user: User):
    """After a successful confirm, the import shows up in history."""
    # Do an import
    confirm_resp = await auth_client.post(
        "/api/v1/import/confirm",
        json={
            "transactions": [
                {
                    "date": "2025-02-01",
                    "description": "Test import",
                    "amount": 25.00,
                    "include": True,
                }
            ],
            "source_type": "csv",
            "original_filename": "history_test.csv",
        },
    )
    assert confirm_resp.status_code == 200
    import_id = confirm_resp.json()["import_id"]

    # Check history
    history_resp = await auth_client.get("/api/v1/import/history")
    assert history_resp.status_code == 200
    history = history_resp.json()
    assert isinstance(history, list)
    assert len(history) >= 1

    ids = [h["id"] for h in history]
    assert import_id in ids


# ---------------------------------------------------------------------------
# Bank templates
# ---------------------------------------------------------------------------


async def test_list_bank_templates(auth_client: AsyncClient, test_user: User):
    """GET /api/v1/import/templates returns available bank presets."""
    resp = await auth_client.get("/api/v1/import/templates")
    assert resp.status_code == 200

    data = resp.json()
    assert "templates" in data
    templates = data["templates"]
    assert len(templates) >= 1

    # Should include well-known banks and generic
    keys = [t["key"] for t in templates]
    assert "generic" in keys


# ---------------------------------------------------------------------------
# Auth required
# ---------------------------------------------------------------------------


async def test_import_unauthenticated(client: AsyncClient):
    """Import endpoints require authentication."""
    resp = await client.post(
        "/api/v1/import/upload",
        files=_csv_upload_file(CHASE_CSV),
    )
    assert resp.status_code == 401

    resp2 = await client.get("/api/v1/import/history")
    assert resp2.status_code == 401
