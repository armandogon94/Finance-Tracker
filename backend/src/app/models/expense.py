import uuid
from datetime import date, datetime, time

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Numeric,
    String,
    Text,
    Time,
    func,
)
from sqlalchemy import JSON
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from src.app.database import Base


class Expense(Base):
    __tablename__ = "expenses"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    category_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("categories.id", ondelete="SET NULL"), index=True
    )
    amount: Mapped[float] = mapped_column(Numeric(10, 2), nullable=False)
    tax_amount: Mapped[float] = mapped_column(Numeric(10, 2), default=0)
    currency: Mapped[str] = mapped_column(String(3), default="USD")
    description: Mapped[str | None] = mapped_column(String(500))
    merchant_name: Mapped[str | None] = mapped_column(String(255), index=True)
    expense_date: Mapped[date] = mapped_column(Date, nullable=False, default=date.today)
    expense_time: Mapped[time | None] = mapped_column(Time)
    notes: Mapped[str | None] = mapped_column(Text)

    # Receipt data
    receipt_image_path: Mapped[str | None] = mapped_column(String(500))
    receipt_ocr_data: Mapped[dict | None] = mapped_column(JSON)
    ocr_method: Mapped[str | None] = mapped_column(String(20))
    ocr_confidence: Mapped[float | None] = mapped_column(Numeric(3, 2))

    # Metadata
    is_recurring: Mapped[bool] = mapped_column(Boolean, default=False)
    is_tax_deductible: Mapped[bool] = mapped_column(Boolean, default=False)
    tags: Mapped[list[str] | None] = mapped_column(JSON)
    import_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    # Relationships
    user = relationship("User", back_populates="expenses")
    category = relationship("Category", back_populates="expenses")
