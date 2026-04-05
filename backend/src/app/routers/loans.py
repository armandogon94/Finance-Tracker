import uuid
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.database import get_db
from src.app.dependencies.auth import get_current_user
from src.app.models.debt_payment import DebtPayment, DebtSnapshot
from src.app.models.loan import Loan
from src.app.models.user import User
from src.app.schemas.debt import (
    DebtPaymentCreate,
    LoanCreate,
    LoanResponse,
    LoanUpdate,
    PayoffProjection,
)
from src.app.services.debt_calculator import calculate_amortization, calculate_loan_payoff

router = APIRouter(prefix="/api/v1/loans", tags=["loans"])


def _loan_to_response(loan: Loan) -> LoanResponse:
    """Convert a Loan ORM instance to a response with computed progress_percent."""
    original = float(loan.original_principal)
    current = float(loan.current_balance)
    if original > 0:
        progress = round((original - current) / original * 100, 2)
    else:
        progress = 100.0
    return LoanResponse(
        id=loan.id,
        loan_name=loan.loan_name,
        lender=loan.lender,
        loan_type=loan.loan_type,
        original_principal=original,
        current_balance=current,
        interest_rate=float(loan.interest_rate),
        interest_rate_type=loan.interest_rate_type,
        minimum_payment=float(loan.minimum_payment) if loan.minimum_payment else None,
        due_day=loan.due_day,
        start_date=loan.start_date,
        progress_percent=progress,
        is_active=loan.is_active,
        created_at=loan.created_at,
        updated_at=loan.updated_at,
    )


@router.get("/", response_model=list[LoanResponse])
async def list_loans(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List all active loans for the authenticated user."""
    result = await db.execute(
        select(Loan)
        .where(Loan.user_id == current_user.id, Loan.is_active == True)  # noqa: E712
        .order_by(Loan.created_at.desc())
    )
    loans = result.scalars().all()
    return [_loan_to_response(loan) for loan in loans]


@router.post("/", response_model=LoanResponse, status_code=status.HTTP_201_CREATED)
async def add_loan(
    data: LoanCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Add a new loan for tracking."""
    loan = Loan(
        user_id=current_user.id,
        loan_name=data.loan_name,
        lender=data.lender,
        loan_type=data.loan_type,
        original_principal=data.original_principal,
        current_balance=data.current_balance,
        interest_rate=data.interest_rate,
        interest_rate_type=data.interest_rate_type,
        minimum_payment=data.minimum_payment,
        due_day=data.due_day,
        start_date=data.start_date,
    )
    db.add(loan)
    await db.commit()
    await db.refresh(loan)
    return _loan_to_response(loan)


@router.get("/{loan_id}", response_model=LoanResponse)
async def get_loan(
    loan_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get details for a specific loan."""
    loan = await _get_user_loan(loan_id, current_user.id, db)
    return _loan_to_response(loan)


@router.patch("/{loan_id}", response_model=LoanResponse)
async def update_loan(
    loan_id: uuid.UUID,
    data: LoanUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update loan fields (balance, rate, payment, etc.)."""
    loan = await _get_user_loan(loan_id, current_user.id, db)

    update_data = data.model_dump(exclude_unset=True)
    if not update_data:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="No fields provided to update",
        )

    for field, value in update_data.items():
        setattr(loan, field, value)

    db.add(loan)
    await db.commit()
    await db.refresh(loan)
    return _loan_to_response(loan)


@router.delete("/{loan_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_loan(
    loan_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Soft delete a loan by setting is_active to False."""
    loan = await _get_user_loan(loan_id, current_user.id, db)
    loan.is_active = False
    db.add(loan)
    await db.commit()


@router.post("/{loan_id}/payment", status_code=status.HTTP_201_CREATED)
async def log_loan_payment(
    loan_id: uuid.UUID,
    data: DebtPaymentCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Log a payment toward a loan and update the loan's balance.

    Automatically splits the payment into principal and interest portions
    based on the loan's current rate.
    """
    loan = await _get_user_loan(loan_id, current_user.id, db)

    # Calculate interest/principal split for this payment
    balance = float(loan.current_balance)
    annual_rate = float(loan.interest_rate)
    monthly_rate = annual_rate / 12
    interest_portion = round(balance * monthly_rate, 2)
    principal_portion = round(max(data.amount - interest_portion, 0), 2)

    # If paying less than interest, all goes to interest
    if data.amount <= interest_portion:
        interest_portion = data.amount
        principal_portion = 0.0

    # Create the payment record
    payment = DebtPayment(
        user_id=current_user.id,
        debt_type="loan",
        debt_id=loan.id,
        amount=data.amount,
        principal_portion=principal_portion,
        interest_portion=interest_portion,
        payment_date=data.payment_date or date.today(),
        is_snowflake=data.is_snowflake,
        notes=data.notes,
    )
    db.add(payment)

    # Reduce balance by principal portion (floor at 0)
    new_balance = max(balance - principal_portion, 0)
    loan.current_balance = new_balance
    db.add(loan)

    # Take a snapshot for history tracking
    snapshot = DebtSnapshot(
        user_id=current_user.id,
        debt_type="loan",
        debt_id=loan.id,
        balance=new_balance,
        snapshot_date=data.payment_date or date.today(),
    )
    db.add(snapshot)

    await db.commit()
    await db.refresh(payment)

    return {
        "payment_id": payment.id,
        "amount": data.amount,
        "principal_portion": principal_portion,
        "interest_portion": interest_portion,
        "new_balance": new_balance,
        "payment_date": str(payment.payment_date),
    }


@router.get("/{loan_id}/amortization")
async def get_amortization_schedule(
    loan_id: uuid.UUID,
    monthly_payment: float | None = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Generate a full amortization schedule for the remaining loan balance.

    If monthly_payment is not specified, uses the loan's minimum_payment.
    """
    loan = await _get_user_loan(loan_id, current_user.id, db)

    payment_amount = monthly_payment
    if payment_amount is None:
        if loan.minimum_payment is None or float(loan.minimum_payment) <= 0:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="No minimum payment set on this loan. Provide monthly_payment query parameter.",
            )
        payment_amount = float(loan.minimum_payment)

    schedule = calculate_amortization(
        balance=float(loan.current_balance),
        annual_rate=float(loan.interest_rate),
        monthly_payment=payment_amount,
    )
    return {
        "loan_id": loan.id,
        "loan_name": loan.loan_name,
        "starting_balance": float(loan.current_balance),
        "monthly_payment": payment_amount,
        "schedule": schedule,
        "total_months": len(schedule),
    }


@router.post("/{loan_id}/snowflake", status_code=status.HTTP_201_CREATED)
async def log_snowflake_payment(
    loan_id: uuid.UUID,
    data: DebtPaymentCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Log a windfall/extra payment that goes entirely to principal.

    Snowflake payments bypass normal interest splitting -- the full amount
    reduces principal directly.
    """
    loan = await _get_user_loan(loan_id, current_user.id, db)

    balance = float(loan.current_balance)
    actual_principal = min(data.amount, balance)

    payment = DebtPayment(
        user_id=current_user.id,
        debt_type="loan",
        debt_id=loan.id,
        amount=data.amount,
        principal_portion=actual_principal,
        interest_portion=0.0,
        payment_date=data.payment_date or date.today(),
        is_snowflake=True,
        notes=data.notes or "Windfall / snowflake payment",
    )
    db.add(payment)

    new_balance = max(balance - actual_principal, 0)
    loan.current_balance = new_balance
    db.add(loan)

    snapshot = DebtSnapshot(
        user_id=current_user.id,
        debt_type="loan",
        debt_id=loan.id,
        balance=new_balance,
        snapshot_date=data.payment_date or date.today(),
    )
    db.add(snapshot)

    await db.commit()
    await db.refresh(payment)

    # Recalculate payoff with minimum payment if available
    payoff = None
    if loan.minimum_payment and float(loan.minimum_payment) > 0:
        payoff = calculate_loan_payoff(
            balance=new_balance,
            annual_rate=float(loan.interest_rate),
            monthly_payment=float(loan.minimum_payment),
        )

    return {
        "payment_id": payment.id,
        "amount": data.amount,
        "principal_applied": actual_principal,
        "new_balance": new_balance,
        "payment_date": str(payment.payment_date),
        "updated_payoff": payoff,
    }


# ─── helpers ──────────────────────────────────────────────────────────────────


async def _get_user_loan(
    loan_id: uuid.UUID, user_id: uuid.UUID, db: AsyncSession
) -> Loan:
    """Fetch a loan by ID and verify ownership."""
    result = await db.execute(
        select(Loan).where(
            Loan.id == loan_id,
            Loan.user_id == user_id,
            Loan.is_active == True,  # noqa: E712
        )
    )
    loan = result.scalar_one_or_none()
    if loan is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Loan not found",
        )
    return loan
