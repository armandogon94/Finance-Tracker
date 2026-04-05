import uuid
from datetime import datetime

from pydantic import BaseModel


class CategoryCreate(BaseModel):
    name: str
    icon: str = "receipt"
    color: str = "#3B82F6"
    is_hidden: bool = False
    monthly_budget: float | None = None


class CategoryUpdate(BaseModel):
    name: str | None = None
    icon: str | None = None
    color: str | None = None
    is_hidden: bool | None = None
    monthly_budget: float | None = None


class CategoryResponse(BaseModel):
    id: uuid.UUID
    name: str
    icon: str
    color: str
    sort_order: int
    is_active: bool
    is_hidden: bool
    monthly_budget: float | None
    created_at: datetime

    model_config = {"from_attributes": True}


class CategoryReorder(BaseModel):
    category_ids: list[uuid.UUID]  # Ordered list of category IDs in new sort order
