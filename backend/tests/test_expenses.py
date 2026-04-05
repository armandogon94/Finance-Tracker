"""Tests for expense CRUD endpoints."""

from datetime import date

import pytest
from httpx import AsyncClient

from src.app.models.category import Category
from src.app.models.user import User


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


async def _create_category(auth_client: AsyncClient, name: str = "Food") -> dict:
    """Helper to create a category and return its JSON."""
    resp = await auth_client.post(
        "/api/v1/categories/",
        json={"name": name},
    )
    assert resp.status_code == 201
    return resp.json()


# ---------------------------------------------------------------------------
# Unauthenticated access
# ---------------------------------------------------------------------------


async def test_list_expenses_unauthenticated(client: AsyncClient):
    """GET /api/v1/expenses without auth should return 401."""
    resp = await client.get("/api/v1/expenses/")
    assert resp.status_code == 401


async def test_create_expense_unauthenticated(client: AsyncClient):
    """POST /api/v1/expenses without auth should return 401."""
    resp = await client.post(
        "/api/v1/expenses/",
        json={"amount": 10.0, "description": "lunch"},
    )
    assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Create expense
# ---------------------------------------------------------------------------


async def test_create_expense(auth_client: AsyncClient, test_user: User):
    """POST /api/v1/expenses should create an expense and return 201."""
    resp = await auth_client.post(
        "/api/v1/expenses/",
        json={
            "amount": 42.50,
            "description": "Grocery run",
            "expense_date": "2025-03-15",
        },
    )
    assert resp.status_code == 201

    data = resp.json()
    assert data["amount"] == 42.50
    assert data["description"] == "Grocery run"
    assert data["expense_date"] == "2025-03-15"
    assert data["currency"] == "USD"
    assert "id" in data


async def test_create_expense_with_category(auth_client: AsyncClient, test_user: User):
    """POST /api/v1/expenses with a valid category_id should succeed."""
    cat = await _create_category(auth_client, "Groceries")

    resp = await auth_client.post(
        "/api/v1/expenses/",
        json={
            "amount": 15.99,
            "description": "Milk and eggs",
            "category_id": cat["id"],
        },
    )
    assert resp.status_code == 201
    assert resp.json()["category_id"] == cat["id"]


# ---------------------------------------------------------------------------
# List expenses
# ---------------------------------------------------------------------------


async def test_list_expenses_pagination_shape(auth_client: AsyncClient, test_user: User):
    """GET /api/v1/expenses should return the correct pagination envelope."""
    # Create a couple of expenses first
    await auth_client.post(
        "/api/v1/expenses/",
        json={"amount": 10.0, "description": "One"},
    )
    await auth_client.post(
        "/api/v1/expenses/",
        json={"amount": 20.0, "description": "Two"},
    )

    resp = await auth_client.get("/api/v1/expenses/")
    assert resp.status_code == 200

    data = resp.json()
    assert "items" in data
    assert "total" in data
    assert "page" in data
    assert "per_page" in data
    assert data["total"] == 2
    assert len(data["items"]) == 2


# ---------------------------------------------------------------------------
# Delete expense
# ---------------------------------------------------------------------------


async def test_delete_expense(auth_client: AsyncClient, test_user: User):
    """DELETE /api/v1/expenses/{id} should return 204 and remove the expense."""
    # Create
    create_resp = await auth_client.post(
        "/api/v1/expenses/",
        json={"amount": 5.00, "description": "Coffee"},
    )
    expense_id = create_resp.json()["id"]

    # Delete
    del_resp = await auth_client.delete(f"/api/v1/expenses/{expense_id}")
    assert del_resp.status_code == 204

    # Verify gone
    get_resp = await auth_client.get(f"/api/v1/expenses/{expense_id}")
    assert get_resp.status_code == 404


# ---------------------------------------------------------------------------
# Quick add
# ---------------------------------------------------------------------------


async def test_quick_add_expense(auth_client: AsyncClient, test_user: User):
    """POST /api/v1/expenses/quick should create an expense with amount + category."""
    cat = await _create_category(auth_client, "Transport")

    resp = await auth_client.post(
        "/api/v1/expenses/quick",
        json={
            "amount": 3.50,
            "category_id": cat["id"],
        },
    )
    assert resp.status_code == 201

    data = resp.json()
    assert data["amount"] == 3.50
    assert data["category_id"] == cat["id"]
    # Quick-add defaults to today
    assert data["expense_date"] == str(date.today())
