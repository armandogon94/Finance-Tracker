import uuid
from datetime import datetime

from pydantic import BaseModel


class AutoLabelRuleCreate(BaseModel):
    keyword: str
    category_id: uuid.UUID
    assign_hidden: bool = False
    priority: int = 100


class AutoLabelRuleUpdate(BaseModel):
    keyword: str | None = None
    category_id: uuid.UUID | None = None
    assign_hidden: bool | None = None
    priority: int | None = None
    is_active: bool | None = None


class AutoLabelRuleResponse(BaseModel):
    id: uuid.UUID
    keyword: str
    category_id: uuid.UUID
    assign_hidden: bool
    priority: int
    is_active: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class AutoLabelTestRequest(BaseModel):
    description: str


class AutoLabelTestResponse(BaseModel):
    matched: bool
    rule_keyword: str | None = None
    category_id: uuid.UUID | None = None
    assign_hidden: bool = False


class AutoLabelLearnRequest(BaseModel):
    description: str
    category_id: uuid.UUID


class AutoLabelLearnResponse(BaseModel):
    suggested_keyword: str
    category_id: uuid.UUID
    prompt: str
