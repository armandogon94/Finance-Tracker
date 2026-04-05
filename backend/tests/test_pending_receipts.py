"""Tests for the pending receipt queue endpoints."""

from unittest.mock import patch

import pytest
from httpx import AsyncClient

# Import so SQLAlchemy registers the table with Base.metadata
from src.app.models.receipt import PendingReceipt
from src.app.models.user import User


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _fake_process_receipt_image(raw_bytes: bytes, user_id: str, expense_id: str) -> dict:
    """Mock replacement for process_receipt_image that skips actual file I/O."""
    return {
        "original_path": f"/tmp/receipts/{user_id}/{expense_id}_original.jpg",
        "thumb_path": f"/tmp/receipts/{user_id}/{expense_id}_thumb.jpg",
        "file_size": len(raw_bytes),
        "width": 800,
        "height": 600,
        "base64": "AAAA",
    }


# Minimal valid JPEG: SOI marker + bare JFIF header + EOI marker
# This is enough for content-type validation but we mock the image processor anyway.
MINIMAL_JPEG = (
    b"\xff\xd8\xff\xe0"  # SOI + APP0 marker
    b"\x00\x10JFIF\x00"  # JFIF header
    b"\x01\x01\x00\x00\x01\x00\x01\x00\x00"  # version, density
    b"\xff\xd9"  # EOI
)


# ---------------------------------------------------------------------------
# Unauthenticated access
# ---------------------------------------------------------------------------


async def test_queue_receipt_unauthenticated(client: AsyncClient):
    """POST /api/v1/receipts/queue without auth should return 401."""
    resp = await client.post(
        "/api/v1/receipts/queue",
        files={"file": ("receipt.jpg", MINIMAL_JPEG, "image/jpeg")},
    )
    assert resp.status_code == 401


async def test_list_pending_unauthenticated(client: AsyncClient):
    """GET /api/v1/receipts/pending without auth should return 401."""
    resp = await client.get("/api/v1/receipts/pending")
    assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Queue a receipt
# ---------------------------------------------------------------------------


@patch(
    "src.app.routers.receipts.process_receipt_image",
    side_effect=_fake_process_receipt_image,
)
async def test_queue_receipt(mock_proc, auth_client: AsyncClient, test_user: User):
    """POST /api/v1/receipts/queue should save a pending receipt and return 201."""
    resp = await auth_client.post(
        "/api/v1/receipts/queue",
        files={"file": ("receipt.jpg", MINIMAL_JPEG, "image/jpeg")},
    )
    assert resp.status_code == 201

    data = resp.json()
    assert data["status"] == "pending"
    assert "id" in data
    assert "created_at" in data
    mock_proc.assert_called_once()


# ---------------------------------------------------------------------------
# List pending receipts
# ---------------------------------------------------------------------------


@patch(
    "src.app.routers.receipts.process_receipt_image",
    side_effect=_fake_process_receipt_image,
)
async def test_list_pending_receipts(mock_proc, auth_client: AsyncClient, test_user: User):
    """GET /api/v1/receipts/pending should return the user's pending receipts."""
    # Queue two receipts
    await auth_client.post(
        "/api/v1/receipts/queue",
        files={"file": ("r1.jpg", MINIMAL_JPEG, "image/jpeg")},
    )
    await auth_client.post(
        "/api/v1/receipts/queue",
        files={"file": ("r2.jpg", MINIMAL_JPEG, "image/jpeg")},
    )

    resp = await auth_client.get("/api/v1/receipts/pending")
    assert resp.status_code == 200

    data = resp.json()
    assert isinstance(data, list)
    assert len(data) == 2
    # Each item should have the expected fields
    for item in data:
        assert "id" in item
        assert "status" in item
        assert item["status"] == "pending"


# ---------------------------------------------------------------------------
# Delete pending receipt
# ---------------------------------------------------------------------------


@patch(
    "src.app.routers.receipts.process_receipt_image",
    side_effect=_fake_process_receipt_image,
)
async def test_delete_pending_receipt(mock_proc, auth_client: AsyncClient, test_user: User):
    """DELETE /api/v1/receipts/pending/{id} should remove the pending receipt."""
    # Queue one
    create_resp = await auth_client.post(
        "/api/v1/receipts/queue",
        files={"file": ("receipt.jpg", MINIMAL_JPEG, "image/jpeg")},
    )
    pending_id = create_resp.json()["id"]

    # Delete it
    del_resp = await auth_client.delete(f"/api/v1/receipts/pending/{pending_id}")
    assert del_resp.status_code == 204

    # Should no longer appear in the list
    list_resp = await auth_client.get("/api/v1/receipts/pending")
    ids = [r["id"] for r in list_resp.json()]
    assert pending_id not in ids


# ---------------------------------------------------------------------------
# Edge case: unsupported content type
# ---------------------------------------------------------------------------


@patch(
    "src.app.routers.receipts.process_receipt_image",
    side_effect=_fake_process_receipt_image,
)
async def test_queue_receipt_rejects_non_image(
    mock_proc, auth_client: AsyncClient, test_user: User
):
    """POST /api/v1/receipts/queue with a non-image type should return 415."""
    resp = await auth_client.post(
        "/api/v1/receipts/queue",
        files={"file": ("doc.pdf", b"%PDF-1.4 fake", "application/pdf")},
    )
    assert resp.status_code == 415
    mock_proc.assert_not_called()
