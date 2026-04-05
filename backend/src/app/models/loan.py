import uuid
from datetime import date, datetime

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Integer, Numeric, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from src.app.database import Base


class Loan(Base):
    __tablename__ = "loans"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    loan_name: Mapped[str] = mapped_column(String(100), nullable=False)
    lender: Mapped[str | None] = mapped_column(String(100))
    loan_type: Mapped[str] = mapped_column(String(30), nullable=False)  # car/student/personal/mortgage/other
    original_principal: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    current_balance: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    interest_rate: Mapped[float] = mapped_column(Numeric(5, 4), nullable=False)  # annual rate
    interest_rate_type: Mapped[str] = mapped_column(String(10), default="yearly")
    minimum_payment: Mapped[float | None] = mapped_column(Numeric(10, 2))
    due_day: Mapped[int | None] = mapped_column(Integer)
    start_date: Mapped[date | None] = mapped_column(Date)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
