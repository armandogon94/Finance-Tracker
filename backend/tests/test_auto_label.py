"""Tests for auto-label rule CRUD, matching, and learn endpoints."""

import uuid

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


async def _create_rule(
    auth_client: AsyncClient,
    keyword: str,
    category_id: str,
    *,
    priority: int = 100,
    assign_hidden: bool = False,
) -> dict:
    resp = await auth_client.post(
        "/api/v1/auto-label/rules",
        json={
            "keyword": keyword,
            "category_id": category_id,
            "priority": priority,
            "assign_hidden": assign_hidden,
        },
    )
    assert resp.status_code == 201
    return resp.json()


# ---------------------------------------------------------------------------
# List rules
# ---------------------------------------------------------------------------


async def test_list_rules_empty(auth_client: AsyncClient, test_user: User):
    """GET /api/v1/auto-label/rules with no rules returns empty list."""
    resp = await auth_client.get("/api/v1/auto-label/rules")
    assert resp.status_code == 200
    assert resp.json() == []


async def test_list_rules_returns_active_only(auth_client: AsyncClient, test_user: User):
    """By default list returns only active rules."""
    cat = await _create_category(auth_client)
    rule = await _create_rule(auth_client, "starbucks", cat["id"])

    # Deactivate the rule
    await auth_client.patch(
        f"/api/v1/auto-label/rules/{rule['id']}",
        json={"is_active": False},
    )

    # Default list should be empty
    resp = await auth_client.get("/api/v1/auto-label/rules")
    assert resp.status_code == 200
    assert len(resp.json()) == 0

    # With include_inactive it should appear
    resp2 = await auth_client.get(
        "/api/v1/auto-label/rules", params={"include_inactive": True}
    )
    assert resp2.status_code == 200
    assert len(resp2.json()) == 1


# ---------------------------------------------------------------------------
# Create rule
# ---------------------------------------------------------------------------


async def test_create_rule(auth_client: AsyncClient, test_user: User):
    """POST /api/v1/auto-label/rules creates a rule and returns 201."""
    cat = await _create_category(auth_client, "Coffee")
    rule = await _create_rule(auth_client, "starbucks", cat["id"], priority=10)

    assert rule["keyword"] == "starbucks"
    assert rule["category_id"] == cat["id"]
    assert rule["priority"] == 10
    assert rule["assign_hidden"] is False
    assert rule["is_active"] is True
    assert "id" in rule


async def test_create_rule_invalid_category(auth_client: AsyncClient, test_user: User):
    """Creating a rule with a non-existent category returns 404."""
    fake_cat_id = str(uuid.uuid4())
    resp = await auth_client.post(
        "/api/v1/auto-label/rules",
        json={"keyword": "amazon", "category_id": fake_cat_id},
    )
    assert resp.status_code == 404


async def test_create_rule_duplicate_keyword(auth_client: AsyncClient, test_user: User):
    """Creating a rule with a duplicate keyword returns 409."""
    cat = await _create_category(auth_client, "Shopping")
    await _create_rule(auth_client, "amazon", cat["id"])

    resp = await auth_client.post(
        "/api/v1/auto-label/rules",
        json={"keyword": "amazon", "category_id": cat["id"]},
    )
    assert resp.status_code == 409


# ---------------------------------------------------------------------------
# Update rule
# ---------------------------------------------------------------------------


async def test_update_rule_keyword(auth_client: AsyncClient, test_user: User):
    """PATCH /api/v1/auto-label/rules/{id} updates fields."""
    cat = await _create_category(auth_client, "Gas")
    rule = await _create_rule(auth_client, "shell", cat["id"])

    resp = await auth_client.patch(
        f"/api/v1/auto-label/rules/{rule['id']}",
        json={"keyword": "chevron", "priority": 5},
    )
    assert resp.status_code == 200
    updated = resp.json()
    assert updated["keyword"] == "chevron"
    assert updated["priority"] == 5


async def test_update_rule_no_fields(auth_client: AsyncClient, test_user: User):
    """PATCH with no fields returns 422."""
    cat = await _create_category(auth_client, "Misc")
    rule = await _create_rule(auth_client, "walgreens", cat["id"])

    resp = await auth_client.patch(
        f"/api/v1/auto-label/rules/{rule['id']}",
        json={},
    )
    assert resp.status_code == 422


async def test_update_rule_not_found(auth_client: AsyncClient, test_user: User):
    """PATCH for non-existent rule returns 404."""
    fake_id = uuid.uuid4()
    resp = await auth_client.patch(
        f"/api/v1/auto-label/rules/{fake_id}",
        json={"keyword": "nope"},
    )
    assert resp.status_code == 404


async def test_update_rule_duplicate_keyword(auth_client: AsyncClient, test_user: User):
    """Renaming a rule to an existing keyword returns 409."""
    cat = await _create_category(auth_client, "Utilities")
    await _create_rule(auth_client, "electric", cat["id"])
    rule2 = await _create_rule(auth_client, "water", cat["id"])

    resp = await auth_client.patch(
        f"/api/v1/auto-label/rules/{rule2['id']}",
        json={"keyword": "electric"},
    )
    assert resp.status_code == 409


# ---------------------------------------------------------------------------
# Delete rule
# ---------------------------------------------------------------------------


async def test_delete_rule(auth_client: AsyncClient, test_user: User):
    """DELETE /api/v1/auto-label/rules/{id} permanently removes the rule."""
    cat = await _create_category(auth_client, "Subscriptions")
    rule = await _create_rule(auth_client, "netflix", cat["id"])

    resp = await auth_client.delete(f"/api/v1/auto-label/rules/{rule['id']}")
    assert resp.status_code == 204

    # Verify gone
    resp2 = await auth_client.get("/api/v1/auto-label/rules")
    assert all(r["id"] != rule["id"] for r in resp2.json())


async def test_delete_rule_not_found(auth_client: AsyncClient, test_user: User):
    """DELETE non-existent rule returns 404."""
    fake_id = uuid.uuid4()
    resp = await auth_client.delete(f"/api/v1/auto-label/rules/{fake_id}")
    assert resp.status_code == 404


# ---------------------------------------------------------------------------
# Test (match a description against rules)
# ---------------------------------------------------------------------------


async def test_test_description_match(auth_client: AsyncClient, test_user: User):
    """POST /api/v1/auto-label/test matches a description against rules."""
    cat = await _create_category(auth_client, "Coffee")
    await _create_rule(auth_client, "starbucks", cat["id"])

    resp = await auth_client.post(
        "/api/v1/auto-label/test",
        json={"description": "CHECKCARD STARBUCKS #12345"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["matched"] is True
    assert data["rule_keyword"] == "starbucks"
    assert data["category_id"] == cat["id"]


async def test_test_description_no_match(auth_client: AsyncClient, test_user: User):
    """POST /api/v1/auto-label/test with no matching rule returns matched=False."""
    cat = await _create_category(auth_client, "Food")
    await _create_rule(auth_client, "chipotle", cat["id"])

    resp = await auth_client.post(
        "/api/v1/auto-label/test",
        json={"description": "PAYMENT TO AMAZON PRIME"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["matched"] is False
    assert data["rule_keyword"] is None
    assert data["category_id"] is None


async def test_test_description_priority_order(auth_client: AsyncClient, test_user: User):
    """Rules with lower priority number match first."""
    cat_grocery = await _create_category(auth_client, "Grocery")
    cat_general = await _create_category(auth_client, "General")

    # "walmart" at priority 10 -> Grocery
    await _create_rule(auth_client, "walmart", cat_grocery["id"], priority=10)
    # "wal" at priority 50 -> General (would also match "walmart" text)
    await _create_rule(auth_client, "wal", cat_general["id"], priority=50)

    resp = await auth_client.post(
        "/api/v1/auto-label/test",
        json={"description": "POS DEBIT WALMART SUPERCENTER"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["matched"] is True
    # Lower priority number wins
    assert data["rule_keyword"] == "walmart"
    assert data["category_id"] == cat_grocery["id"]


async def test_test_description_case_insensitive(auth_client: AsyncClient, test_user: User):
    """Matching is case-insensitive."""
    cat = await _create_category(auth_client, "Dining")
    await _create_rule(auth_client, "McDonalds", cat["id"])

    resp = await auth_client.post(
        "/api/v1/auto-label/test",
        json={"description": "POS MCDONALDS #4521"},
    )
    assert resp.status_code == 200
    assert resp.json()["matched"] is True


# ---------------------------------------------------------------------------
# Learn (suggest a rule from a description)
# ---------------------------------------------------------------------------


async def test_learn_suggest_rule(auth_client: AsyncClient, test_user: User):
    """POST /api/v1/auto-label/learn extracts a keyword and suggests a rule."""
    cat = await _create_category(auth_client, "Restaurants")

    resp = await auth_client.post(
        "/api/v1/auto-label/learn",
        json={
            "description": "POS DEBIT CHILIS RESTAURANT 03/29",
            "category_id": cat["id"],
        },
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "suggested_keyword" in data
    assert data["category_id"] == cat["id"]
    assert "prompt" in data
    # The keyword should be a non-empty string
    assert len(data["suggested_keyword"]) > 0


async def test_learn_invalid_category(auth_client: AsyncClient, test_user: User):
    """Learn with non-existent category returns 404."""
    fake_id = str(uuid.uuid4())
    resp = await auth_client.post(
        "/api/v1/auto-label/learn",
        json={"description": "SOME TRANSACTION", "category_id": fake_id},
    )
    assert resp.status_code == 404


async def test_learn_existing_keyword(auth_client: AsyncClient, test_user: User):
    """Learn warns if the suggested keyword already has a rule."""
    cat = await _create_category(auth_client, "Coffee")

    # First, learn to get the suggested keyword
    resp1 = await auth_client.post(
        "/api/v1/auto-label/learn",
        json={"description": "STARBUCKS COFFEE #9876", "category_id": cat["id"]},
    )
    suggested = resp1.json()["suggested_keyword"]

    # Create a rule with that keyword
    await _create_rule(auth_client, suggested, cat["id"])

    # Learn again -- should mention the keyword already exists
    resp2 = await auth_client.post(
        "/api/v1/auto-label/learn",
        json={"description": "STARBUCKS COFFEE #9876", "category_id": cat["id"]},
    )
    assert resp2.status_code == 200
    assert "already exists" in resp2.json()["prompt"]


# ---------------------------------------------------------------------------
# Auth required
# ---------------------------------------------------------------------------


async def test_auto_label_unauthenticated(client: AsyncClient):
    """All auto-label endpoints require authentication."""
    resp = await client.get("/api/v1/auto-label/rules")
    assert resp.status_code == 401

    resp2 = await client.post(
        "/api/v1/auto-label/rules",
        json={"keyword": "test", "category_id": str(uuid.uuid4())},
    )
    assert resp2.status_code == 401

    resp3 = await client.post(
        "/api/v1/auto-label/test",
        json={"description": "test"},
    )
    assert resp3.status_code == 401
