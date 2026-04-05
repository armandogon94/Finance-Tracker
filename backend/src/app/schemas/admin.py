import uuid
from datetime import datetime

from pydantic import BaseModel


class AdminUserResponse(BaseModel):
    id: uuid.UUID
    email: str
    display_name: str | None
    is_active: bool
    is_superuser: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class FeatureFlagToggle(BaseModel):
    feature_name: str
    is_enabled: bool


class FeatureFlagResponse(BaseModel):
    feature_name: str
    is_enabled: bool
    enabled_at: datetime | None

    model_config = {"from_attributes": True}


class SystemStats(BaseModel):
    total_users: int
    active_users: int
    total_expenses: int
    total_receipts: int
    total_debt_items: int
