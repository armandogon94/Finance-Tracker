import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, Numeric, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from src.app.database import Base


class CreditCard(Base):
    __tablename__ = "credit_cards"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    card_name: Mapped[str] = mapped_column(String(100), nullable=False)
    last_four: Mapped[str | None] = mapped_column(String(4))
    current_balance: Mapped[float] = mapped_column(Numeric(12, 2), default=0)
    credit_limit: Mapped[float | None] = mapped_column(Numeric(12, 2))
    apr: Mapped[float] = mapped_column(Numeric(5, 4), nullable=False)  # e.g., 0.2499 = 24.99%
    minimum_payment: Mapped[float | None] = mapped_column(Numeric(10, 2))
    statement_day: Mapped[int | None] = mapped_column(Integer)
    due_day: Mapped[int | None] = mapped_column(Integer)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
