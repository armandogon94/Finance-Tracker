"""CRITICAL adversarial tests for multi-user data isolation.

Creates two independent users and verifies that each user's data is
invisible and inaccessible to the other.  Covers expenses, categories,
credit cards, analytics, and auto-label rules.
"""

import uuid
from datetime import date

import pytest
from httpx import ASGITransport, AsyncClient

from src.app.dependencies.auth import create_access_token, hash_password
from src.app.main import app
from src.app.models.category import Category
from src.app.models.credit_card import CreditCard
from src.app.models.expense import Expense
from src.app.models.user import User


# ─── Fixtures ──────────────────────────────────────────────────────


@pytest.fixture
async def user_a(db_session):
    user = User(
        id=uuid.uuid4(),
        email="alice@test.com",
        hashed_password=hash_password("alicepass"),
        display_name="Alice",
        is_active=True,
    )
    db_session.add(user)
    await db_session.commit()
    await db_session.refresh(user)
    return user


@pytest.fixture
async def user_b(db_session):
    user = User(
        id=uuid.uuid4(),
        email="bob@test.com",
        hashed_password=hash_password("bobpass"),
        display_name="Bob",
        is_active=True,
    )
    db_session.add(user)
    await db_session.commit()
    await db_session.refresh(user)
    return user


@pytest.fixture
async def client_a(user_a):
    token = create_access_token(user_a)
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as ac:
        ac.headers["Authorization"] = f"Bearer {token}"
        yield ac


@pytest.fixture
async def client_b(user_b):
    token = create_access_token(user_b)
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as ac:
        ac.headers["Authorization"] = f"Bearer {token}"
        yield ac


# ─── Helpers ───────────────────────────────────────────────────────


async def _create_category_api(client: AsyncClient, name: str) -> dict:
    resp = await client.post("/api/v1/categories/", json={"name": name})
    assert resp.status_code == 201
    return resp.json()


async def _create_expense_api(
    client: AsyncClient, amount: float, description: str,
    *, category_id: str | None = None,
) -> dict:
    payload: dict = {
        "amount": amount,
        "description": description,
        "expense_date": "2025-06-01",
    }
    if category_id:
        payload["category_id"] = category_id
    resp = await client.post("/api/v1/expenses/", json=payload)
    assert resp.status_code == 201
    return resp.json()


async def _create_credit_card_api(client: AsyncClient, card_name: str) -> dict:
    resp = await client.post(
        "/api/v1/credit-cards/",
        json={
            "card_name": card_name,
            "last_four": "1234",
            "current_balance": 1000.00,
            "apr": 0.1999,
        },
    )
    assert resp.status_code == 201
    return resp.json()


# ─── Expense isolation ─────────────────────────────────────────────


async def test_user_cannot_see_other_users_expenses(
    client_a, client_b, user_a, user_b, db_session
):
    """User A's expenses must not appear in User B's expense list."""
    # Create a category for User A
    cat_a = Category(user_id=user_a.id, name="Food", sort_order=0)
    db_session.add(cat_a)
    await db_session.flush()

    # Create an expense for User A
    exp_a = Expense(
        user_id=user_a.id,
        amount=42.50,
        description="Alice secret expense",
        expense_date=date(2026, 3, 15),
        category_id=cat_a.id,
    )
    db_session.add(exp_a)
    await db_session.commit()

    # User B should see 0 expenses
    resp = await client_b.get("/api/v1/expenses/")
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] == 0
    assert len(data["items"]) == 0

    # User A should see their expense
    resp_a = await client_a.get("/api/v1/expenses/")
    assert resp_a.status_code == 200
    data_a = resp_a.json()
    assert data_a["total"] == 1


async def test_user_cannot_access_other_users_expense_by_id(
    client_a, client_b, user_a, db_session
):
    """Direct GET by expense ID should return 404 for non-owner."""
    exp_a = Expense(
        user_id=user_a.id,
        amount=100.00,
        description="Private expense",
        expense_date=date(2026, 3, 15),
    )
    db_session.add(exp_a)
    await db_session.commit()
    await db_session.refresh(exp_a)

    # User B tries to access User A's expense
    resp = await client_b.get(f"/api/v1/expenses/{exp_a.id}")
    assert resp.status_code == 404


async def test_user_cannot_delete_other_users_expense(
    client_a, client_b, user_a, db_session
):
    """Delete should return 404 for non-owner, leaving expense intact."""
    exp_a = Expense(
        user_id=user_a.id,
        amount=55.00,
        description="Protected expense",
        expense_date=date(2026, 3, 15),
    )
    db_session.add(exp_a)
    await db_session.commit()
    await db_session.refresh(exp_a)

    # User B tries to delete User A's expense
    resp = await client_b.delete(f"/api/v1/expenses/{exp_a.id}")
    assert resp.status_code == 404

    # Verify expense still exists for User A
    resp_a = await client_a.get(f"/api/v1/expenses/{exp_a.id}")
    assert resp_a.status_code == 200


async def test_user_cannot_update_other_users_expense(
    client_a, client_b, user_a, db_session
):
    """PATCH should return 404 for non-owner, leaving expense unchanged."""
    exp_a = Expense(
        user_id=user_a.id,
        amount=30.00,
        description="Alice original",
        expense_date=date(2025, 6, 1),
    )
    db_session.add(exp_a)
    await db_session.commit()
    await db_session.refresh(exp_a)

    # User B tries to update User A's expense
    resp = await client_b.patch(
        f"/api/v1/expenses/{exp_a.id}",
        json={"description": "Hacked by Bob"},
    )
    assert resp.status_code == 404

    # Verify unchanged for User A
    resp_a = await client_a.get(f"/api/v1/expenses/{exp_a.id}")
    assert resp_a.status_code == 200
    assert resp_a.json()["description"] == "Alice original"


# ─── Category isolation ────────────────────────────────────────────


async def test_user_cannot_see_other_users_categories(
    client_a, client_b, user_a, user_b, db_session
):
    """User A's categories must not appear in User B's category list."""
    cat_a = Category(user_id=user_a.id, name="Alice Category", sort_order=0)
    cat_b = Category(user_id=user_b.id, name="Bob Category", sort_order=0)
    db_session.add_all([cat_a, cat_b])
    await db_session.commit()

    # User A sees only their category
    resp_a = await client_a.get("/api/v1/categories/")
    names_a = [c["name"] for c in resp_a.json()]
    assert "Alice Category" in names_a
    assert "Bob Category" not in names_a

    # User B sees only their category
    resp_b = await client_b.get("/api/v1/categories/")
    names_b = [c["name"] for c in resp_b.json()]
    assert "Bob Category" in names_b
    assert "Alice Category" not in names_b


async def test_user_cannot_use_other_users_category(
    client_a, client_b, user_a, user_b, db_session
):
    """User A cannot create an expense referencing User B's category."""
    cat_b = Category(user_id=user_b.id, name="Bob Private Cat", sort_order=0)
    db_session.add(cat_b)
    await db_session.commit()
    await db_session.refresh(cat_b)

    resp = await client_a.post(
        "/api/v1/expenses/",
        json={
            "amount": 10.00,
            "description": "Using Bob cat",
            "category_id": str(cat_b.id),
        },
    )
    assert resp.status_code == 404


# ─── Credit card isolation ─────────────────────────────────────────


async def test_user_cannot_see_other_users_credit_cards(
    client_a, client_b, user_a, user_b, db_session
):
    """User A's credit cards must not appear in User B's list."""
    card_a = CreditCard(
        user_id=user_a.id,
        card_name="Alice's Card",
        apr=0.2499,
        current_balance=5000.00,
    )
    card_b = CreditCard(
        user_id=user_b.id,
        card_name="Bob's Card",
        apr=0.1999,
        current_balance=3000.00,
    )
    db_session.add_all([card_a, card_b])
    await db_session.commit()

    # User A sees only their card
    resp_a = await client_a.get("/api/v1/credit-cards/")
    names_a = [c["card_name"] for c in resp_a.json()]
    assert "Alice's Card" in names_a
    assert "Bob's Card" not in names_a

    # User B sees only their card
    resp_b = await client_b.get("/api/v1/credit-cards/")
    names_b = [c["card_name"] for c in resp_b.json()]
    assert "Bob's Card" in names_b
    assert "Alice's Card" not in names_b


async def test_user_cannot_access_other_users_credit_card_by_id(
    client_a, client_b, user_a, user_b
):
    """User A cannot fetch User B's credit card by ID."""
    bob_card = await _create_credit_card_api(client_b, "Bob Mastercard")

    resp = await client_a.get(f"/api/v1/credit-cards/{bob_card['id']}")
    assert resp.status_code == 404


async def test_user_cannot_delete_other_users_credit_card(
    client_a, client_b, user_a, user_b
):
    """User A cannot soft-delete User B's credit card."""
    bob_card = await _create_credit_card_api(client_b, "Bob Discover")

    resp = await client_a.delete(f"/api/v1/credit-cards/{bob_card['id']}")
    assert resp.status_code == 404

    # Verify B's card still exists and is active
    resp_b = await client_b.get(f"/api/v1/credit-cards/{bob_card['id']}")
    assert resp_b.status_code == 200
    assert resp_b.json()["is_active"] is True


# ─── Analytics isolation ───────────────────────────────────────────


async def test_analytics_only_shows_own_data(
    client_a, client_b, user_a, user_b
):
    """Analytics endpoints only reflect the authenticated user's expenses."""
    await _create_expense_api(client_a, 100.00, "Alice analytics")
    await _create_expense_api(client_b, 999.00, "Bob analytics")

    # User A daily
    resp_a = await client_a.get(
        "/api/v1/analytics/daily",
        params={"start_date": "2025-06-01", "end_date": "2025-06-30"},
    )
    assert resp_a.status_code == 200
    data_a = resp_a.json()["data"]
    totals_a = sum(d["total"] for d in data_a)
    assert totals_a == 100.00

    # User B daily
    resp_b = await client_b.get(
        "/api/v1/analytics/daily",
        params={"start_date": "2025-06-01", "end_date": "2025-06-30"},
    )
    assert resp_b.status_code == 200
    data_b = resp_b.json()["data"]
    totals_b = sum(d["total"] for d in data_b)
    assert totals_b == 999.00


async def test_by_category_analytics_isolation(
    client_a, client_b, user_a, user_b
):
    """By-category analytics only includes the authenticated user's data."""
    cat_a = await _create_category_api(client_a, "Alice Cat")
    cat_b = await _create_category_api(client_b, "Bob Cat")

    await _create_expense_api(client_a, 50.00, "Alice food", category_id=cat_a["id"])
    await _create_expense_api(client_b, 75.00, "Bob food", category_id=cat_b["id"])

    resp_a = await client_a.get(
        "/api/v1/analytics/by-category",
        params={"start_date": "2025-06-01", "end_date": "2025-06-30"},
    )
    assert resp_a.status_code == 200
    names_a = [d["category_name"] for d in resp_a.json()["data"]]
    assert "Alice Cat" in names_a
    assert "Bob Cat" not in names_a


# ─── Auto-label rule isolation ─────────────────────────────────────


async def test_user_cannot_see_other_users_auto_label_rules(
    client_a, client_b, user_a, user_b
):
    """User A's auto-label rules are not visible to User B."""
    cat_a = await _create_category_api(client_a, "Alice Rule Cat")
    cat_b = await _create_category_api(client_b, "Bob Rule Cat")

    resp1 = await client_a.post(
        "/api/v1/auto-label/rules",
        json={"keyword": "alice_kw", "category_id": cat_a["id"]},
    )
    assert resp1.status_code == 201

    resp2 = await client_b.post(
        "/api/v1/auto-label/rules",
        json={"keyword": "bob_kw", "category_id": cat_b["id"]},
    )
    assert resp2.status_code == 201

    # User A sees only their rules
    resp_a = await client_a.get("/api/v1/auto-label/rules")
    keywords_a = [r["keyword"] for r in resp_a.json()]
    assert "alice_kw" in keywords_a
    assert "bob_kw" not in keywords_a

    # User B sees only their rules
    resp_b = await client_b.get("/api/v1/auto-label/rules")
    keywords_b = [r["keyword"] for r in resp_b.json()]
    assert "bob_kw" in keywords_b
    assert "alice_kw" not in keywords_b
