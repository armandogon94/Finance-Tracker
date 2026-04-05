"""Tests for category CRUD endpoints."""

import pytest
from httpx import AsyncClient

from src.app.models.user import User


# ---------------------------------------------------------------------------
# Unauthenticated access
# ---------------------------------------------------------------------------


async def test_list_categories_unauthenticated(client: AsyncClient):
    """GET /api/v1/categories without auth should return 401."""
    resp = await client.get("/api/v1/categories/")
    assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Create category
# ---------------------------------------------------------------------------


async def test_create_category(auth_client: AsyncClient, test_user: User):
    """POST /api/v1/categories should create a category and return 201."""
    resp = await auth_client.post(
        "/api/v1/categories/",
        json={"name": "Food"},
    )
    assert resp.status_code == 201

    data = resp.json()
    assert data["name"] == "Food"
    assert data["icon"] == "receipt"  # default
    assert data["color"] == "#3B82F6"  # default
    assert data["is_active"] is True
    assert data["is_hidden"] is False
    assert "id" in data


async def test_create_category_with_options(auth_client: AsyncClient, test_user: User):
    """POST /api/v1/categories with custom icon, color, budget should work."""
    resp = await auth_client.post(
        "/api/v1/categories/",
        json={
            "name": "Entertainment",
            "icon": "movie",
            "color": "#EF4444",
            "monthly_budget": 150.00,
        },
    )
    assert resp.status_code == 201

    data = resp.json()
    assert data["name"] == "Entertainment"
    assert data["icon"] == "movie"
    assert data["color"] == "#EF4444"
    assert data["monthly_budget"] == 150.00


async def test_create_duplicate_category_returns_409(
    auth_client: AsyncClient, test_user: User
):
    """Creating a category with an already-existing name should return 409."""
    await auth_client.post("/api/v1/categories/", json={"name": "Rent"})
    resp = await auth_client.post("/api/v1/categories/", json={"name": "Rent"})
    assert resp.status_code == 409


# ---------------------------------------------------------------------------
# List categories
# ---------------------------------------------------------------------------


async def test_list_categories(auth_client: AsyncClient, test_user: User):
    """GET /api/v1/categories should return a list of the user's categories."""
    await auth_client.post("/api/v1/categories/", json={"name": "Alpha"})
    await auth_client.post("/api/v1/categories/", json={"name": "Beta"})

    resp = await auth_client.get("/api/v1/categories/")
    assert resp.status_code == 200

    data = resp.json()
    assert isinstance(data, list)
    assert len(data) == 2
    names = {c["name"] for c in data}
    assert names == {"Alpha", "Beta"}


# ---------------------------------------------------------------------------
# Delete (soft-delete) category
# ---------------------------------------------------------------------------


async def test_delete_category(auth_client: AsyncClient, test_user: User):
    """DELETE /api/v1/categories/{id} should soft-delete the category."""
    create_resp = await auth_client.post(
        "/api/v1/categories/", json={"name": "Temporary"}
    )
    cat_id = create_resp.json()["id"]

    del_resp = await auth_client.delete(f"/api/v1/categories/{cat_id}")
    assert del_resp.status_code == 204

    # Should no longer appear in default listing
    list_resp = await auth_client.get("/api/v1/categories/")
    ids = [c["id"] for c in list_resp.json()]
    assert cat_id not in ids


# ---------------------------------------------------------------------------
# Hidden categories
# ---------------------------------------------------------------------------


async def test_create_hidden_category(auth_client: AsyncClient, test_user: User):
    """Creating a hidden category should store is_hidden=True."""
    resp = await auth_client.post(
        "/api/v1/categories/",
        json={"name": "Secret Stash", "is_hidden": True},
    )
    assert resp.status_code == 201
    assert resp.json()["is_hidden"] is True
