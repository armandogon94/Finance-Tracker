import uuid
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.database import get_db
from src.app.dependencies.feature_flags import require_feature
from src.app.models.friend_debt import ExternalAccount, FriendDeposit
from src.app.models.user import User
from src.app.schemas.friend_debt import (
    ExternalAccountCreate,
    ExternalAccountResponse,
    ExternalAccountUpdate,
    FriendDebtSummary,
    FriendDepositCreate,
    FriendDepositResponse,
)
from src.app.services.friend_debt_calc import calculate_friend_debt

router = APIRouter(prefix="/api/v1/friend-debt", tags=["friend-debt"])

# All endpoints require the friend_debt_calculator feature flag
_require_friend_debt = require_feature("friend_debt_calculator")


# ─── Summary ─────────────────────────────────────────────────────────────────


@router.get("/summary", response_model=FriendDebtSummary)
async def get_friend_debt_summary(
    bank_balance: float = Query(..., description="Current bank account balance"),
    current_user: User = Depends(_require_friend_debt),
    db: AsyncSession = Depends(get_db),
):
    """Calculate current friend debt position.

    Compares accumulated friend deposits/withdrawals against the bank balance
    and any external safety-net accounts to determine the true shortfall.
    """
    # Fetch all deposits/withdrawals
    deposit_result = await db.execute(
        select(FriendDeposit)
        .where(FriendDeposit.user_id == current_user.id)
        .order_by(FriendDeposit.transaction_date.asc())
    )
    deposits = deposit_result.scalars().all()

    # Fetch external accounts
    ext_result = await db.execute(
        select(ExternalAccount).where(ExternalAccount.user_id == current_user.id)
    )
    external_accounts = ext_result.scalars().all()

    total_deposits = sum(
        float(d.amount) for d in deposits if d.transaction_type == "deposit"
    )
    total_withdrawals = sum(
        float(d.amount) for d in deposits if d.transaction_type == "withdrawal"
    )
    ext_accounts_dicts = [
        {"name": a.account_name, "balance": float(a.current_balance)}
        for a in external_accounts
    ]

    summary = calculate_friend_debt(
        total_deposits=total_deposits,
        total_withdrawals=total_withdrawals,
        bank_balance=bank_balance,
        external_accounts=ext_accounts_dicts,
    )
    return summary


# ─── Deposits / Withdrawals ──────────────────────────────────────────────────


@router.post("/deposits", response_model=FriendDepositResponse, status_code=status.HTTP_201_CREATED)
async def create_deposit(
    data: FriendDepositCreate,
    current_user: User = Depends(_require_friend_debt),
    db: AsyncSession = Depends(get_db),
):
    """Log a friend deposit or withdrawal."""
    if data.transaction_type not in ("deposit", "withdrawal"):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="transaction_type must be 'deposit' or 'withdrawal'",
        )

    deposit = FriendDeposit(
        user_id=current_user.id,
        friend_name=data.friend_name,
        amount=data.amount,
        transaction_type=data.transaction_type,
        description=data.description,
        transaction_date=data.transaction_date or date.today(),
    )
    db.add(deposit)
    await db.commit()
    await db.refresh(deposit)
    return deposit


@router.get("/deposits", response_model=list[FriendDepositResponse])
async def list_deposits(
    friend_name: str | None = Query(None, description="Filter by friend name"),
    current_user: User = Depends(_require_friend_debt),
    db: AsyncSession = Depends(get_db),
):
    """List all friend deposits and withdrawals, optionally filtered by friend name."""
    query = (
        select(FriendDeposit)
        .where(FriendDeposit.user_id == current_user.id)
        .order_by(FriendDeposit.transaction_date.desc())
    )
    if friend_name:
        query = query.where(FriendDeposit.friend_name == friend_name)

    result = await db.execute(query)
    return result.scalars().all()


@router.delete("/deposits/{deposit_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_deposit(
    deposit_id: uuid.UUID,
    current_user: User = Depends(_require_friend_debt),
    db: AsyncSession = Depends(get_db),
):
    """Delete a friend deposit/withdrawal entry."""
    result = await db.execute(
        select(FriendDeposit).where(
            FriendDeposit.id == deposit_id,
            FriendDeposit.user_id == current_user.id,
        )
    )
    deposit = result.scalar_one_or_none()
    if deposit is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Deposit not found",
        )
    await db.delete(deposit)
    await db.commit()


# ─── External Accounts ───────────────────────────────────────────────────────


@router.get("/external-accounts", response_model=list[ExternalAccountResponse])
async def list_external_accounts(
    current_user: User = Depends(_require_friend_debt),
    db: AsyncSession = Depends(get_db),
):
    """List all external accounts used as safety-net balances."""
    result = await db.execute(
        select(ExternalAccount)
        .where(ExternalAccount.user_id == current_user.id)
        .order_by(ExternalAccount.created_at.desc())
    )
    return result.scalars().all()


@router.post(
    "/external-accounts",
    response_model=ExternalAccountResponse,
    status_code=status.HTTP_201_CREATED,
)
async def add_external_account(
    data: ExternalAccountCreate,
    current_user: User = Depends(_require_friend_debt),
    db: AsyncSession = Depends(get_db),
):
    """Add a new external account (e.g., savings, Venmo, etc.)."""
    account = ExternalAccount(
        user_id=current_user.id,
        account_name=data.account_name,
        current_balance=data.current_balance,
    )
    db.add(account)
    await db.commit()
    await db.refresh(account)
    return account


@router.patch("/external-accounts/{account_id}", response_model=ExternalAccountResponse)
async def update_external_account(
    account_id: uuid.UUID,
    data: ExternalAccountUpdate,
    current_user: User = Depends(_require_friend_debt),
    db: AsyncSession = Depends(get_db),
):
    """Update an external account's name or balance."""
    account = await _get_user_external_account(account_id, current_user.id, db)

    update_data = data.model_dump(exclude_unset=True)
    if not update_data:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="No fields provided to update",
        )

    for field, value in update_data.items():
        setattr(account, field, value)

    db.add(account)
    await db.commit()
    await db.refresh(account)
    return account


@router.delete("/external-accounts/{account_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_external_account(
    account_id: uuid.UUID,
    current_user: User = Depends(_require_friend_debt),
    db: AsyncSession = Depends(get_db),
):
    """Remove an external account."""
    account = await _get_user_external_account(account_id, current_user.id, db)
    await db.delete(account)
    await db.commit()


# ─── helpers ──────────────────────────────────────────────────────────────────


async def _get_user_external_account(
    account_id: uuid.UUID, user_id: uuid.UUID, db: AsyncSession
) -> ExternalAccount:
    """Fetch an external account by ID and verify ownership."""
    result = await db.execute(
        select(ExternalAccount).where(
            ExternalAccount.id == account_id,
            ExternalAccount.user_id == user_id,
        )
    )
    account = result.scalar_one_or_none()
    if account is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="External account not found",
        )
    return account
