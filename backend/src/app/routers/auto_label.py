import re
import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.database import get_db
from src.app.dependencies.auth import get_current_user
from src.app.models.auto_label import AutoLabelRule
from src.app.models.category import Category
from src.app.models.user import User
from src.app.schemas.auto_label import (
    AutoLabelLearnRequest,
    AutoLabelLearnResponse,
    AutoLabelRuleCreate,
    AutoLabelRuleResponse,
    AutoLabelRuleUpdate,
    AutoLabelTestRequest,
    AutoLabelTestResponse,
)

router = APIRouter(prefix="/api/v1/auto-label", tags=["auto-label"])


# ─── List rules ──────────────────────────────────────────────────────────────


@router.get("/rules", response_model=list[AutoLabelRuleResponse])
async def list_rules(
    include_inactive: bool = False,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List all auto-label rules for the current user, sorted by priority."""
    stmt = (
        select(AutoLabelRule)
        .where(AutoLabelRule.user_id == current_user.id)
        .order_by(AutoLabelRule.priority.asc(), AutoLabelRule.keyword.asc())
    )
    if not include_inactive:
        stmt = stmt.where(AutoLabelRule.is_active == True)  # noqa: E712

    result = await db.execute(stmt)
    return result.scalars().all()


# ─── Create rule ─────────────────────────────────────────────────────────────


@router.post("/rules", response_model=AutoLabelRuleResponse, status_code=status.HTTP_201_CREATED)
async def create_rule(
    data: AutoLabelRuleCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a new auto-label rule.

    Rules are matched against transaction descriptions during import.
    Lower priority numbers are evaluated first.
    """
    # Validate category belongs to user
    cat_result = await db.execute(
        select(Category).where(
            Category.id == data.category_id,
            Category.user_id == current_user.id,
            Category.is_active == True,  # noqa: E712
        )
    )
    if cat_result.scalar_one_or_none() is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Category not found or inactive",
        )

    # Check for duplicate keyword
    existing = await db.execute(
        select(AutoLabelRule).where(
            AutoLabelRule.user_id == current_user.id,
            AutoLabelRule.keyword == data.keyword,
        )
    )
    if existing.scalar_one_or_none() is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"A rule with keyword '{data.keyword}' already exists",
        )

    rule = AutoLabelRule(
        user_id=current_user.id,
        keyword=data.keyword,
        category_id=data.category_id,
        assign_hidden=data.assign_hidden,
        priority=data.priority,
    )
    db.add(rule)
    await db.commit()
    await db.refresh(rule)

    return rule


# ─── Update rule ─────────────────────────────────────────────────────────────


@router.patch("/rules/{rule_id}", response_model=AutoLabelRuleResponse)
async def update_rule(
    rule_id: uuid.UUID,
    data: AutoLabelRuleUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update an existing auto-label rule's fields."""
    rule = await _get_user_rule(rule_id, current_user.id, db)

    update_data = data.model_dump(exclude_unset=True)
    if not update_data:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="No fields provided to update",
        )

    # Validate category if being changed
    if "category_id" in update_data and update_data["category_id"] is not None:
        cat_result = await db.execute(
            select(Category).where(
                Category.id == update_data["category_id"],
                Category.user_id == current_user.id,
                Category.is_active == True,  # noqa: E712
            )
        )
        if cat_result.scalar_one_or_none() is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Category not found or inactive",
            )

    # Check for keyword uniqueness if changing keyword
    if "keyword" in update_data and update_data["keyword"] != rule.keyword:
        existing = await db.execute(
            select(AutoLabelRule).where(
                AutoLabelRule.user_id == current_user.id,
                AutoLabelRule.keyword == update_data["keyword"],
                AutoLabelRule.id != rule_id,
            )
        )
        if existing.scalar_one_or_none() is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"A rule with keyword '{update_data['keyword']}' already exists",
            )

    for field, value in update_data.items():
        setattr(rule, field, value)

    db.add(rule)
    await db.commit()
    await db.refresh(rule)

    return rule


# ─── Delete rule ─────────────────────────────────────────────────────────────


@router.delete("/rules/{rule_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_rule(
    rule_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Permanently delete an auto-label rule."""
    rule = await _get_user_rule(rule_id, current_user.id, db)
    await db.delete(rule)
    await db.commit()


# ─── Test a description against rules ────────────────────────────────────────


@router.post("/test", response_model=AutoLabelTestResponse)
async def test_description(
    data: AutoLabelTestRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Test a transaction description against the user's auto-label rules.

    Returns which rule (if any) would match, useful for previewing behavior
    before importing a statement.
    """
    result = await db.execute(
        select(AutoLabelRule)
        .where(
            AutoLabelRule.user_id == current_user.id,
            AutoLabelRule.is_active == True,  # noqa: E712
        )
        .order_by(AutoLabelRule.priority.asc())
    )
    rules = result.scalars().all()

    desc_lower = data.description.lower()
    for rule in rules:
        if rule.keyword.lower() in desc_lower:
            return AutoLabelTestResponse(
                matched=True,
                rule_keyword=rule.keyword,
                category_id=rule.category_id,
                assign_hidden=rule.assign_hidden,
            )

    return AutoLabelTestResponse(matched=False)


# ─── Learn / suggest a rule ──────────────────────────────────────────────────


@router.post("/learn", response_model=AutoLabelLearnResponse)
async def learn_rule(
    data: AutoLabelLearnRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Given a transaction description and chosen category, extract a keyword and suggest a rule.

    Uses simple heuristics to identify the most distinctive word in the
    description that could serve as a reliable matching keyword for future
    transactions from the same merchant/source.
    """
    # Validate category
    cat_result = await db.execute(
        select(Category).where(
            Category.id == data.category_id,
            Category.user_id == current_user.id,
            Category.is_active == True,  # noqa: E712
        )
    )
    category = cat_result.scalar_one_or_none()
    if category is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Category not found or inactive",
        )

    # Extract keyword from description
    suggested_keyword = _extract_keyword(data.description)

    # Check if this keyword already exists
    existing = await db.execute(
        select(AutoLabelRule).where(
            AutoLabelRule.user_id == current_user.id,
            AutoLabelRule.keyword == suggested_keyword,
        )
    )
    existing_rule = existing.scalar_one_or_none()

    if existing_rule:
        prompt = (
            f"A rule for '{suggested_keyword}' already exists "
            f"(assigned to a different category). Would you like to update it?"
        )
    else:
        prompt = (
            f"Create a rule: when a transaction contains '{suggested_keyword}', "
            f"auto-assign it to '{category.name}'?"
        )

    return AutoLabelLearnResponse(
        suggested_keyword=suggested_keyword,
        category_id=data.category_id,
        prompt=prompt,
    )


# ─── Helpers ─────────────────────────────────────────────────────────────────


# Common stopwords to ignore when extracting keywords
_STOPWORDS = {
    "the", "a", "an", "and", "or", "of", "to", "in", "for", "on", "at", "by",
    "with", "from", "is", "it", "that", "this", "was", "are", "be", "has",
    "had", "have", "not", "but", "what", "all", "were", "we", "when",
    "pos", "debit", "credit", "card", "purchase", "payment", "transaction",
    "online", "pending", "authorized", "recurring", "check", "checkcard",
    "visa", "mastercard", "amex", "dc", "ach", "wire", "transfer",
}


def _extract_keyword(description: str) -> str:
    """Extract the most likely merchant/source keyword from a transaction description.

    Heuristics:
    1. Remove common bank transaction prefixes (POS, DEBIT, etc.)
    2. Remove dates and reference numbers
    3. Pick the longest non-stopword token as the keyword
    4. If the result is too short, use the first two words
    """
    # Clean up the description
    cleaned = description.strip()

    # Remove common prefixes
    prefixes = [
        r"^(POS|DEBIT|CREDIT|ACH|CHECKCARD|CHECK CARD|VISA|MC|AMEX)\s+",
        r"^(PURCHASE|PAYMENT|RECURRING|AUTOPAY)\s+",
        r"^\d{2}/\d{2}\s+",  # Date prefixes like "03/29"
    ]
    for pattern in prefixes:
        cleaned = re.sub(pattern, "", cleaned, flags=re.IGNORECASE)

    # Remove trailing reference numbers and dates
    cleaned = re.sub(r"\s+\d{4,}$", "", cleaned)  # Trailing long numbers
    cleaned = re.sub(r"\s+\d{2}/\d{2}/?\d{0,4}$", "", cleaned)  # Trailing dates
    cleaned = re.sub(r"\s+#\S+$", "", cleaned)  # Trailing references like #12345
    cleaned = re.sub(r"\s+\*+\d+$", "", cleaned)  # Patterns like *1234

    # Tokenize and filter
    tokens = cleaned.split()
    meaningful = [
        t for t in tokens
        if t.lower() not in _STOPWORDS
        and len(t) > 1
        and not t.isdigit()
    ]

    if not meaningful:
        # Fallback: use first word of the original
        tokens = description.split()
        return tokens[0] if tokens else description[:20]

    # Pick the longest token as it's likely the merchant name
    keyword = max(meaningful, key=len)

    # If it's very short, combine first two meaningful tokens
    if len(keyword) <= 3 and len(meaningful) >= 2:
        keyword = " ".join(meaningful[:2])

    return keyword


async def _get_user_rule(
    rule_id: uuid.UUID, user_id: uuid.UUID, db: AsyncSession
) -> AutoLabelRule:
    """Fetch an auto-label rule by ID and verify ownership."""
    result = await db.execute(
        select(AutoLabelRule).where(
            AutoLabelRule.id == rule_id,
            AutoLabelRule.user_id == user_id,
        )
    )
    rule = result.scalar_one_or_none()
    if rule is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Auto-label rule not found",
        )
    return rule
