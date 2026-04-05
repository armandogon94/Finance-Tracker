"""Tests for analytics endpoints (daily, monthly, by-category, budget-status).

NOTE: The weekly endpoint uses EXTRACT(isoyear/week) which is PostgreSQL-specific
and will NOT work with SQLite.  We skip it intentionally.
"""

import uuid
from datetime import date

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.models.category import Category
from src.app.models.expense import Expense
from src.app.models.user import User


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


async def _create_category(
    auth_client: AsyncClient, name: str, *, monthly_budget: float | None = None
) -> dict:
    payload: dict = {"name": name}
    if monthly_budget is not None:
        payload["monthly_budget"] = monthly_budget
    resp = await auth_client.post("/api/v1/categories/", json=payload)
    assert resp.status_code == 201
    return resp.json()


async def _create_expense(
    auth_client: AsyncClient,
    amount: float,
    expense_date: str,
    *,
    description: str = "test expense",
    category_id: str | None = None,
) -> dict:
    payload: dict = {
        "amount": amount,
        "description": description,
        "expense_date": expense_date,
    }
    if category_id is not None:
        payload["category_id"] = category_id
    resp = await auth_client.post("/api/v1/expenses/", json=payload)
    assert resp.status_code == 201
    return resp.json()


# ---------------------------------------------------------------------------
# Daily spending
# ---------------------------------------------------------------------------


async def test_daily_spending_empty(auth_client: AsyncClient, test_user: User):
    """Daily spending with no expenses returns empty data list."""
    resp = await auth_client.get(
        "/api/v1/analytics/daily",
        params={"start_date": "2025-01-01", "end_date": "2025-01-31"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["data"] == []
    assert data["start_date"] == "2025-01-01"
    assert data["end_date"] == "2025-01-31"


async def test_daily_spending_with_expenses(auth_client: AsyncClient, test_user: User):
    """Daily spending aggregates correctly across multiple days."""
    await _create_expense(auth_client, 10.00, "2025-03-01")
    await _create_expense(auth_client, 20.00, "2025-03-01")
    await _create_expense(auth_client, 15.00, "2025-03-02")

    resp = await auth_client.get(
        "/api/v1/analytics/daily",
        params={"start_date": "2025-03-01", "end_date": "2025-03-02"},
    )
    assert resp.status_code == 200

    rows = resp.json()["data"]
    assert len(rows) == 2

    day1 = rows[0]
    assert day1["date"] == "2025-03-01"
    assert day1["total"] == 30.00
    assert day1["count"] == 2

    day2 = rows[1]
    assert day2["date"] == "2025-03-02"
    assert day2["total"] == 15.00
    assert day2["count"] == 1


async def test_daily_spending_date_validation(auth_client: AsyncClient, test_user: User):
    """Daily spending rejects end_date before start_date."""
    resp = await auth_client.get(
        "/api/v1/analytics/daily",
        params={"start_date": "2025-03-10", "end_date": "2025-03-01"},
    )
    assert resp.status_code == 422


async def test_daily_spending_category_filter(auth_client: AsyncClient, test_user: User):
    """Daily spending can filter by category_id."""
    cat = await _create_category(auth_client, "Food")
    await _create_expense(auth_client, 10.00, "2025-04-01", category_id=cat["id"])
    await _create_expense(auth_client, 99.00, "2025-04-01")  # no category

    resp = await auth_client.get(
        "/api/v1/analytics/daily",
        params={
            "start_date": "2025-04-01",
            "end_date": "2025-04-01",
            "category_id": cat["id"],
        },
    )
    assert resp.status_code == 200
    rows = resp.json()["data"]
    assert len(rows) == 1
    assert rows[0]["total"] == 10.00


# ---------------------------------------------------------------------------
# Weekly spending -- SKIPPED (PostgreSQL-specific EXTRACT)
# ---------------------------------------------------------------------------


@pytest.mark.skip(reason="Weekly uses EXTRACT(isoyear/week) which is PostgreSQL-only")
async def test_weekly_spending(auth_client: AsyncClient, test_user: User):
    pass


# ---------------------------------------------------------------------------
# Monthly spending
# ---------------------------------------------------------------------------


async def test_monthly_spending_empty(auth_client: AsyncClient, test_user: User):
    """Monthly spending for a year with no expenses returns 12 zero-rows."""
    resp = await auth_client.get(
        "/api/v1/analytics/monthly",
        params={"year": 2099},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["year"] == 2099
    assert len(data["data"]) == 12
    assert data["grand_total"] == 0.0
    for entry in data["data"]:
        assert entry["total"] == 0.0
        assert entry["count"] == 0


async def test_monthly_spending_with_expenses(auth_client: AsyncClient, test_user: User):
    """Monthly spending aggregates correctly across months."""
    await _create_expense(auth_client, 100.00, "2025-01-15")
    await _create_expense(auth_client, 200.00, "2025-01-20")
    await _create_expense(auth_client, 50.00, "2025-03-10")

    resp = await auth_client.get(
        "/api/v1/analytics/monthly",
        params={"year": 2025},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["year"] == 2025
    assert data["grand_total"] == 350.00

    # January (index 0): 300
    jan = data["data"][0]
    assert jan["month"] == 1
    assert jan["total"] == 300.00
    assert jan["count"] == 2

    # March (index 2): 50
    mar = data["data"][2]
    assert mar["month"] == 3
    assert mar["total"] == 50.00
    assert mar["count"] == 1

    # February should be zero
    feb = data["data"][1]
    assert feb["total"] == 0.0
    assert feb["count"] == 0


# ---------------------------------------------------------------------------
# Spending by category
# ---------------------------------------------------------------------------


async def test_by_category_empty(auth_client: AsyncClient, test_user: User):
    """By-category with no expenses returns empty data."""
    resp = await auth_client.get(
        "/api/v1/analytics/by-category",
        params={"start_date": "2025-01-01", "end_date": "2025-12-31"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["data"] == []
    assert data["grand_total"] == 0.0


async def test_by_category_with_expenses(auth_client: AsyncClient, test_user: User):
    """By-category groups expenses and computes percentages."""
    cat_food = await _create_category(auth_client, "Food")
    cat_transport = await _create_category(auth_client, "Transport")

    await _create_expense(auth_client, 60.00, "2025-06-01", category_id=cat_food["id"])
    await _create_expense(auth_client, 40.00, "2025-06-02", category_id=cat_transport["id"])

    resp = await auth_client.get(
        "/api/v1/analytics/by-category",
        params={"start_date": "2025-06-01", "end_date": "2025-06-30"},
    )
    assert resp.status_code == 200

    data = resp.json()
    assert data["grand_total"] == 100.00
    assert len(data["data"]) == 2

    # Sorted descending by total, so Food (60) first
    food_entry = data["data"][0]
    assert food_entry["category_name"] == "Food"
    assert food_entry["total"] == 60.00
    assert food_entry["percentage"] == 60.0

    transport_entry = data["data"][1]
    assert transport_entry["category_name"] == "Transport"
    assert transport_entry["total"] == 40.00
    assert transport_entry["percentage"] == 40.0


async def test_by_category_uncategorized(auth_client: AsyncClient, test_user: User):
    """Expenses without a category show up as 'Uncategorized'."""
    await _create_expense(auth_client, 25.00, "2025-07-01")

    resp = await auth_client.get(
        "/api/v1/analytics/by-category",
        params={"start_date": "2025-07-01", "end_date": "2025-07-31"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["data"]) == 1
    assert data["data"][0]["category_name"] == "Uncategorized"
    assert data["data"][0]["category_id"] is None


async def test_by_category_date_validation(auth_client: AsyncClient, test_user: User):
    """By-category rejects end_date before start_date."""
    resp = await auth_client.get(
        "/api/v1/analytics/by-category",
        params={"start_date": "2025-12-31", "end_date": "2025-01-01"},
    )
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# Budget status
# ---------------------------------------------------------------------------


async def test_budget_status_no_budgets(auth_client: AsyncClient, test_user: User):
    """Budget status with no budgeted categories returns empty."""
    resp = await auth_client.get(
        "/api/v1/analytics/budget-status",
        params={"month": 3, "year": 2025},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["categories"] == []
    assert data["total_budget"] == 0
    assert data["total_spent"] == 0


async def test_budget_status_with_spending(auth_client: AsyncClient, test_user: User):
    """Budget status correctly computes spent vs budget per category."""
    cat = await _create_category(auth_client, "Groceries", monthly_budget=500.00)

    # Spend 300 of the 500 budget in March 2025
    await _create_expense(auth_client, 200.00, "2025-03-05", category_id=cat["id"])
    await _create_expense(auth_client, 100.00, "2025-03-20", category_id=cat["id"])

    resp = await auth_client.get(
        "/api/v1/analytics/budget-status",
        params={"month": 3, "year": 2025},
    )
    assert resp.status_code == 200

    data = resp.json()
    assert data["month"] == 3
    assert data["year"] == 2025
    assert data["total_budget"] == 500.00
    assert data["total_spent"] == 300.00
    assert data["total_remaining"] == 200.00

    cats = data["categories"]
    assert len(cats) == 1
    assert cats[0]["category_name"] == "Groceries"
    assert cats[0]["budget"] == 500.00
    assert cats[0]["spent"] == 300.00
    assert cats[0]["remaining"] == 200.00
    assert cats[0]["percentage_used"] == 60.0
    assert cats[0]["status"] == "on_track"


async def test_budget_status_over_budget(auth_client: AsyncClient, test_user: User):
    """Budget status marks over_budget when spending exceeds budget."""
    cat = await _create_category(auth_client, "Dining", monthly_budget=100.00)

    await _create_expense(auth_client, 120.00, "2025-05-10", category_id=cat["id"])

    resp = await auth_client.get(
        "/api/v1/analytics/budget-status",
        params={"month": 5, "year": 2025},
    )
    assert resp.status_code == 200

    cats = resp.json()["categories"]
    assert len(cats) == 1
    assert cats[0]["status"] == "over_budget"
    assert cats[0]["percentage_used"] == 120.0
    assert cats[0]["remaining"] == -20.00


async def test_budget_status_warning_threshold(auth_client: AsyncClient, test_user: User):
    """Budget status shows 'warning' when between 80% and 100%."""
    cat = await _create_category(auth_client, "Entertainment", monthly_budget=100.00)

    await _create_expense(auth_client, 85.00, "2025-06-15", category_id=cat["id"])

    resp = await auth_client.get(
        "/api/v1/analytics/budget-status",
        params={"month": 6, "year": 2025},
    )
    assert resp.status_code == 200

    cats = resp.json()["categories"]
    assert len(cats) == 1
    assert cats[0]["status"] == "warning"


# ---------------------------------------------------------------------------
# Auth required
# ---------------------------------------------------------------------------


async def test_daily_spending_excludes_hidden_categories(
    auth_client: AsyncClient, test_user: User, db_session: AsyncSession
):
    """Expenses in hidden categories must NOT appear in analytics results."""
    # Create a normal and a hidden category
    normal_cat = Category(
        user_id=test_user.id, name="Visible", sort_order=0, is_hidden=False,
    )
    hidden_cat = Category(
        user_id=test_user.id, name="Secret", sort_order=1, is_hidden=True,
    )
    db_session.add_all([normal_cat, hidden_cat])
    await db_session.flush()

    # Add expenses to both
    db_session.add(Expense(
        user_id=test_user.id, category_id=normal_cat.id,
        amount=50.00, expense_date=date(2025, 6, 15),
    ))
    db_session.add(Expense(
        user_id=test_user.id, category_id=hidden_cat.id,
        amount=999.00, expense_date=date(2025, 6, 15),
    ))
    await db_session.commit()

    # Daily analytics should show only the $50 from normal category
    resp = await auth_client.get(
        "/api/v1/analytics/daily",
        params={"start_date": "2025-06-01", "end_date": "2025-06-30"},
    )
    assert resp.status_code == 200
    totals = sum(d["total"] for d in resp.json()["data"])
    assert totals == 50.00, f"Expected 50.00 (hidden excluded), got {totals}"

    # By-category should also exclude hidden
    resp2 = await auth_client.get(
        "/api/v1/analytics/by-category",
        params={"start_date": "2025-06-01", "end_date": "2025-06-30"},
    )
    assert resp2.status_code == 200
    cat_names = [c["category_name"] for c in resp2.json()["data"]]
    assert "Secret" not in cat_names
    assert resp2.json()["grand_total"] == 50.00


async def test_analytics_unauthenticated(client: AsyncClient):
    """All analytics endpoints require auth."""
    for url in [
        "/api/v1/analytics/daily?start_date=2025-01-01&end_date=2025-01-31",
        "/api/v1/analytics/monthly?year=2025",
        "/api/v1/analytics/by-category?start_date=2025-01-01&end_date=2025-01-31",
        "/api/v1/analytics/budget-status?month=1&year=2025",
    ]:
        resp = await client.get(url)
        assert resp.status_code == 401, f"Expected 401 for {url}"
