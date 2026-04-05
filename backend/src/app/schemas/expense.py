import uuid
from datetime import date, datetime, time

from pydantic import BaseModel


class ExpenseCreate(BaseModel):
    category_id: uuid.UUID | None = None
    amount: float
    tax_amount: float = 0
    currency: str = "USD"
    description: str | None = None
    merchant_name: str | None = None
    expense_date: date | None = None
    expense_time: time | None = None
    notes: str | None = None
    is_recurring: bool = False
    is_tax_deductible: bool = False
    tags: list[str] | None = None


class ExpenseQuickAdd(BaseModel):
    amount: float
    category_id: uuid.UUID


class ExpenseUpdate(BaseModel):
    category_id: uuid.UUID | None = None
    amount: float | None = None
    tax_amount: float | None = None
    description: str | None = None
    merchant_name: str | None = None
    expense_date: date | None = None
    notes: str | None = None
    is_tax_deductible: bool | None = None
    tags: list[str] | None = None


class ExpenseResponse(BaseModel):
    id: uuid.UUID
    category_id: uuid.UUID | None
    amount: float
    tax_amount: float
    currency: str
    description: str | None
    merchant_name: str | None
    expense_date: date
    expense_time: time | None
    notes: str | None
    receipt_image_path: str | None
    ocr_method: str | None
    is_recurring: bool
    is_tax_deductible: bool
    tags: list[str] | None
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class ExpenseListResponse(BaseModel):
    items: list[ExpenseResponse]
    total: int
    page: int
    per_page: int
