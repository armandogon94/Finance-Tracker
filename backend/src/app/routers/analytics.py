import uuid
from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import case, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.database import get_db
from src.app.dependencies.auth import get_current_user
from src.app.models.category import Category
from src.app.models.expense import Expense
from src.app.models.user import User

router = APIRouter(prefix="/api/v1/analytics", tags=["analytics"])


def _base_expense_query(user_id: uuid.UUID):
    """Base query for user expenses, excluding those in hidden categories.

    Expenses with no category (category_id IS NULL) are always included.
    """
    return (
        select(Expense)
        .outerjoin(Category, Expense.category_id == Category.id)
        .where(
            Expense.user_id == user_id,
            or_(
                Expense.category_id.is_(None),
                Category.is_hidden == False,  # noqa: E712
            ),
        )
    )


# ─── Daily spending ─────────────────────────────────────────────────────────


@router.get("/daily")
async def daily_spending(
    start_date: date = Query(..., description="Start date (inclusive)"),
    end_date: date = Query(..., description="End date (inclusive)"),
    category_id: uuid.UUID | None = Query(None, description="Optional category filter"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Daily spending totals within a date range.

    Returns a list of {date, total, count} objects for each day that has
    expenses, sorted chronologically. Hidden-category expenses are excluded.
    """
    if end_date < start_date:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="end_date must be on or after start_date",
        )

    stmt = (
        select(
            Expense.expense_date,
            func.sum(Expense.amount).label("total"),
            func.count(Expense.id).label("count"),
        )
        .outerjoin(Category, Expense.category_id == Category.id)
        .where(
            Expense.user_id == current_user.id,
            Expense.expense_date >= start_date,
            Expense.expense_date <= end_date,
            or_(
                Expense.category_id.is_(None),
                Category.is_hidden == False,  # noqa: E712
            ),
        )
        .group_by(Expense.expense_date)
        .order_by(Expense.expense_date.asc())
    )

    if category_id is not None:
        stmt = stmt.where(Expense.category_id == category_id)

    result = await db.execute(stmt)
    rows = result.all()

    return {
        "data": [
            {
                "date": str(row.expense_date),
                "total": round(float(row.total), 2),
                "count": row.count,
            }
            for row in rows
        ],
        "start_date": str(start_date),
        "end_date": str(end_date),
    }


# ─── Weekly spending ─────────────────────────────────────────────────────────


@router.get("/weekly")
async def weekly_spending(
    start_date: date = Query(..., description="Start date (inclusive)"),
    end_date: date = Query(..., description="End date (inclusive)"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Weekly spending aggregation within a date range.

    Groups expenses by ISO week number. Returns {year, week, total, count}
    for each week that has expenses.
    """
    if end_date < start_date:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="end_date must be on or after start_date",
        )

    # Use EXTRACT for week grouping (ISO week)
    week_expr = func.extract("isoyear", Expense.expense_date).label("year")
    week_num_expr = func.extract("week", Expense.expense_date).label("week")

    stmt = (
        select(
            week_expr,
            week_num_expr,
            func.sum(Expense.amount).label("total"),
            func.count(Expense.id).label("count"),
            func.min(Expense.expense_date).label("week_start"),
            func.max(Expense.expense_date).label("week_end"),
        )
        .outerjoin(Category, Expense.category_id == Category.id)
        .where(
            Expense.user_id == current_user.id,
            Expense.expense_date >= start_date,
            Expense.expense_date <= end_date,
            or_(
                Expense.category_id.is_(None),
                Category.is_hidden == False,  # noqa: E712
            ),
        )
        .group_by(week_expr, week_num_expr)
        .order_by(week_expr.asc(), week_num_expr.asc())
    )

    result = await db.execute(stmt)
    rows = result.all()

    return {
        "data": [
            {
                "year": int(row.year),
                "week": int(row.week),
                "total": round(float(row.total), 2),
                "count": row.count,
                "week_start": str(row.week_start),
                "week_end": str(row.week_end),
            }
            for row in rows
        ],
        "start_date": str(start_date),
        "end_date": str(end_date),
    }


# ─── Monthly spending ───────────────────────────────────────────────────────


@router.get("/monthly")
async def monthly_spending(
    year: int = Query(..., ge=2000, le=2100, description="Year to show monthly totals for"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Monthly spending totals for a given year.

    Returns {month, total, count} for each month (1-12) that has expenses.
    """
    month_expr = func.extract("month", Expense.expense_date).label("month")

    stmt = (
        select(
            month_expr,
            func.sum(Expense.amount).label("total"),
            func.count(Expense.id).label("count"),
        )
        .outerjoin(Category, Expense.category_id == Category.id)
        .where(
            Expense.user_id == current_user.id,
            func.extract("year", Expense.expense_date) == year,
            or_(
                Expense.category_id.is_(None),
                Category.is_hidden == False,  # noqa: E712
            ),
        )
        .group_by(month_expr)
        .order_by(month_expr.asc())
    )

    result = await db.execute(stmt)
    rows = result.all()

    # Build a full 12-month array with zeros for missing months
    monthly_data = {int(row.month): {"total": round(float(row.total), 2), "count": row.count} for row in rows}

    data = []
    grand_total = 0.0
    for m in range(1, 13):
        entry = monthly_data.get(m, {"total": 0.0, "count": 0})
        grand_total += entry["total"]
        data.append({
            "month": m,
            "total": entry["total"],
            "count": entry["count"],
        })

    return {
        "year": year,
        "data": data,
        "grand_total": round(grand_total, 2),
    }


# ─── Spending by category ───────────────────────────────────────────────────


@router.get("/by-category")
async def spending_by_category(
    start_date: date = Query(..., description="Start date (inclusive)"),
    end_date: date = Query(..., description="End date (inclusive)"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Spending breakdown by category within a date range (for pie chart).

    Returns {category_id, category_name, color, icon, total, count, percentage}
    for each category. Uncategorized expenses are grouped under a special entry.
    Hidden categories are excluded.
    """
    if end_date < start_date:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="end_date must be on or after start_date",
        )

    stmt = (
        select(
            Expense.category_id,
            Category.name.label("category_name"),
            Category.color.label("color"),
            Category.icon.label("icon"),
            func.sum(Expense.amount).label("total"),
            func.count(Expense.id).label("count"),
        )
        .outerjoin(Category, Expense.category_id == Category.id)
        .where(
            Expense.user_id == current_user.id,
            Expense.expense_date >= start_date,
            Expense.expense_date <= end_date,
            or_(
                Expense.category_id.is_(None),
                Category.is_hidden == False,  # noqa: E712
            ),
        )
        .group_by(Expense.category_id, Category.name, Category.color, Category.icon)
        .order_by(func.sum(Expense.amount).desc())
    )

    result = await db.execute(stmt)
    rows = result.all()

    # Calculate grand total for percentage computation
    grand_total = sum(float(row.total) for row in rows)

    data = []
    for row in rows:
        total = round(float(row.total), 2)
        percentage = round((total / grand_total * 100), 1) if grand_total > 0 else 0
        data.append({
            "category_id": str(row.category_id) if row.category_id else None,
            "category_name": row.category_name or "Uncategorized",
            "color": row.color or "#6B7280",
            "icon": row.icon or "receipt",
            "total": total,
            "count": row.count,
            "percentage": percentage,
        })

    return {
        "data": data,
        "grand_total": round(grand_total, 2),
        "start_date": str(start_date),
        "end_date": str(end_date),
    }


# ─── Budget status ───────────────────────────────────────────────────────────


@router.get("/budget-status")
async def budget_status(
    month: int | None = Query(None, ge=1, le=12, description="Month (defaults to current)"),
    year: int | None = Query(None, ge=2000, le=2100, description="Year (defaults to current)"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Budget vs actual spending per category for a given month.

    Compares each category's monthly_budget against actual spending.
    Only includes categories that have a budget set. Hidden categories are excluded.

    Returns {category_id, category_name, budget, spent, remaining, percentage_used}
    for each budgeted category.
    """
    today = date.today()
    target_month = month or today.month
    target_year = year or today.year

    # Fetch all budgeted categories for the user (non-hidden, active)
    cat_result = await db.execute(
        select(Category).where(
            Category.user_id == current_user.id,
            Category.is_active == True,  # noqa: E712
            Category.is_hidden == False,  # noqa: E712
            Category.monthly_budget.isnot(None),
            Category.monthly_budget > 0,
        )
    )
    budgeted_categories = cat_result.scalars().all()

    if not budgeted_categories:
        return {
            "month": target_month,
            "year": target_year,
            "categories": [],
            "total_budget": 0,
            "total_spent": 0,
        }

    # Get actual spending per category for the target month
    spending_stmt = (
        select(
            Expense.category_id,
            func.sum(Expense.amount).label("total_spent"),
        )
        .where(
            Expense.user_id == current_user.id,
            func.extract("month", Expense.expense_date) == target_month,
            func.extract("year", Expense.expense_date) == target_year,
            Expense.category_id.in_([c.id for c in budgeted_categories]),
        )
        .group_by(Expense.category_id)
    )

    spending_result = await db.execute(spending_stmt)
    spending_by_cat = {row.category_id: float(row.total_spent) for row in spending_result.all()}

    # Build response
    categories = []
    total_budget = 0.0
    total_spent = 0.0

    for cat in budgeted_categories:
        budget = float(cat.monthly_budget)
        spent = spending_by_cat.get(cat.id, 0.0)
        remaining = budget - spent
        pct_used = round((spent / budget * 100), 1) if budget > 0 else 0

        total_budget += budget
        total_spent += spent

        status_label = "on_track"
        if pct_used >= 100:
            status_label = "over_budget"
        elif pct_used >= 80:
            status_label = "warning"

        categories.append({
            "category_id": str(cat.id),
            "category_name": cat.name,
            "color": cat.color,
            "icon": cat.icon,
            "budget": round(budget, 2),
            "spent": round(spent, 2),
            "remaining": round(remaining, 2),
            "percentage_used": pct_used,
            "status": status_label,
        })

    # Sort by percentage used descending (most overbudget first)
    categories.sort(key=lambda x: x["percentage_used"], reverse=True)

    return {
        "month": target_month,
        "year": target_year,
        "categories": categories,
        "total_budget": round(total_budget, 2),
        "total_spent": round(total_spent, 2),
        "total_remaining": round(total_budget - total_spent, 2),
    }
