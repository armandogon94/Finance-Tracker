import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.database import get_db
from src.app.dependencies.auth import get_current_user
from src.app.models.category import Category
from src.app.models.user import User
from src.app.schemas.category import (
    CategoryCreate,
    CategoryReorder,
    CategoryResponse,
    CategoryUpdate,
)

router = APIRouter(prefix="/api/v1/categories", tags=["categories"])


@router.get("/", response_model=list[CategoryResponse])
async def list_categories(
    include_inactive: bool = False,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List all categories for the current user, sorted by sort_order.

    By default only active categories are returned. Pass include_inactive=true
    to also include soft-deleted categories.
    """
    stmt = (
        select(Category)
        .where(Category.user_id == current_user.id)
        .order_by(Category.sort_order)
    )
    if not include_inactive:
        stmt = stmt.where(Category.is_active == True)  # noqa: E712

    result = await db.execute(stmt)
    return result.scalars().all()


@router.post("/", response_model=CategoryResponse, status_code=status.HTTP_201_CREATED)
async def create_category(
    data: CategoryCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a new category for the current user."""
    # Check for duplicate name within user's categories
    result = await db.execute(
        select(Category).where(
            Category.user_id == current_user.id,
            Category.name == data.name,
            Category.is_active == True,  # noqa: E712
        )
    )
    if result.scalar_one_or_none() is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Category '{data.name}' already exists",
        )

    # Determine next sort_order
    max_order_result = await db.execute(
        select(Category.sort_order)
        .where(Category.user_id == current_user.id)
        .order_by(Category.sort_order.desc())
        .limit(1)
    )
    max_order = max_order_result.scalar_one_or_none()
    next_order = (max_order + 1) if max_order is not None else 0

    category = Category(
        user_id=current_user.id,
        name=data.name,
        icon=data.icon,
        color=data.color,
        is_hidden=data.is_hidden,
        monthly_budget=data.monthly_budget,
        sort_order=next_order,
    )
    db.add(category)
    await db.commit()
    await db.refresh(category)

    return category


@router.patch("/{category_id}", response_model=CategoryResponse)
async def update_category(
    category_id: uuid.UUID,
    data: CategoryUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update a category's fields."""
    result = await db.execute(
        select(Category).where(
            Category.id == category_id,
            Category.user_id == current_user.id,
        )
    )
    category = result.scalar_one_or_none()
    if category is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Category not found",
        )

    update_data = data.model_dump(exclude_unset=True)
    if not update_data:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="No fields provided to update",
        )

    # If renaming, check for duplicate
    if "name" in update_data and update_data["name"] != category.name:
        dup_result = await db.execute(
            select(Category).where(
                Category.user_id == current_user.id,
                Category.name == update_data["name"],
                Category.is_active == True,  # noqa: E712
                Category.id != category_id,
            )
        )
        if dup_result.scalar_one_or_none() is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Category '{update_data['name']}' already exists",
            )

    for field, value in update_data.items():
        setattr(category, field, value)

    db.add(category)
    await db.commit()
    await db.refresh(category)

    return category


@router.delete("/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_category(
    category_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Soft-delete a category by setting is_active=False."""
    result = await db.execute(
        select(Category).where(
            Category.id == category_id,
            Category.user_id == current_user.id,
        )
    )
    category = result.scalar_one_or_none()
    if category is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Category not found",
        )

    category.is_active = False
    db.add(category)
    await db.commit()


@router.put("/reorder", response_model=list[CategoryResponse])
async def reorder_categories(
    data: CategoryReorder,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Bulk update sort_order for categories based on the provided ordered list of IDs."""
    if not data.category_ids:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="category_ids list must not be empty",
        )

    # Fetch all specified categories belonging to the user
    result = await db.execute(
        select(Category).where(
            Category.user_id == current_user.id,
            Category.id.in_(data.category_ids),
        )
    )
    categories_by_id = {cat.id: cat for cat in result.scalars().all()}

    # Validate that all provided IDs match existing user categories
    for cat_id in data.category_ids:
        if cat_id not in categories_by_id:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Category {cat_id} not found",
            )

    # Assign new sort_order based on position in the list
    for new_order, cat_id in enumerate(data.category_ids):
        categories_by_id[cat_id].sort_order = new_order

    await db.commit()

    # Refresh and return in new order
    for cat in categories_by_id.values():
        await db.refresh(cat)

    return [categories_by_id[cat_id] for cat_id in data.category_ids]
