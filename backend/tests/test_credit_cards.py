"""Tests for credit card CRUD endpoints."""

import pytest
from httpx import AsyncClient

from src.app.models.credit_card import CreditCard
from src.app.models.user import User


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

SAMPLE_CARD = {
    "card_name": "Chase Sapphire",
    "apr": 0.2499,
    "current_balance": 2500.00,
    "credit_limit": 10000.00,
}


# ---------------------------------------------------------------------------
# Unauthenticated access
# ---------------------------------------------------------------------------


async def test_list_credit_cards_unauthenticated(client: AsyncClient):
    """GET /api/v1/credit-cards/ without auth should return 401."""
    resp = await client.get("/api/v1/credit-cards/")
    assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Create credit card
# ---------------------------------------------------------------------------


async def test_create_credit_card(auth_client: AsyncClient, test_user: User):
    """POST /api/v1/credit-cards/ should create a card and return 201."""
    resp = await auth_client.post("/api/v1/credit-cards/", json=SAMPLE_CARD)
    assert resp.status_code == 201

    data = resp.json()
    assert data["card_name"] == "Chase Sapphire"
    assert data["apr"] == 0.2499
    assert data["current_balance"] == 2500.00
    assert data["credit_limit"] == 10000.00
    assert data["is_active"] is True
    assert "id" in data


# ---------------------------------------------------------------------------
# Utilization computation
# ---------------------------------------------------------------------------


async def test_utilization_computed_correctly(auth_client: AsyncClient, test_user: User):
    """Utilization should be (balance / limit) * 100, rounded to 2 decimals."""
    resp = await auth_client.post(
        "/api/v1/credit-cards/",
        json={
            "card_name": "Util Test Card",
            "apr": 0.1999,
            "current_balance": 3000.00,
            "credit_limit": 12000.00,
        },
    )
    assert resp.status_code == 201

    data = resp.json()
    # 3000 / 12000 * 100 = 25.0
    assert data["utilization"] == 25.0


async def test_utilization_none_when_no_limit(auth_client: AsyncClient, test_user: User):
    """Utilization should be None when no credit_limit is set."""
    resp = await auth_client.post(
        "/api/v1/credit-cards/",
        json={
            "card_name": "No Limit Card",
            "apr": 0.1599,
            "current_balance": 500.00,
        },
    )
    assert resp.status_code == 201
    assert resp.json()["utilization"] is None


# ---------------------------------------------------------------------------
# List credit cards
# ---------------------------------------------------------------------------


async def test_list_credit_cards(auth_client: AsyncClient, test_user: User):
    """GET /api/v1/credit-cards/ should return active cards for the user."""
    await auth_client.post("/api/v1/credit-cards/", json=SAMPLE_CARD)
    await auth_client.post(
        "/api/v1/credit-cards/",
        json={**SAMPLE_CARD, "card_name": "Amex Platinum"},
    )

    resp = await auth_client.get("/api/v1/credit-cards/")
    assert resp.status_code == 200

    data = resp.json()
    assert isinstance(data, list)
    assert len(data) == 2


# ---------------------------------------------------------------------------
# Delete credit card (soft delete)
# ---------------------------------------------------------------------------


async def test_delete_credit_card(auth_client: AsyncClient, test_user: User):
    """DELETE /api/v1/credit-cards/{id} should soft-delete the card."""
    create_resp = await auth_client.post("/api/v1/credit-cards/", json=SAMPLE_CARD)
    card_id = create_resp.json()["id"]

    del_resp = await auth_client.delete(f"/api/v1/credit-cards/{card_id}")
    assert del_resp.status_code == 204

    # Soft-deleted card should not appear in list
    list_resp = await auth_client.get("/api/v1/credit-cards/")
    ids = [c["id"] for c in list_resp.json()]
    assert card_id not in ids
