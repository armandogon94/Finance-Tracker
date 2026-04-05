import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.database import get_db
from src.app.dependencies.auth import get_current_superuser
from src.app.models.credit_card import CreditCard
from src.app.models.expense import Expense
from src.app.models.feature_flag import UserFeatureFlag
from src.app.models.loan import Loan
from src.app.models.receipt import ReceiptArchive
from src.app.models.user import User
from src.app.schemas.admin import (
    AdminUserResponse,
    FeatureFlagResponse,
    FeatureFlagToggle,
    SystemStats,
)

router = APIRouter(prefix="/api/v1/admin", tags=["admin"])


@router.get("/users", response_model=list[AdminUserResponse])
async def list_users(
    skip: int = 0,
    limit: int = 50,
    current_user: User = Depends(get_current_superuser),
    db: AsyncSession = Depends(get_db),
):
    """List all users in the system with pagination."""
    result = await db.execute(
        select(User)
        .order_by(User.created_at.desc())
        .offset(skip)
        .limit(limit)
    )
    return result.scalars().all()


@router.get("/users/{user_id}", response_model=AdminUserResponse)
async def get_user(
    user_id: uuid.UUID,
    current_user: User = Depends(get_current_superuser),
    db: AsyncSession = Depends(get_db),
):
    """Get detailed information about a specific user."""
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )
    return user


@router.patch("/users/{user_id}", response_model=AdminUserResponse)
async def toggle_user_active(
    user_id: uuid.UUID,
    current_user: User = Depends(get_current_superuser),
    db: AsyncSession = Depends(get_db),
):
    """Toggle a user's is_active status. Cannot deactivate yourself."""
    if user_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot deactivate your own account",
        )

    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    user.is_active = not user.is_active
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


@router.get("/users/{user_id}/features", response_model=list[FeatureFlagResponse])
async def get_user_features(
    user_id: uuid.UUID,
    current_user: User = Depends(get_current_superuser),
    db: AsyncSession = Depends(get_db),
):
    """Get all feature flags for a specific user."""
    # Verify user exists
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    result = await db.execute(
        select(UserFeatureFlag)
        .where(UserFeatureFlag.user_id == user_id)
        .order_by(UserFeatureFlag.feature_name)
    )
    return result.scalars().all()


@router.patch("/users/{user_id}/features", response_model=FeatureFlagResponse)
async def toggle_feature_flag(
    user_id: uuid.UUID,
    data: FeatureFlagToggle,
    current_user: User = Depends(get_current_superuser),
    db: AsyncSession = Depends(get_db),
):
    """Enable or disable a feature flag for a specific user.

    Creates the flag record if it doesn't exist yet.
    """
    # Verify user exists
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    # Check if flag already exists for this user
    result = await db.execute(
        select(UserFeatureFlag).where(
            UserFeatureFlag.user_id == user_id,
            UserFeatureFlag.feature_name == data.feature_name,
        )
    )
    flag = result.scalar_one_or_none()

    if flag is None:
        # Create new flag record
        flag = UserFeatureFlag(
            user_id=user_id,
            feature_name=data.feature_name,
            is_enabled=data.is_enabled,
            enabled_by=current_user.id if data.is_enabled else None,
            enabled_at=datetime.now(timezone.utc) if data.is_enabled else None,
        )
        db.add(flag)
    else:
        # Update existing flag
        flag.is_enabled = data.is_enabled
        if data.is_enabled:
            flag.enabled_by = current_user.id
            flag.enabled_at = datetime.now(timezone.utc)
        else:
            flag.enabled_by = None
            flag.enabled_at = None
        db.add(flag)

    await db.commit()
    await db.refresh(flag)
    return flag


@router.get("/stats", response_model=SystemStats)
async def get_system_stats(
    current_user: User = Depends(get_current_superuser),
    db: AsyncSession = Depends(get_db),
):
    """System-wide statistics: total users, expenses, receipts, and debt items."""
    total_users_result = await db.execute(select(func.count(User.id)))
    total_users = total_users_result.scalar() or 0

    active_users_result = await db.execute(
        select(func.count(User.id)).where(User.is_active == True)  # noqa: E712
    )
    active_users = active_users_result.scalar() or 0

    total_expenses_result = await db.execute(select(func.count(Expense.id)))
    total_expenses = total_expenses_result.scalar() or 0

    total_receipts_result = await db.execute(select(func.count(ReceiptArchive.id)))
    total_receipts = total_receipts_result.scalar() or 0

    total_cc_result = await db.execute(
        select(func.count(CreditCard.id)).where(CreditCard.is_active == True)  # noqa: E712
    )
    total_cc = total_cc_result.scalar() or 0

    total_loans_result = await db.execute(
        select(func.count(Loan.id)).where(Loan.is_active == True)  # noqa: E712
    )
    total_loans = total_loans_result.scalar() or 0

    return SystemStats(
        total_users=total_users,
        active_users=active_users,
        total_expenses=total_expenses,
        total_receipts=total_receipts,
        total_debt_items=total_cc + total_loans,
    )
