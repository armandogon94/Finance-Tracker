import uuid
from datetime import datetime

from sqlalchemy import JSON, DateTime, ForeignKey, Integer, Numeric, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from src.app.database import Base


class MonthlySummary(Base):
    __tablename__ = "monthly_summaries"
    __table_args__ = (
        UniqueConstraint("user_id", "year", "month", name="uq_monthly_summary"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    year: Mapped[int] = mapped_column(Integer, nullable=False)
    month: Mapped[int] = mapped_column(Integer, nullable=False)
    total_spent: Mapped[float] = mapped_column(Numeric(12, 2), default=0)
    total_tax: Mapped[float] = mapped_column(Numeric(12, 2), default=0)
    category_breakdown: Mapped[dict | None] = mapped_column(JSON)
    transaction_count: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
