import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, String, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from src.app.database import Base


class UserFeatureFlag(Base):
    __tablename__ = "user_feature_flags"
    __table_args__ = (
        UniqueConstraint("user_id", "feature_name", name="uq_user_feature"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    feature_name: Mapped[str] = mapped_column(String(50), nullable=False)
    is_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    enabled_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    enabled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
