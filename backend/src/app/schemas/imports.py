import uuid
from datetime import date

from pydantic import BaseModel


class ParsedTransaction(BaseModel):
    date: date
    description: str
    amount: float
    is_expense: bool = True
    suggested_category_id: uuid.UUID | None = None
    auto_labeled: bool = False
    label_rule_name: str | None = None
    is_hidden: bool = False
    possible_duplicate: bool = False
    duplicate_confidence: float | None = None
    include: bool = True


class ImportPreview(BaseModel):
    transactions: list[ParsedTransaction]
    total_parsed: int
    bank_detected: str | None
    source_type: str  # 'csv' or 'pdf'
    filename: str


class ImportConfirm(BaseModel):
    transactions: list[ParsedTransaction]
    source_type: str
    bank_preset: str | None = None
    original_filename: str | None = None


class ImportResult(BaseModel):
    imported: int
    skipped: int
    import_id: uuid.UUID
