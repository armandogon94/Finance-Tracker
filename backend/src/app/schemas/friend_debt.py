import uuid
from datetime import date, datetime

from pydantic import BaseModel


class FriendDepositCreate(BaseModel):
    friend_name: str
    amount: float
    transaction_type: str  # 'deposit' or 'withdrawal'
    description: str | None = None
    transaction_date: date | None = None


class FriendDepositResponse(BaseModel):
    id: uuid.UUID
    friend_name: str
    amount: float
    transaction_type: str
    description: str | None
    transaction_date: date
    created_at: datetime

    model_config = {"from_attributes": True}


class ExternalAccountCreate(BaseModel):
    account_name: str
    current_balance: float = 0


class ExternalAccountUpdate(BaseModel):
    account_name: str | None = None
    current_balance: float | None = None


class ExternalAccountResponse(BaseModel):
    id: uuid.UUID
    account_name: str
    current_balance: float
    last_updated: datetime

    model_config = {"from_attributes": True}


class FriendDebtSummary(BaseModel):
    friend_accumulated: float
    current_bank_balance: float
    amount_owed: float
    external_safety_net: float
    true_shortfall: float
    status: str  # 'clear', 'covered', 'shortfall'
