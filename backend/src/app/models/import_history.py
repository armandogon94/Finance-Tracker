import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from src.app.database import Base


class ImportHistory(Base):
    __tablename__ = "import_history"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    source_type: Mapped[str] = mapped_column(String(10), nullable=False)  # 'csv' or 'pdf'
    bank_preset: Mapped[str | None] = mapped_column(String(50))
    original_filename: Mapped[str | None] = mapped_column(String(255))
    transactions_parsed: Mapped[int] = mapped_column(Integer, default=0)
    transactions_imported: Mapped[int] = mapped_column(Integer, default=0)
    import_date: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
