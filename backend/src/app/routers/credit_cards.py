import uuid
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.database import get_db
from src.app.dependencies.auth import get_current_user
from src.app.models.credit_card import CreditCard
from src.app.models.debt_payment import DebtPayment, DebtSnapshot
from src.app.models.user import User
from src.app.schemas.debt import (
    CreditCardCreate,
    CreditCardResponse,
    CreditCardUpdate,
    DebtPaymentCreate,
    PayoffProjection,
)
from src.app.services.debt_calculator import calculate_cc_payoff

router = APIRouter(prefix="/api/v1/credit-cards", tags=["credit-cards"])


def _card_to_response(card: CreditCard) -> CreditCardResponse:
    """Convert a CreditCard ORM instance to a response with computed utilization."""
    utilization = None
    if card.credit_limit and float(card.credit_limit) > 0:
        utilization = round(float(card.current_balance) / float(card.credit_limit) * 100, 2)
    return CreditCardResponse(
        id=card.id,
        card_name=card.card_name,
        last_four=card.last_four,
        current_balance=float(card.current_balance),
        credit_limit=float(card.credit_limit) if card.credit_limit else None,
        apr=float(card.apr),
        minimum_payment=float(card.minimum_payment) if card.minimum_payment else None,
        statement_day=card.statement_day,
        due_day=card.due_day,
        utilization=utilization,
        is_active=card.is_active,
        created_at=card.created_at,
        updated_at=card.updated_at,
    )


@router.get("/", response_model=list[CreditCardResponse])
async def list_credit_cards(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List all active credit cards for the authenticated user."""
    result = await db.execute(
        select(CreditCard)
        .where(CreditCard.user_id == current_user.id, CreditCard.is_active == True)  # noqa: E712
        .order_by(CreditCard.created_at.desc())
    )
    cards = result.scalars().all()
    return [_card_to_response(card) for card in cards]


@router.post("/", response_model=CreditCardResponse, status_code=status.HTTP_201_CREATED)
async def add_credit_card(
    data: CreditCardCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Add a new credit card for tracking."""
    card = CreditCard(
        user_id=current_user.id,
        card_name=data.card_name,
        last_four=data.last_four,
        current_balance=data.current_balance,
        credit_limit=data.credit_limit,
        apr=data.apr,
        minimum_payment=data.minimum_payment,
        statement_day=data.statement_day,
        due_day=data.due_day,
    )
    db.add(card)
    await db.commit()
    await db.refresh(card)
    return _card_to_response(card)


@router.get("/{card_id}", response_model=CreditCardResponse)
async def get_credit_card(
    card_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get details for a specific credit card."""
    card = await _get_user_card(card_id, current_user.id, db)
    return _card_to_response(card)


@router.patch("/{card_id}", response_model=CreditCardResponse)
async def update_credit_card(
    card_id: uuid.UUID,
    data: CreditCardUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update credit card fields (balance, APR, limit, etc.)."""
    card = await _get_user_card(card_id, current_user.id, db)

    update_data = data.model_dump(exclude_unset=True)
    if not update_data:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="No fields provided to update",
        )

    for field, value in update_data.items():
        setattr(card, field, value)

    db.add(card)
    await db.commit()
    await db.refresh(card)
    return _card_to_response(card)


@router.delete("/{card_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_credit_card(
    card_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Soft delete a credit card by setting is_active to False."""
    card = await _get_user_card(card_id, current_user.id, db)
    card.is_active = False
    db.add(card)
    await db.commit()


@router.post("/{card_id}/payment", status_code=status.HTTP_201_CREATED)
async def log_credit_card_payment(
    card_id: uuid.UUID,
    data: DebtPaymentCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Log a payment toward a credit card and update the card's balance."""
    card = await _get_user_card(card_id, current_user.id, db)

    # Create the payment record
    payment = DebtPayment(
        user_id=current_user.id,
        debt_type="credit_card",
        debt_id=card.id,
        amount=data.amount,
        payment_date=data.payment_date or date.today(),
        is_snowflake=data.is_snowflake,
        notes=data.notes,
    )
    db.add(payment)

    # Reduce balance (floor at 0)
    new_balance = max(float(card.current_balance) - data.amount, 0)
    card.current_balance = new_balance
    db.add(card)

    # Take a snapshot for history tracking
    snapshot = DebtSnapshot(
        user_id=current_user.id,
        debt_type="credit_card",
        debt_id=card.id,
        balance=new_balance,
        snapshot_date=data.payment_date or date.today(),
    )
    db.add(snapshot)

    await db.commit()
    await db.refresh(payment)

    return {
        "payment_id": payment.id,
        "amount": data.amount,
        "new_balance": new_balance,
        "payment_date": str(payment.payment_date),
    }


@router.get("/{card_id}/payoff", response_model=PayoffProjection)
async def get_payoff_projection(
    card_id: uuid.UUID,
    monthly_payment: float | None = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Calculate payoff projection for a credit card.

    If monthly_payment is not specified, uses the card's minimum_payment.
    """
    card = await _get_user_card(card_id, current_user.id, db)

    payment_amount = monthly_payment
    if payment_amount is None:
        if card.minimum_payment is None or float(card.minimum_payment) <= 0:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="No minimum payment set on this card. Provide monthly_payment query parameter.",
            )
        payment_amount = float(card.minimum_payment)

    projection = calculate_cc_payoff(
        balance=float(card.current_balance),
        apr=float(card.apr),
        monthly_payment=payment_amount,
    )
    return projection


# ─── helpers ──────────────────────────────────────────────────────────────────


async def _get_user_card(
    card_id: uuid.UUID, user_id: uuid.UUID, db: AsyncSession
) -> CreditCard:
    """Fetch a credit card by ID and verify ownership."""
    result = await db.execute(
        select(CreditCard).where(
            CreditCard.id == card_id,
            CreditCard.user_id == user_id,
            CreditCard.is_active == True,  # noqa: E712
        )
    )
    card = result.scalar_one_or_none()
    if card is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Credit card not found",
        )
    return card
