import uuid
from datetime import date, datetime

from pydantic import BaseModel


# Credit Cards
class CreditCardCreate(BaseModel):
    card_name: str
    last_four: str | None = None
    current_balance: float = 0
    credit_limit: float | None = None
    apr: float  # Annual rate as decimal, e.g., 0.2499 = 24.99%
    minimum_payment: float | None = None
    statement_day: int | None = None
    due_day: int | None = None


class CreditCardUpdate(BaseModel):
    card_name: str | None = None
    current_balance: float | None = None
    credit_limit: float | None = None
    apr: float | None = None
    minimum_payment: float | None = None
    statement_day: int | None = None
    due_day: int | None = None


class CreditCardResponse(BaseModel):
    id: uuid.UUID
    card_name: str
    last_four: str | None
    current_balance: float
    credit_limit: float | None
    apr: float
    minimum_payment: float | None
    statement_day: int | None
    due_day: int | None
    utilization: float | None  # Computed field
    is_active: bool
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


# Loans
class LoanCreate(BaseModel):
    loan_name: str
    lender: str | None = None
    loan_type: str  # car/student/personal/mortgage/other
    original_principal: float
    current_balance: float
    interest_rate: float  # Annual rate as decimal
    interest_rate_type: str = "yearly"
    minimum_payment: float | None = None
    due_day: int | None = None
    start_date: date | None = None


class LoanUpdate(BaseModel):
    loan_name: str | None = None
    lender: str | None = None
    current_balance: float | None = None
    interest_rate: float | None = None
    minimum_payment: float | None = None
    due_day: int | None = None


class LoanResponse(BaseModel):
    id: uuid.UUID
    loan_name: str
    lender: str | None
    loan_type: str
    original_principal: float
    current_balance: float
    interest_rate: float
    interest_rate_type: str
    minimum_payment: float | None
    due_day: int | None
    start_date: date | None
    progress_percent: float  # Computed: (original - current) / original * 100
    is_active: bool
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


# Payments
class DebtPaymentCreate(BaseModel):
    amount: float
    payment_date: date | None = None
    is_snowflake: bool = False
    notes: str | None = None


# Strategy
class StrategyRequest(BaseModel):
    monthly_budget: float


class PayoffProjection(BaseModel):
    payoff_months: int | float
    total_interest: float
    payoff_date: str | None
    warning: str | None = None


class StrategyResult(BaseModel):
    strategy: str
    months_to_freedom: int
    total_interest: float
    payoff_order: list[str]


class StrategyComparison(BaseModel):
    avalanche: StrategyResult
    snowball: StrategyResult
    hybrid: StrategyResult
    minimum_only: StrategyResult
    recommendation: str
