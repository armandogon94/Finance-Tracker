from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.database import get_db
from src.app.dependencies.auth import get_current_user
from src.app.models.credit_card import CreditCard
from src.app.models.debt_payment import DebtSnapshot
from src.app.models.loan import Loan
from src.app.models.user import User
from src.app.schemas.debt import StrategyComparison
from src.app.services.debt_strategies import compare_strategies_schema

router = APIRouter(prefix="/api/v1/debt", tags=["debt"])


@router.get("/summary")
async def get_debt_summary(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Total debt overview: sums all active credit cards and loans.

    Returns balances broken down by type, total minimums, and item counts.
    """
    # Fetch active credit cards
    cc_result = await db.execute(
        select(CreditCard).where(
            CreditCard.user_id == current_user.id,
            CreditCard.is_active == True,  # noqa: E712
        )
    )
    cards = cc_result.scalars().all()

    # Fetch active loans
    loan_result = await db.execute(
        select(Loan).where(
            Loan.user_id == current_user.id,
            Loan.is_active == True,  # noqa: E712
        )
    )
    loans = loan_result.scalars().all()

    # Aggregate credit card totals
    total_cc_balance = sum(float(c.current_balance) for c in cards)
    total_cc_limit = sum(float(c.credit_limit) for c in cards if c.credit_limit)
    total_cc_minimum = sum(float(c.minimum_payment) for c in cards if c.minimum_payment)
    avg_cc_apr = (
        sum(float(c.apr) for c in cards) / len(cards) if cards else 0
    )

    # Aggregate loan totals
    total_loan_balance = sum(float(l.current_balance) for l in loans)
    total_loan_original = sum(float(l.original_principal) for l in loans)
    total_loan_minimum = sum(float(l.minimum_payment) for l in loans if l.minimum_payment)
    avg_loan_rate = (
        sum(float(l.interest_rate) for l in loans) / len(loans) if loans else 0
    )

    total_balance = total_cc_balance + total_loan_balance
    total_minimum = total_cc_minimum + total_loan_minimum

    return {
        "total_balance": round(total_balance, 2),
        "total_minimum_payment": round(total_minimum, 2),
        "credit_cards": {
            "count": len(cards),
            "total_balance": round(total_cc_balance, 2),
            "total_credit_limit": round(total_cc_limit, 2),
            "overall_utilization": (
                round(total_cc_balance / total_cc_limit * 100, 2) if total_cc_limit > 0 else None
            ),
            "total_minimum": round(total_cc_minimum, 2),
            "average_apr": round(avg_cc_apr, 4),
        },
        "loans": {
            "count": len(loans),
            "total_balance": round(total_loan_balance, 2),
            "total_original_principal": round(total_loan_original, 2),
            "overall_progress_percent": (
                round((total_loan_original - total_loan_balance) / total_loan_original * 100, 2)
                if total_loan_original > 0
                else None
            ),
            "total_minimum": round(total_loan_minimum, 2),
            "average_rate": round(avg_loan_rate, 4),
        },
    }


@router.get("/strategies", response_model=StrategyComparison)
async def get_payoff_strategies(
    monthly_budget: float = Query(..., gt=0, description="Total monthly amount available for debt payments"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Compare payoff strategies (avalanche, snowball, hybrid, minimum-only).

    Takes the user's total monthly debt-payment budget and simulates each
    strategy to find months-to-freedom and total interest paid.
    """
    # Gather all active debts
    cc_result = await db.execute(
        select(CreditCard).where(
            CreditCard.user_id == current_user.id,
            CreditCard.is_active == True,  # noqa: E712
        )
    )
    cards = cc_result.scalars().all()

    loan_result = await db.execute(
        select(Loan).where(
            Loan.user_id == current_user.id,
            Loan.is_active == True,  # noqa: E712
        )
    )
    loans = loan_result.scalars().all()

    if not cards and not loans:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No active debts found to build a payoff strategy",
        )

    # Build a unified list of debt items for the strategy engine
    debts = []
    for card in cards:
        debts.append({
            "name": card.card_name,
            "type": "credit_card",
            "balance": float(card.current_balance),
            "rate": float(card.apr),
            "minimum_payment": float(card.minimum_payment) if card.minimum_payment else 0,
        })
    for loan in loans:
        debts.append({
            "name": loan.loan_name,
            "type": "loan",
            "balance": float(loan.current_balance),
            "rate": float(loan.interest_rate),
            "minimum_payment": float(loan.minimum_payment) if loan.minimum_payment else 0,
        })

    # Verify budget covers all minimums
    total_minimums = sum(d["minimum_payment"] for d in debts)
    if monthly_budget < total_minimums:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=(
                f"Monthly budget ${monthly_budget:.2f} is less than total minimum payments "
                f"${total_minimums:.2f}. Budget must cover at least all minimums."
            ),
        )

    comparison = compare_strategies_schema(debts=debts, monthly_budget=monthly_budget)
    return comparison


@router.get("/history")
async def get_debt_history(
    months: int = Query(12, ge=1, le=60, description="Number of months of history to return"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Debt balance over time from recorded snapshots.

    Returns a time-series of balance snapshots grouped by date, useful for
    charting debt paydown progress.
    """
    result = await db.execute(
        select(DebtSnapshot)
        .where(DebtSnapshot.user_id == current_user.id)
        .order_by(DebtSnapshot.snapshot_date.asc())
    )
    snapshots = result.scalars().all()

    # Group by date for easy charting
    history: dict[str, dict] = {}
    for snap in snapshots:
        date_key = str(snap.snapshot_date)
        if date_key not in history:
            history[date_key] = {
                "date": date_key,
                "credit_card_total": 0.0,
                "loan_total": 0.0,
                "total": 0.0,
                "items": [],
            }
        balance = float(snap.balance)
        if snap.debt_type == "credit_card":
            history[date_key]["credit_card_total"] += balance
        else:
            history[date_key]["loan_total"] += balance
        history[date_key]["total"] += balance
        history[date_key]["items"].append({
            "debt_type": snap.debt_type,
            "debt_id": str(snap.debt_id),
            "balance": balance,
        })

    # Round all totals
    for entry in history.values():
        entry["credit_card_total"] = round(entry["credit_card_total"], 2)
        entry["loan_total"] = round(entry["loan_total"], 2)
        entry["total"] = round(entry["total"], 2)

    # Return as sorted list, limited to requested months of data
    sorted_history = sorted(history.values(), key=lambda x: x["date"])

    # Trim to approximate month count (use last N*30 entries max)
    if len(sorted_history) > months * 31:
        sorted_history = sorted_history[-(months * 31):]

    return {
        "history": sorted_history,
        "total_snapshots": len(sorted_history),
    }
