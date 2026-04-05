"""
Seed script for demo data.

Creates 3 demo accounts with realistic financial data including expenses,
credit cards, loans, debt payments, chat conversations, and auto-label rules.

Usage:
    cd backend && uv run python scripts/seed_demo_data.py

Idempotent: skips creation if demo@armando.com already exists.
"""

import asyncio
import random
import sys
import uuid
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path

# Ensure the backend package is importable when running from backend/
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from src.app.config import settings
from src.app.database import Base
from src.app.dependencies.auth import hash_password
from src.app.models.auto_label import AutoLabelRule
from src.app.models.category import Category
from src.app.models.chat import ChatConversation, ChatMessage
from src.app.models.credit_card import CreditCard
from src.app.models.debt_payment import DebtPayment
from src.app.models.expense import Expense
from src.app.models.feature_flag import UserFeatureFlag
from src.app.models.friend_debt import ExternalAccount, FriendDeposit
from src.app.models.loan import Loan
from src.app.models.user import User

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

TODAY = date.today()
PASSWORD_HASH = hash_password("Demo1234!")

DEMO_ACCOUNTS = [
    {
        "email": "demo@armando.com",
        "display_name": "Armando Demo",
        "is_superuser": True,
    },
    {
        "email": "demo@maria.com",
        "display_name": "Maria Demo",
        "is_superuser": False,
    },
    {
        "email": "demo@reviewer.com",
        "display_name": "Demo Reviewer",
        "is_superuser": False,
    },
]

# Default categories shared by all users (name, icon, color)
DEFAULT_CATEGORIES = [
    ("Groceries", "shopping-cart", "#22C55E"),
    ("Transport", "car", "#3B82F6"),
    ("Coffee", "coffee", "#92400E"),
    ("Dining", "utensils", "#EF4444"),
    ("Subscriptions", "credit-card", "#8B5CF6"),
    ("Shopping", "bag", "#F59E0B"),
    ("Bills", "file-text", "#6366F1"),
    ("Health", "heart", "#EC4899"),
    ("Entertainment", "film", "#14B8A6"),
]

# Per-user custom categories (index -> extra categories)
CUSTOM_CATEGORIES = {
    0: [("Travel", "plane", "#0EA5E9"), ("Gifts", "gift", "#D946EF"), ("Education", "book", "#0D9488"), ("Pets", "paw-print", "#A3E635")],
    1: [("Kids", "baby", "#FB923C"), ("Beauty", "sparkles", "#F472B6"), ("Home", "home", "#84CC16")],
    2: [("Freelance", "briefcase", "#6D28D9"), ("Tech", "monitor", "#06B6D4"), ("Fitness", "dumbbell", "#F43F5E"), ("Books", "book-open", "#8B5CF6")],
}

# ---------------------------------------------------------------------------
# Expense templates per category name
# ---------------------------------------------------------------------------

EXPENSE_TEMPLATES: dict[str, list[tuple[str, str, float, float]]] = {
    # (description, merchant_name, min_amount, max_amount)
    "Groceries": [
        ("Weekly groceries", "Whole Foods", 45.0, 89.0),
        ("Groceries run", "Trader Joe's", 35.0, 65.0),
        ("Quick grocery stop", "Costco", 80.0, 160.0),
        ("Fresh produce", "Sprouts", 25.0, 55.0),
    ],
    "Transport": [
        ("Ride to downtown", "Uber", 8.0, 25.0),
        ("Gas fill-up", "Shell Gas Station", 35.0, 55.0),
        ("Metro commute", "Metro Transit", 2.75, 2.75),
        ("Ride to airport", "Lyft", 22.0, 45.0),
    ],
    "Coffee": [
        ("Morning coffee", "Starbucks", 5.0, 8.0),
        ("Latte & pastry", "Starbucks", 7.0, 12.0),
        ("Iced coffee", "Dunkin", 4.0, 6.5),
        ("Espresso", "Blue Bottle Coffee", 5.5, 9.0),
    ],
    "Dining": [
        ("Lunch burrito", "Chipotle", 12.0, 18.0),
        ("Dinner out", "Olive Garden", 25.0, 55.0),
        ("Thai takeout", "Thai Palace", 15.0, 28.0),
        ("Pizza night", "Dominos", 18.0, 35.0),
        ("Sushi dinner", "Nobu", 40.0, 85.0),
    ],
    "Subscriptions": [
        ("Netflix monthly", "Netflix", 15.99, 15.99),
        ("Spotify Premium", "Spotify", 10.99, 10.99),
        ("iCloud storage", "Apple", 2.99, 2.99),
        ("ChatGPT Plus", "OpenAI", 20.0, 20.0),
        ("YouTube Premium", "Google", 13.99, 13.99),
    ],
    "Shopping": [
        ("Online order", "Amazon", 15.0, 150.0),
        ("Household items", "Target", 20.0, 80.0),
        ("Clothing", "Zara", 35.0, 120.0),
        ("Electronics", "Best Buy", 25.0, 200.0),
    ],
    "Bills": [
        ("Monthly rent", "Landlord", 1500.0, 2200.0),
        ("Internet bill", "Xfinity", 60.0, 90.0),
        ("Phone bill", "T-Mobile", 45.0, 85.0),
        ("Electric bill", "ConEd", 80.0, 160.0),
        ("Water bill", "City Water", 30.0, 55.0),
    ],
    "Health": [
        ("Gym membership", "Planet Fitness", 50.0, 50.0),
        ("Pharmacy", "CVS Pharmacy", 15.0, 45.0),
        ("Doctor copay", "Medical Center", 30.0, 50.0),
        ("Vitamins", "GNC", 20.0, 40.0),
    ],
    "Entertainment": [
        ("Movie tickets", "AMC Theatres", 15.0, 30.0),
        ("Concert tickets", "Ticketmaster", 45.0, 120.0),
        ("Bowling night", "Bowl-O-Rama", 20.0, 40.0),
        ("Video game", "Steam", 10.0, 60.0),
    ],
}

# Per-user credit card definitions
CREDIT_CARDS_PER_USER = [
    # User 0 (Armando)
    [
        {"card_name": "Chase Sapphire Preferred", "last_four": "4821", "current_balance": 4350.00, "credit_limit": 15000.0, "apr": 0.2299, "minimum_payment": 95.0, "statement_day": 15, "due_day": 5},
        {"card_name": "Amex Gold Card", "last_four": "7193", "current_balance": 2180.00, "credit_limit": 10000.0, "apr": 0.1999, "minimum_payment": 65.0, "statement_day": 20, "due_day": 10},
        {"card_name": "Capital One Venture", "last_four": "3305", "current_balance": 890.00, "credit_limit": 8000.0, "apr": 0.2149, "minimum_payment": 35.0, "statement_day": 1, "due_day": 22},
    ],
    # User 1 (Maria)
    [
        {"card_name": "Chase Freedom Unlimited", "last_four": "6247", "current_balance": 3200.00, "credit_limit": 12000.0, "apr": 0.2099, "minimum_payment": 78.0, "statement_day": 10, "due_day": 1},
        {"card_name": "Amex Blue Cash Everyday", "last_four": "5518", "current_balance": 1850.00, "credit_limit": 8000.0, "apr": 0.1899, "minimum_payment": 55.0, "statement_day": 25, "due_day": 15},
    ],
    # User 2 (Reviewer)
    [
        {"card_name": "Chase Sapphire Reserve", "last_four": "9012", "current_balance": 5500.00, "credit_limit": 20000.0, "apr": 0.2299, "minimum_payment": 120.0, "statement_day": 5, "due_day": 25},
        {"card_name": "Citi Double Cash", "last_four": "1177", "current_balance": 2500.00, "credit_limit": 10000.0, "apr": 0.1849, "minimum_payment": 60.0, "statement_day": 18, "due_day": 8},
    ],
]

# Per-user loan definitions
LOANS_PER_USER = [
    # User 0 (Armando)
    [
        {"loan_name": "Car Loan - Honda Civic", "lender": "Chase Auto", "loan_type": "car", "original_principal": 28000.0, "current_balance": 19500.0, "interest_rate": 0.0549, "minimum_payment": 485.0, "due_day": 15, "start_date": date(2023, 3, 1)},
        {"loan_name": "Federal Student Loan", "lender": "Dept of Education", "loan_type": "student", "original_principal": 35000.0, "current_balance": 13200.0, "interest_rate": 0.0475, "minimum_payment": 320.0, "due_day": 1, "start_date": date(2019, 9, 1)},
    ],
    # User 1 (Maria)
    [
        {"loan_name": "Car Loan - Toyota RAV4", "lender": "Toyota Financial", "loan_type": "car", "original_principal": 32000.0, "current_balance": 22000.0, "interest_rate": 0.0599, "minimum_payment": 520.0, "due_day": 20, "start_date": date(2023, 6, 1)},
        {"loan_name": "Personal Loan", "lender": "SoFi", "loan_type": "personal", "original_principal": 10000.0, "current_balance": 6800.0, "interest_rate": 0.0899, "minimum_payment": 250.0, "due_day": 5, "start_date": date(2024, 1, 15)},
    ],
    # User 2 (Reviewer)
    [
        {"loan_name": "Student Loan - Grad School", "lender": "Sallie Mae", "loan_type": "student", "original_principal": 45000.0, "current_balance": 14500.0, "interest_rate": 0.0525, "minimum_payment": 380.0, "due_day": 10, "start_date": date(2018, 8, 1)},
    ],
]

# Per-user chat conversations
CHAT_CONVERSATIONS = [
    # User 0 (Armando)
    [
        {
            "title": "Monthly spending analysis",
            "messages": [
                ("user", "How much did I spend on dining out last month?"),
                ("assistant", "Based on your expenses, you spent approximately $287.50 on dining last month across 8 transactions. Your most frequent restaurant was Chipotle (4 visits), followed by Thai Palace (2 visits). This is about 12% of your total monthly spending. Would you like me to compare this to previous months?"),
                ("user", "Yes, how does that compare to the month before?"),
                ("assistant", "Two months ago you spent $195.20 on dining, which means last month saw a 47% increase. The jump was mainly due to two higher-end dinners at Nobu ($78 and $65). If you'd like to set a dining budget alert, I can help with that."),
            ],
        },
        {
            "title": "Debt payoff strategy",
            "messages": [
                ("user", "What's the fastest way to pay off my credit cards?"),
                ("assistant", "You have 3 credit cards with a combined balance of $7,420. I'd recommend the avalanche method since your Chase Sapphire has the highest APR at 22.99%. Here's the priority:\n\n1. Chase Sapphire Preferred ($4,350 at 22.99%) - focus extra payments here\n2. Capital One Venture ($890 at 21.49%) - small balance, quick win\n3. Amex Gold ($2,180 at 19.99%) - lowest rate\n\nIf you put an extra $300/month toward the highest-rate card while making minimums on the others, you could be debt-free in about 22 months and save roughly $1,840 in interest."),
            ],
        },
        {
            "title": "Budget tips",
            "messages": [
                ("user", "Give me tips to reduce my grocery spending"),
                ("assistant", "Looking at your grocery spending, you average about $280/month across Whole Foods, Trader Joe's, and Costco. Here are some targeted tips:\n\n1. **Shift more shopping to Trader Joe's** - your TJ trips average $48 vs $67 at Whole Foods\n2. **Costco bulk buys** are great for staples but watch impulse buys\n3. **Meal planning** - your highest-spend weeks correlate with no pattern, suggesting unplanned trips\n4. **Use the Whole Foods app** for Prime member discounts\n\nA realistic target would be $220/month, saving you ~$720/year."),
            ],
        },
    ],
    # User 1 (Maria)
    [
        {
            "title": "Subscription audit",
            "messages": [
                ("user", "Can you list all my recurring subscriptions?"),
                ("assistant", "Here are your active subscriptions I found in your expenses:\n\n1. Netflix - $15.99/mo\n2. Spotify Premium - $10.99/mo\n3. iCloud Storage - $2.99/mo\n4. YouTube Premium - $13.99/mo\n\n**Total: $43.96/month ($527.52/year)**\n\nWould you like me to flag any that seem underused or suggest alternatives?"),
                ("user", "That seems like a lot. Which should I cancel?"),
                ("assistant", "Great question! Here's my analysis:\n\n- **Keep:** Spotify ($10.99) - you use it daily based on transaction frequency\n- **Keep:** iCloud ($2.99) - too cheap to matter, useful for backups\n- **Consider canceling:** YouTube Premium ($13.99) - you could use the free tier with ads\n- **Review:** Netflix ($15.99) - consider switching to the ad-supported plan at $6.99\n\nPotential savings: **$22.99/month ($275.88/year)** if you drop YouTube Premium and downgrade Netflix."),
            ],
        },
        {
            "title": "Saving for vacation",
            "messages": [
                ("user", "I want to save $3000 for a vacation in 6 months. Is that realistic?"),
                ("assistant", "That's $500/month you'd need to set aside. Looking at your current spending patterns, your average monthly expenses are around $3,400. With your income considered, here's a plan:\n\n1. **Reduce dining out** from ~$250 to $150/month = $100 saved\n2. **Cut subscriptions** per our earlier chat = $23 saved\n3. **Fewer Amazon impulse buys** (you average $180/mo) = $80 saved\n4. **Skip 2 Uber rides/week** for transit = $60 saved\n5. **Remaining gap:** ~$237 from other areas\n\nIt's tight but doable with discipline. Want me to set up budget alerts for these categories?"),
            ],
        },
    ],
    # User 2 (Reviewer)
    [
        {
            "title": "Tax deductions review",
            "messages": [
                ("user", "Which of my expenses might be tax deductible?"),
                ("assistant", "Based on your expense history, here are potential deductions:\n\n1. **Home office** - if you work remotely, a portion of your internet ($75/mo) and electric bills may qualify\n2. **Student loan interest** - your Sallie Mae payments include interest that's deductible up to $2,500/year\n3. **Health expenses** - gym, pharmacy, and doctor visits totaling ~$135/month if they exceed 7.5% of AGI\n\nI'd recommend tagging relevant expenses as 'tax-deductible' in the app. Would you like me to flag them automatically?"),
            ],
        },
        {
            "title": "Spending trends",
            "messages": [
                ("user", "What are my top 3 spending categories this quarter?"),
                ("assistant", "Here's your top 3 for this quarter:\n\n1. **Bills** - $4,230 (rent, utilities, phone, internet)\n2. **Groceries** - $890 (mostly Whole Foods and Costco)\n3. **Shopping** - $645 (Amazon and Target)\n\nBills dominate at 55% of total spending, which is typical. Your grocery spending is actually below the national average for your area. Shopping has been trending up - last quarter it was $480. Want me to break down the shopping increase?"),
                ("user", "Yes, break down the shopping increase"),
                ("assistant", "The $165 increase in shopping breaks down as:\n\n- **Amazon:** Up $95 (from $310 to $405) - mainly electronics and household items\n- **Target:** Up $45 (from $120 to $165) - more frequent visits (5 vs 3 last quarter)\n- **Best Buy:** $25 new purchase not present last quarter\n\nThe Amazon increase coincides with a new electronics purchase ($189) in February. Without that one-off, your shopping would have been roughly flat. No cause for concern unless this becomes a pattern."),
            ],
        },
    ],
]

# Per-user auto-label rules (keyword, category_name, assign_hidden, priority)
AUTO_LABEL_RULES = [
    # User 0 (Armando)
    [
        ("starbucks", "Coffee", False, 90),
        ("uber", "Transport", False, 90),
        ("whole foods", "Groceries", False, 80),
        ("netflix", "Subscriptions", False, 100),
        ("chipotle", "Dining", False, 85),
    ],
    # User 1 (Maria)
    [
        ("starbucks", "Coffee", False, 90),
        ("trader joe", "Groceries", False, 85),
        ("amazon", "Shopping", False, 80),
        ("spotify", "Subscriptions", False, 100),
    ],
    # User 2 (Reviewer)
    [
        ("costco", "Groceries", False, 85),
        ("uber", "Transport", False, 90),
        ("target", "Shopping", False, 80),
        ("netflix", "Subscriptions", False, 100),
        ("shell", "Transport", False, 85),
    ],
]


# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

def rand_date_in_last_n_days(n: int) -> date:
    """Return a random date within the last *n* days (inclusive of today)."""
    delta = random.randint(0, n)
    return TODAY - timedelta(days=delta)


def rand_time() -> time:
    """Return a random time of day biased toward waking hours."""
    hour = random.choices(range(24), weights=[1]*6 + [3]*2 + [5]*4 + [8]*4 + [5]*4 + [3]*2 + [1]*2, k=1)[0]
    minute = random.randint(0, 59)
    return time(hour, minute)


def rand_amount(lo: float, hi: float) -> float:
    """Return a random dollar amount rounded to 2 decimals."""
    if lo == hi:
        return round(lo, 2)
    return round(random.uniform(lo, hi), 2)


def past_datetime(days_ago: int) -> datetime:
    """Return a timezone-aware datetime *days_ago* days in the past."""
    return datetime.now(timezone.utc) - timedelta(days=days_ago)


# ---------------------------------------------------------------------------
# Seed functions
# ---------------------------------------------------------------------------

async def create_user(session: AsyncSession, account: dict) -> User:
    """Create a user if not already present; return the User object."""
    result = await session.execute(
        select(User).where(User.email == account["email"])
    )
    existing = result.scalar_one_or_none()
    if existing:
        print(f"  [skip] User {account['email']} already exists (id={existing.id})")
        return existing

    user = User(
        id=uuid.uuid4(),
        email=account["email"],
        hashed_password=PASSWORD_HASH,
        display_name=account["display_name"],
        is_superuser=account.get("is_superuser", False),
        is_active=True,
        currency="USD",
        timezone="America/New_York",
    )
    session.add(user)
    await session.flush()
    print(f"  [created] User {account['email']} (id={user.id})")
    return user


async def create_categories(
    session: AsyncSession, user: User, user_index: int
) -> dict[str, uuid.UUID]:
    """Create default + custom categories. Returns {name: id} map."""
    cat_map: dict[str, uuid.UUID] = {}

    all_cats = list(DEFAULT_CATEGORIES) + CUSTOM_CATEGORIES.get(user_index, [])

    for sort_order, (name, icon, color) in enumerate(all_cats):
        result = await session.execute(
            select(Category).where(
                Category.user_id == user.id, Category.name == name
            )
        )
        existing = result.scalar_one_or_none()
        if existing:
            cat_map[name] = existing.id
            continue

        cat_id = uuid.uuid4()
        budget = None
        if name == "Groceries":
            budget = 400.0
        elif name == "Dining":
            budget = 300.0
        elif name == "Coffee":
            budget = 60.0

        cat = Category(
            id=cat_id,
            user_id=user.id,
            name=name,
            icon=icon,
            color=color,
            sort_order=sort_order,
            is_active=True,
            is_hidden=False,
            monthly_budget=budget,
        )
        session.add(cat)
        cat_map[name] = cat_id

    await session.flush()
    print(f"  [categories] {len(cat_map)} categories for {user.email}")
    return cat_map


async def create_expenses(
    session: AsyncSession,
    user: User,
    cat_map: dict[str, uuid.UUID],
    count_range: tuple[int, int] = (50, 80),
) -> list[uuid.UUID]:
    """Create realistic expenses spread across the last 90 days."""
    expense_count = random.randint(*count_range)
    expense_ids: list[uuid.UUID] = []

    # Build a weighted pool of (category_name, template) pairs
    pool: list[tuple[str, tuple[str, str, float, float]]] = []
    weights: list[int] = []
    category_weights = {
        "Groceries": 12, "Transport": 10, "Coffee": 14, "Dining": 10,
        "Subscriptions": 4, "Shopping": 6, "Bills": 5, "Health": 4,
        "Entertainment": 5,
    }
    for cat_name, templates in EXPENSE_TEMPLATES.items():
        if cat_name in cat_map:
            for tpl in templates:
                pool.append((cat_name, tpl))
                weights.append(category_weights.get(cat_name, 5))

    if not pool:
        print(f"  [warn] No expense templates matched categories for {user.email}")
        return expense_ids

    for _ in range(expense_count):
        cat_name, (desc, merchant, lo, hi) = random.choices(pool, weights=weights, k=1)[0]
        amount = rand_amount(lo, hi)

        # Bills are monthly - place them on the 1st of each of the last 3 months
        if cat_name == "Bills" and lo >= 1000:
            # Rent-like: one per month
            month_offset = random.randint(0, 2)
            exp_date = (TODAY.replace(day=1) - timedelta(days=30 * month_offset)).replace(day=1)
        else:
            exp_date = rand_date_in_last_n_days(90)

        exp_id = uuid.uuid4()
        is_recurring = cat_name in ("Subscriptions", "Bills")
        tags = None
        if cat_name == "Subscriptions":
            tags = ["subscription", "recurring"]
        elif cat_name == "Bills":
            tags = ["bill", "recurring"]

        expense = Expense(
            id=exp_id,
            user_id=user.id,
            category_id=cat_map.get(cat_name),
            amount=amount,
            tax_amount=round(amount * 0.08, 2) if cat_name in ("Dining", "Shopping") else 0,
            currency="USD",
            description=desc,
            merchant_name=merchant,
            expense_date=exp_date,
            expense_time=rand_time(),
            is_recurring=is_recurring,
            tags=tags,
        )
        session.add(expense)
        expense_ids.append(exp_id)

    await session.flush()
    print(f"  [expenses] {expense_count} expenses for {user.email}")
    return expense_ids


async def create_credit_cards(
    session: AsyncSession, user: User, user_index: int
) -> list[uuid.UUID]:
    """Create credit cards and return their IDs."""
    card_ids: list[uuid.UUID] = []
    for card_def in CREDIT_CARDS_PER_USER[user_index]:
        card_id = uuid.uuid4()
        card = CreditCard(id=card_id, user_id=user.id, **card_def)
        session.add(card)
        card_ids.append(card_id)
    await session.flush()
    print(f"  [credit_cards] {len(card_ids)} cards for {user.email}")
    return card_ids


async def create_loans(
    session: AsyncSession, user: User, user_index: int
) -> list[uuid.UUID]:
    """Create loans and return their IDs."""
    loan_ids: list[uuid.UUID] = []
    for loan_def in LOANS_PER_USER[user_index]:
        loan_id = uuid.uuid4()
        loan = Loan(id=loan_id, user_id=user.id, **loan_def)
        session.add(loan)
        loan_ids.append(loan_id)
    await session.flush()
    print(f"  [loans] {len(loan_ids)} loans for {user.email}")
    return loan_ids


async def create_debt_payments(
    session: AsyncSession,
    user: User,
    card_ids: list[uuid.UUID],
    loan_ids: list[uuid.UUID],
) -> None:
    """Create 5-10 debt payments spread across the last 3 months."""
    payment_count = random.randint(5, 10)
    created = 0

    all_debts: list[tuple[str, uuid.UUID]] = []
    for cid in card_ids:
        all_debts.append(("credit_card", cid))
    for lid in loan_ids:
        all_debts.append(("loan", lid))

    if not all_debts:
        return

    for _ in range(payment_count):
        debt_type, debt_id = random.choice(all_debts)

        if debt_type == "credit_card":
            amount = rand_amount(50, 500)
            interest = round(amount * random.uniform(0.15, 0.30), 2)
        else:
            amount = rand_amount(200, 600)
            interest = round(amount * random.uniform(0.03, 0.08), 2)

        principal = round(amount - interest, 2)
        payment_date = rand_date_in_last_n_days(90)

        payment = DebtPayment(
            id=uuid.uuid4(),
            user_id=user.id,
            debt_type=debt_type,
            debt_id=debt_id,
            amount=amount,
            principal_portion=principal,
            interest_portion=interest,
            payment_date=payment_date,
            is_snowflake=random.random() < 0.2,
            notes="Extra payment" if random.random() < 0.2 else None,
        )
        session.add(payment)
        created += 1

    await session.flush()
    print(f"  [debt_payments] {created} payments for {user.email}")


async def create_chat_conversations(
    session: AsyncSession, user: User, user_index: int
) -> None:
    """Create pre-written chat conversations with messages."""
    convos = CHAT_CONVERSATIONS[user_index]
    for convo_def in convos:
        convo_id = uuid.uuid4()
        days_ago = random.randint(1, 60)
        convo = ChatConversation(
            id=convo_id,
            user_id=user.id,
            title=convo_def["title"],
        )
        session.add(convo)
        await session.flush()

        for msg_idx, (role, content) in enumerate(convo_def["messages"]):
            msg = ChatMessage(
                id=uuid.uuid4(),
                conversation_id=convo_id,
                role=role,
                content=content,
                model_used="claude-3-haiku-20240307" if role == "assistant" else None,
                tokens_used=random.randint(150, 800) if role == "assistant" else None,
            )
            session.add(msg)

    await session.flush()
    print(f"  [chat] {len(convos)} conversations for {user.email}")


async def create_auto_label_rules(
    session: AsyncSession,
    user: User,
    user_index: int,
    cat_map: dict[str, uuid.UUID],
) -> None:
    """Create auto-label rules mapping keywords to categories."""
    rules = AUTO_LABEL_RULES[user_index]
    created = 0
    for keyword, cat_name, assign_hidden, priority in rules:
        cat_id = cat_map.get(cat_name)
        if not cat_id:
            continue

        # Check uniqueness constraint (user_id, keyword)
        result = await session.execute(
            select(AutoLabelRule).where(
                AutoLabelRule.user_id == user.id,
                AutoLabelRule.keyword == keyword,
            )
        )
        if result.scalar_one_or_none():
            continue

        rule = AutoLabelRule(
            id=uuid.uuid4(),
            user_id=user.id,
            keyword=keyword,
            category_id=cat_id,
            assign_hidden=assign_hidden,
            priority=priority,
        )
        session.add(rule)
        created += 1

    await session.flush()
    print(f"  [auto_label] {created} rules for {user.email}")


# ---------------------------------------------------------------------------
# Armando-only extras
# ---------------------------------------------------------------------------

async def create_feature_flags(session: AsyncSession, user: User) -> None:
    """Enable feature flags for the Armando account."""
    flags = ["friend_debt_calculator", "hidden_categories"]
    for flag_name in flags:
        result = await session.execute(
            select(UserFeatureFlag).where(
                UserFeatureFlag.user_id == user.id,
                UserFeatureFlag.feature_name == flag_name,
            )
        )
        if result.scalar_one_or_none():
            continue

        flag = UserFeatureFlag(
            id=uuid.uuid4(),
            user_id=user.id,
            feature_name=flag_name,
            is_enabled=True,
            enabled_by=user.id,
            enabled_at=datetime.now(timezone.utc),
        )
        session.add(flag)

    await session.flush()
    print(f"  [feature_flags] Enabled {len(flags)} flags for {user.email}")


async def create_friend_debts(session: AsyncSession, user: User) -> None:
    """Create friend deposit/withdrawal records for Armando."""
    deposits = [
        {
            "friend_name": "Carlos",
            "amount": 500.0,
            "transaction_type": "deposit",
            "description": "Loan for apartment deposit",
            "transaction_date": TODAY - timedelta(days=45),
        },
        {
            "friend_name": "Carlos",
            "amount": 200.0,
            "transaction_type": "withdrawal",
            "description": "Partial repayment - dinner",
            "transaction_date": TODAY - timedelta(days=20),
        },
        {
            "friend_name": "Carlos",
            "amount": 75.0,
            "transaction_type": "withdrawal",
            "description": "Venmo repayment",
            "transaction_date": TODAY - timedelta(days=5),
        },
        {
            "friend_name": "Sofia",
            "amount": 150.0,
            "transaction_type": "deposit",
            "description": "Concert tickets fronted",
            "transaction_date": TODAY - timedelta(days=30),
        },
    ]
    for dep_def in deposits:
        dep = FriendDeposit(
            id=uuid.uuid4(),
            user_id=user.id,
            **dep_def,
        )
        session.add(dep)

    await session.flush()
    print(f"  [friend_debts] {len(deposits)} transactions for {user.email}")


async def create_external_accounts(session: AsyncSession, user: User) -> None:
    """Create external account records for Armando."""
    accounts = [
        {"account_name": "Venmo", "current_balance": 350.0},
        {"account_name": "Savings Account (Ally)", "current_balance": 2000.0},
    ]
    for acct_def in accounts:
        acct = ExternalAccount(
            id=uuid.uuid4(),
            user_id=user.id,
            **acct_def,
        )
        session.add(acct)

    await session.flush()
    print(f"  [external_accounts] {len(accounts)} accounts for {user.email}")


async def create_hidden_category_expenses(
    session: AsyncSession, user: User
) -> None:
    """Create a hidden 'Private' category with a few expenses (Armando only)."""
    result = await session.execute(
        select(Category).where(
            Category.user_id == user.id, Category.name == "Private"
        )
    )
    existing_cat = result.scalar_one_or_none()

    if existing_cat:
        cat_id = existing_cat.id
    else:
        cat_id = uuid.uuid4()
        private_cat = Category(
            id=cat_id,
            user_id=user.id,
            name="Private",
            icon="lock",
            color="#71717A",
            sort_order=99,
            is_active=True,
            is_hidden=True,
            monthly_budget=None,
        )
        session.add(private_cat)
        await session.flush()

    hidden_expenses = [
        ("Birthday gift for Mom", "Nordstrom", 125.0),
        ("Surprise party supplies", "Party City", 78.50),
        ("Engagement ring deposit", "Blue Nile", 950.0),
        ("Anniversary dinner", "Le Bernardin", 245.0),
        ("Weekend getaway booking", "Airbnb", 380.0),
    ]

    for desc, merchant, amount in hidden_expenses:
        expense = Expense(
            id=uuid.uuid4(),
            user_id=user.id,
            category_id=cat_id,
            amount=amount,
            currency="USD",
            description=desc,
            merchant_name=merchant,
            expense_date=rand_date_in_last_n_days(60),
            expense_time=rand_time(),
            tags=["private"],
        )
        session.add(expense)

    await session.flush()
    print(f"  [hidden_expenses] 5 private expenses for {user.email}")


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

async def main() -> None:
    print("=" * 60)
    print("Finance Tracker - Demo Data Seed Script")
    print("=" * 60)
    print(f"Database: {settings.database_url}")
    print()

    engine = create_async_engine(settings.database_url, echo=False)
    async_session_factory = async_sessionmaker(
        engine, class_=AsyncSession, expire_on_commit=False
    )

    async with async_session_factory() as session:
        # Idempotency check
        result = await session.execute(
            select(User).where(User.email == "demo@armando.com")
        )
        if result.scalar_one_or_none():
            print("[idempotent] demo@armando.com already exists.")
            print("To re-seed, delete demo users first, then re-run.")
            print("Checking remaining accounts...")
            print()

            # Still try to create the other accounts if they don't exist
            remaining_new = False
            for acct in DEMO_ACCOUNTS[1:]:
                r = await session.execute(
                    select(User).where(User.email == acct["email"])
                )
                if not r.scalar_one_or_none():
                    remaining_new = True
                    break

            if not remaining_new:
                print("All demo accounts already exist. Nothing to do.")
                await engine.dispose()
                return

        # Seed all 3 accounts
        for idx, account in enumerate(DEMO_ACCOUNTS):
            print(f"\n--- Account {idx + 1}: {account['email']} ---")

            user = await create_user(session, account)
            cat_map = await create_categories(session, user, idx)
            await create_expenses(session, user, cat_map)
            card_ids = await create_credit_cards(session, user, idx)
            loan_ids = await create_loans(session, user, idx)
            await create_debt_payments(session, user, card_ids, loan_ids)
            await create_chat_conversations(session, user, idx)
            await create_auto_label_rules(session, user, idx, cat_map)

            # Armando-only extras
            if account["email"] == "demo@armando.com":
                await create_feature_flags(session, user)
                await create_friend_debts(session, user)
                await create_external_accounts(session, user)
                await create_hidden_category_expenses(session, user)

        await session.commit()
        print("\n" + "=" * 60)
        print("Seed complete! Demo accounts ready:")
        print("  demo@armando.com  / Demo1234!  (superuser)")
        print("  demo@maria.com    / Demo1234!  (standard)")
        print("  demo@reviewer.com / Demo1234!  (standard)")
        print("=" * 60)

    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
