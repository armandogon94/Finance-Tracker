"""
AI Finance Chat service.

Handles intent classification, financial data retrieval from PostgreSQL,
and Claude API calls with streaming for the chat interface.
"""

import json
import logging
import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from typing import Any, AsyncGenerator

import anthropic
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.config import settings
from src.app.models.category import Category
from src.app.models.credit_card import CreditCard
from src.app.models.expense import Expense
from src.app.models.loan import Loan
from src.app.models.monthly_summary import MonthlySummary

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Intent classification
# ---------------------------------------------------------------------------

INTENT_KEYWORDS = {
    "spending": [
        "spend", "spent", "spending", "cost", "paid", "expense", "expenses",
        "how much", "total", "bought", "purchase", "gasto", "gastos", "gasté",
    ],
    "budget": [
        "budget", "on track", "over budget", "under budget", "limit",
        "overspending", "save", "saving", "reduce", "presupuesto",
    ],
    "debt": [
        "debt", "credit card", "loan", "pay off", "payoff", "interest",
        "balance", "owe", "owed", "deuda", "tarjeta", "préstamo",
    ],
    "category": [
        "category", "categories", "groceries", "food", "dining", "transport",
        "entertainment", "bills", "health", "shopping", "categoría",
    ],
    "trend": [
        "trend", "compare", "comparison", "vs", "versus", "month over month",
        "increase", "decrease", "change", "tendencia",
    ],
}


def classify_intent(message: str) -> list[str]:
    """Classify user message into financial intents using keyword matching.

    Returns a list of matching intents (may be multiple).
    """
    lower = message.lower()
    intents = []
    for intent, keywords in INTENT_KEYWORDS.items():
        if any(kw in lower for kw in keywords):
            intents.append(intent)
    return intents or ["general"]


# ---------------------------------------------------------------------------
# Financial data retrieval
# ---------------------------------------------------------------------------


class DecimalEncoder(json.JSONEncoder):
    def default(self, obj: Any) -> Any:
        if isinstance(obj, Decimal):
            return float(obj)
        if isinstance(obj, (date, datetime)):
            return obj.isoformat()
        if isinstance(obj, uuid.UUID):
            return str(obj)
        return super().default(obj)


async def get_financial_context(
    user_id: uuid.UUID,
    intents: list[str],
    db: AsyncSession,
) -> dict[str, Any]:
    """Query PostgreSQL for relevant financial data based on detected intents.

    Builds a context dict that gets included in the Claude prompt.
    """
    context: dict[str, Any] = {}
    today = date.today()
    month_start = today.replace(day=1)
    last_month_start = (month_start - timedelta(days=1)).replace(day=1)

    if "spending" in intents or "general" in intents:
        context["current_month_spending"] = await _get_monthly_spending(
            user_id, month_start, today, db
        )
        context["last_month_spending"] = await _get_monthly_spending(
            user_id, last_month_start, month_start - timedelta(days=1), db
        )

    if "category" in intents or "spending" in intents or "general" in intents:
        context["category_breakdown"] = await _get_category_breakdown(
            user_id, month_start, today, db
        )

    if "budget" in intents or "general" in intents:
        context["budget_status"] = await _get_budget_status(user_id, month_start, today, db)

    if "debt" in intents or "general" in intents:
        context["debts"] = await _get_debt_summary(user_id, db)

    if "trend" in intents:
        context["monthly_trends"] = await _get_monthly_trends(user_id, db)

    # Always include recent expenses for context
    context["recent_expenses"] = await _get_recent_expenses(user_id, db, limit=10)

    return context


async def _get_monthly_spending(
    user_id: uuid.UUID, start: date, end: date, db: AsyncSession
) -> dict:
    result = await db.execute(
        select(
            func.coalesce(func.sum(Expense.amount), 0).label("total"),
            func.count(Expense.id).label("count"),
        )
        .where(
            Expense.user_id == user_id,
            Expense.expense_date >= start,
            Expense.expense_date <= end,
        )
    )
    row = result.one()
    return {"total": float(row.total), "transaction_count": int(row.count)}


async def _get_category_breakdown(
    user_id: uuid.UUID, start: date, end: date, db: AsyncSession
) -> list[dict]:
    result = await db.execute(
        select(
            Category.name,
            func.coalesce(func.sum(Expense.amount), 0).label("total"),
            func.count(Expense.id).label("count"),
        )
        .join(Category, Expense.category_id == Category.id, isouter=True)
        .where(
            Expense.user_id == user_id,
            Expense.expense_date >= start,
            Expense.expense_date <= end,
        )
        .group_by(Category.name)
        .order_by(func.sum(Expense.amount).desc())
    )
    return [
        {"category": row.name or "Uncategorized", "total": float(row.total), "count": int(row.count)}
        for row in result.all()
    ]


async def _get_budget_status(
    user_id: uuid.UUID, start: date, end: date, db: AsyncSession
) -> list[dict]:
    result = await db.execute(
        select(
            Category.name,
            Category.monthly_budget,
            func.coalesce(func.sum(Expense.amount), 0).label("spent"),
        )
        .join(Category, Expense.category_id == Category.id)
        .where(
            Expense.user_id == user_id,
            Expense.expense_date >= start,
            Expense.expense_date <= end,
            Category.monthly_budget.isnot(None),
        )
        .group_by(Category.name, Category.monthly_budget)
    )
    return [
        {
            "category": row.name,
            "budget": float(row.monthly_budget),
            "spent": float(row.spent),
            "remaining": float(row.monthly_budget) - float(row.spent),
            "percent_used": round(float(row.spent) / float(row.monthly_budget) * 100, 1)
            if float(row.monthly_budget) > 0
            else 0,
        }
        for row in result.all()
    ]


async def _get_debt_summary(user_id: uuid.UUID, db: AsyncSession) -> dict:
    cards_result = await db.execute(
        select(CreditCard).where(
            CreditCard.user_id == user_id,
            CreditCard.is_active == True,  # noqa: E712
        )
    )
    cards = cards_result.scalars().all()

    loans_result = await db.execute(
        select(Loan).where(
            Loan.user_id == user_id,
            Loan.is_active == True,  # noqa: E712
        )
    )
    loans = loans_result.scalars().all()

    return {
        "credit_cards": [
            {
                "name": c.card_name,
                "balance": float(c.current_balance),
                "limit": float(c.credit_limit) if c.credit_limit else None,
                "apr": float(c.apr),
                "minimum_payment": float(c.minimum_payment),
            }
            for c in cards
        ],
        "loans": [
            {
                "name": ln.loan_name,
                "balance": float(ln.current_balance),
                "rate": float(ln.interest_rate),
                "minimum_payment": float(ln.minimum_payment),
            }
            for ln in loans
        ],
        "total_debt": sum(float(c.current_balance) for c in cards)
        + sum(float(ln.current_balance) for ln in loans),
    }


async def _get_monthly_trends(user_id: uuid.UUID, db: AsyncSession) -> list[dict]:
    result = await db.execute(
        select(MonthlySummary)
        .where(MonthlySummary.user_id == user_id)
        .order_by(MonthlySummary.year.desc(), MonthlySummary.month.desc())
        .limit(6)
    )
    summaries = result.scalars().all()
    return [
        {
            "year": s.year,
            "month": s.month,
            "total_spent": float(s.total_spent),
            "transaction_count": s.transaction_count,
        }
        for s in summaries
    ]


async def _get_recent_expenses(
    user_id: uuid.UUID, db: AsyncSession, limit: int = 10
) -> list[dict]:
    result = await db.execute(
        select(Expense)
        .where(Expense.user_id == user_id)
        .order_by(Expense.expense_date.desc(), Expense.created_at.desc())
        .limit(limit)
    )
    expenses = result.scalars().all()
    return [
        {
            "amount": float(e.amount),
            "description": e.description,
            "merchant": e.merchant_name,
            "date": e.expense_date.isoformat(),
        }
        for e in expenses
    ]


# ---------------------------------------------------------------------------
# Claude API streaming
# ---------------------------------------------------------------------------

SYSTEM_PROMPT = """You are a helpful personal finance assistant for a user's expense tracker app.
You have access to the user's actual financial data provided in the context below.

Guidelines:
- Be concise and actionable. Use bullet points for clarity.
- Reference specific numbers from the data when answering.
- For spending queries, always mention the time period you're analyzing.
- For debt advice, consider interest rates and recommend optimal strategies.
- Support both English and Spanish — respond in whatever language the user writes in.
- Format currency amounts with $ and two decimal places.
- If the data doesn't contain enough info to answer, say so honestly.
- Never fabricate financial data — only reference what's in the context."""


MODEL_MAP = {
    "haiku": "claude-haiku-4-5-20251001",
    "sonnet": "claude-sonnet-4-5-20241022",
}


async def stream_chat_response(
    user_message: str,
    conversation_history: list[dict],
    financial_context: dict,
    model: str = "haiku",
) -> AsyncGenerator[str, None]:
    """Stream a Claude response with financial context.

    Yields text chunks as they arrive from the API.
    Returns the final full text after the stream completes (via a sentinel).
    """
    if not settings.anthropic_api_key:
        yield "I'm sorry, the AI chat feature requires an API key to be configured. Please contact your administrator."
        return

    model_id = MODEL_MAP.get(model, MODEL_MAP["haiku"])
    context_str = json.dumps(financial_context, cls=DecimalEncoder, indent=2)

    messages = []
    for msg in conversation_history[-20:]:  # Keep last 20 messages for context window
        messages.append({"role": msg["role"], "content": msg["content"]})
    messages.append({"role": "user", "content": user_message})

    system_with_context = (
        f"{SYSTEM_PROMPT}\n\n"
        f"--- USER'S FINANCIAL DATA ---\n{context_str}\n--- END FINANCIAL DATA ---"
    )

    try:
        client = anthropic.Anthropic(api_key=settings.anthropic_api_key)

        with client.messages.stream(
            model=model_id,
            max_tokens=2048,
            system=system_with_context,
            messages=messages,
        ) as stream:
            for text in stream.text_stream:
                yield text

    except anthropic.APIError as exc:
        logger.error("Claude API error in chat: %s", exc)
        yield f"I encountered an error communicating with the AI service. Please try again later."
    except Exception as exc:
        logger.error("Unexpected error in chat stream: %s", exc, exc_info=True)
        yield "An unexpected error occurred. Please try again."


def get_token_usage_estimate(model: str, context_size: int, response_size: int) -> dict:
    """Estimate token costs for display to the user."""
    # Rough estimates: 1 token ≈ 4 characters
    input_tokens = context_size // 4
    output_tokens = response_size // 4

    costs = {
        "haiku": {"input": 0.80 / 1_000_000, "output": 4.00 / 1_000_000},
        "sonnet": {"input": 3.00 / 1_000_000, "output": 15.00 / 1_000_000},
    }
    rates = costs.get(model, costs["haiku"])

    return {
        "model": model,
        "estimated_input_tokens": input_tokens,
        "estimated_output_tokens": output_tokens,
        "estimated_cost_usd": round(
            input_tokens * rates["input"] + output_tokens * rates["output"], 6
        ),
    }
