import uuid
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.database import get_db
from src.app.dependencies.auth import get_current_user
from src.app.models.category import Category
from src.app.models.expense import Expense
from src.app.models.user import User
from src.app.schemas.expense import (
    ExpenseCreate,
    ExpenseListResponse,
    ExpenseQuickAdd,
    ExpenseResponse,
    ExpenseUpdate,
)

router = APIRouter(prefix="/api/v1/expenses", tags=["expenses"])


def _build_base_query(user_id: uuid.UUID):
    """Build the base select for expenses belonging to a user."""
    return select(Expense).where(Expense.user_id == user_id)


def _apply_filters(
    stmt,
    *,
    start_date: date | None = None,
    end_date: date | None = None,
    category_id: uuid.UUID | None = None,
    search: str | None = None,
    min_amount: float | None = None,
    max_amount: float | None = None,
):
    """Apply optional filter clauses to an expense query."""
    if start_date is not None:
        stmt = stmt.where(Expense.expense_date >= start_date)
    if end_date is not None:
        stmt = stmt.where(Expense.expense_date <= end_date)
    if category_id is not None:
        stmt = stmt.where(Expense.category_id == category_id)
    if search is not None:
        pattern = f"%{search}%"
        stmt = stmt.where(
            or_(
                Expense.description.ilike(pattern),
                Expense.merchant_name.ilike(pattern),
            )
        )
    if min_amount is not None:
        stmt = stmt.where(Expense.amount >= min_amount)
    if max_amount is not None:
        stmt = stmt.where(Expense.amount <= max_amount)
    return stmt


@router.get("/hidden", response_model=ExpenseListResponse)
async def list_hidden_expenses(
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List expenses that belong to hidden categories only.

    This endpoint is intended for users who have hidden-category expenses they
    want to review separately.
    """
    # Join with Category and filter where category IS hidden
    base = (
        _build_base_query(current_user.id)
        .join(Category, Expense.category_id == Category.id)
        .where(Category.is_hidden == True)  # noqa: E712
    )

    # Count total matching rows
    count_stmt = select(func.count()).select_from(base.subquery())
    total = (await db.execute(count_stmt)).scalar_one()

    # Fetch page
    offset = (page - 1) * per_page
    rows_stmt = base.order_by(Expense.expense_date.desc(), Expense.created_at.desc()).offset(offset).limit(per_page)
    result = await db.execute(rows_stmt)
    items = result.scalars().all()

    return ExpenseListResponse(items=items, total=total, page=page, per_page=per_page)


@router.get("/", response_model=ExpenseListResponse)
async def list_expenses(
    start_date: date | None = Query(None),
    end_date: date | None = Query(None),
    category_id: uuid.UUID | None = Query(None),
    search: str | None = Query(None, max_length=200),
    min_amount: float | None = Query(None, ge=0),
    max_amount: float | None = Query(None, ge=0),
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List expenses with filters and pagination.

    By default, expenses linked to hidden categories are excluded. Expenses
    with no category (category_id IS NULL) are always included.
    """
    base = (
        _build_base_query(current_user.id)
        .outerjoin(Category, Expense.category_id == Category.id)
        .where(
            or_(
                Expense.category_id.is_(None),
                Category.is_hidden == False,  # noqa: E712
            )
        )
    )

    base = _apply_filters(
        base,
        start_date=start_date,
        end_date=end_date,
        category_id=category_id,
        search=search,
        min_amount=min_amount,
        max_amount=max_amount,
    )

    # Total count
    count_stmt = select(func.count()).select_from(base.subquery())
    total = (await db.execute(count_stmt)).scalar_one()

    # Paginated results
    offset = (page - 1) * per_page
    rows_stmt = base.order_by(Expense.expense_date.desc(), Expense.created_at.desc()).offset(offset).limit(per_page)
    result = await db.execute(rows_stmt)
    items = result.scalars().all()

    return ExpenseListResponse(items=items, total=total, page=page, per_page=per_page)


@router.post("/", response_model=ExpenseResponse, status_code=status.HTTP_201_CREATED)
async def create_expense(
    data: ExpenseCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a new expense."""
    # Validate category belongs to user if provided
    if data.category_id is not None:
        cat_result = await db.execute(
            select(Category).where(
                Category.id == data.category_id,
                Category.user_id == current_user.id,
                Category.is_active == True,  # noqa: E712
            )
        )
        if cat_result.scalar_one_or_none() is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Category not found or inactive",
            )

    expense = Expense(
        user_id=current_user.id,
        category_id=data.category_id,
        amount=data.amount,
        tax_amount=data.tax_amount,
        currency=data.currency,
        description=data.description,
        merchant_name=data.merchant_name,
        expense_date=data.expense_date or date.today(),
        expense_time=data.expense_time,
        notes=data.notes,
        is_recurring=data.is_recurring,
        is_tax_deductible=data.is_tax_deductible,
        tags=data.tags,
    )
    db.add(expense)
    await db.commit()
    await db.refresh(expense)

    return expense


@router.post("/quick", response_model=ExpenseResponse, status_code=status.HTTP_201_CREATED)
async def quick_add_expense(
    data: ExpenseQuickAdd,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Quick-add an expense with just amount and category. Date defaults to today."""
    # Validate category belongs to user
    cat_result = await db.execute(
        select(Category).where(
            Category.id == data.category_id,
            Category.user_id == current_user.id,
            Category.is_active == True,  # noqa: E712
        )
    )
    if cat_result.scalar_one_or_none() is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Category not found or inactive",
        )

    expense = Expense(
        user_id=current_user.id,
        category_id=data.category_id,
        amount=data.amount,
        expense_date=date.today(),
        currency=current_user.currency,
    )
    db.add(expense)
    await db.commit()
    await db.refresh(expense)

    return expense


@router.get("/{expense_id}", response_model=ExpenseResponse)
async def get_expense(
    expense_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get a single expense by ID."""
    result = await db.execute(
        select(Expense).where(
            Expense.id == expense_id,
            Expense.user_id == current_user.id,
        )
    )
    expense = result.scalar_one_or_none()
    if expense is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Expense not found",
        )
    return expense


@router.patch("/{expense_id}", response_model=ExpenseResponse)
async def update_expense(
    expense_id: uuid.UUID,
    data: ExpenseUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update an existing expense's fields."""
    result = await db.execute(
        select(Expense).where(
            Expense.id == expense_id,
            Expense.user_id == current_user.id,
        )
    )
    expense = result.scalar_one_or_none()
    if expense is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Expense not found",
        )

    update_data = data.model_dump(exclude_unset=True)
    if not update_data:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="No fields provided to update",
        )

    # Validate category if being changed
    if "category_id" in update_data and update_data["category_id"] is not None:
        cat_result = await db.execute(
            select(Category).where(
                Category.id == update_data["category_id"],
                Category.user_id == current_user.id,
                Category.is_active == True,  # noqa: E712
            )
        )
        if cat_result.scalar_one_or_none() is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Category not found or inactive",
            )

    for field, value in update_data.items():
        setattr(expense, field, value)

    db.add(expense)
    await db.commit()
    await db.refresh(expense)

    return expense


@router.delete("/{expense_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_expense(
    expense_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Permanently delete an expense."""
    result = await db.execute(
        select(Expense).where(
            Expense.id == expense_id,
            Expense.user_id == current_user.id,
        )
    )
    expense = result.scalar_one_or_none()
    if expense is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Expense not found",
        )

    await db.delete(expense)
    await db.commit()
