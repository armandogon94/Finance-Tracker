# Expense Tracker with Receipt Scanner + AI Finance Chat
## Smart Expense Logging, Receipt OCR, Spending Analytics & Telegram Bot

---

## PROJECT OVERVIEW

Mobile-first expense tracker designed for daily use by Armando and family members. Core philosophy: **logging an expense should take less than 10 seconds**. Four ways to get data in: manual quick-add, receipt photo scanning with ML extraction, bank statement import (PDF or CSV), and Telegram bot for on-the-go logging. Features an AI Finance Chat tab powered by Claude for spending queries, budget advice, and debt coaching.

**This is a website**, not a native app. It lives at finance.armandointeligencia.com with a login screen. No App Store, no Apple Developer License. It's a responsive web app that works great on iPhone Safari, Android Chrome, and desktop browsers. Users can optionally "Add to Home Screen" on their phone for a native-like shortcut (this is a free browser feature, not an app publication).

**Core Features:**
- Ultra-fast expense logging (amount + category in 2 taps)
- Receipt photo capture with ML-powered data extraction (amount, tax, merchant)
- Bank statement import (PDF and CSV) for bulk transaction ingestion
- Credit card debt tracking with statement import
- Personal loan tracking with payoff projections and strategy recommendations
- Receipt image storage organized by month/year for tax purposes
- Flexible user-defined categories with drag-and-drop reorganization
- Hidden categories (admin-toggle per user) for discreet expense tracking
- Auto-labeling engine for imported transactions (keyword-based, user-reviewable)
- Spending visualizations: daily, weekly, monthly breakdowns
- Multi-user authentication (Armando + Mom + future users) with login screen
- Admin panel to toggle optional features per user (friend debt, hidden categories)
- **AI Finance Chat tab** — Chat interface for spending queries, budget advice, and debt coaching powered by Claude
- **Telegram bot** — Quick expense logging via text, receipt OCR via photo, spending queries
- Responsive web app — works on iPhone, Android, and laptop browsers

**Five Data Input Methods:**
1. **Quick Manual Add** — Open app, type amount, tap category, done. ~5 seconds.
2. **Receipt Scanner** — Snap photo of receipt, ML reads it, confirm & save. ~15 seconds.
3. **Bank Statement Import** — Upload PDF or CSV from your bank, auto-parse all transactions at once. Great for catching up on a month of expenses.
4. **Credit Card Statement Import** — Upload CC statement (PDF/CSV), parse charges, track running balance per card.
5. **Telegram Bot** — Text message "coffee 4.50" or send receipt photo to bot for instant logging, anywhere, anytime.

**Subdomain:** finance.armandointeligencia.com

---

## TECH STACK

**Frontend:**
- Next.js 14+ (TypeScript, App Router)
- TailwindCSS + Shadcn/UI (mobile-first components)
- Recharts (spending visualizations)
- Optional PWA: next-pwa (add-to-homescreen shortcut, offline support)
- Camera: MediaDevices API or `<input type="file" capture="environment">`
- Drag-and-drop: @dnd-kit/core (category reorganization)
- File upload: react-dropzone (bank statement PDF/CSV upload)

**Backend:**
- FastAPI 0.104+ (Python 3.11+)
- SQLAlchemy 2.0 + Alembic (migrations)
- Pydantic v2 (validation)
- Pillow (image compression before storage)
- Receipt OCR: Dual strategy (see Receipt OCR section below)
- PDF parsing: pdfplumber or tabula-py (bank statement table extraction)
- CSV parsing: Python csv + pandas for flexible column mapping

**Database:**
- PostgreSQL 16

**Image Storage:**
- MinIO (self-hosted S3-compatible object storage)
- OR filesystem with structured paths (simpler for v1)

**Authentication:**
- FastAPI-Users library (JWT tokens, registration, password reset)
- OAuth2 with refresh tokens (15-min access, 7-day refresh)

**Optional Encryption:**
- pgcrypto for sensitive fields if desired (easy to add later)
- All traffic over HTTPS (Traefik handles SSL)

---

## RECEIPT OCR STRATEGY

### Recommended: Dual-Mode Approach

**Mode 1 — Claude Vision API (Primary, for accuracy)**
Best accuracy for receipts. Cost: ~$0.003-0.004 per receipt using Haiku model.
At 100 receipts/month = ~$0.40/month (negligible).

```python
# Receipt extraction via Claude API
import anthropic

client = anthropic.Anthropic()

def extract_receipt_data(image_base64: str) -> dict:
    message = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=1024,
        messages=[{
            "role": "user",
            "content": [
                {
                    "type": "image",
                    "source": {
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": image_base64
                    }
                },
                {
                    "type": "text",
                    "text": """Extract from this receipt:
                    - merchant_name (store name)
                    - date (YYYY-MM-DD format)
                    - subtotal (number)
                    - tax (number)
                    - total (number)
                    - currency (USD, MXN, etc.)
                    - items (array of {description, quantity, price})
                    Return ONLY valid JSON, no explanation."""
                }
            ]
        }]
    )
    return json.loads(message.content[0].text)
```

**Mode 2 — Tesseract/PaddleOCR (Fallback, fully offline)**
For when API is unavailable or user prefers offline processing.
Tesseract runs on CPU with minimal RAM. PaddleOCR is more accurate but slower.

```python
# Offline fallback with Tesseract
import pytesseract
from PIL import Image
import re

def extract_receipt_offline(image_path: str) -> dict:
    img = Image.open(image_path)
    text = pytesseract.image_to_string(img)

    # Regex patterns for common receipt fields
    total_pattern = r'(?:TOTAL|Total|AMOUNT)\s*[\$]?\s*([\d,]+\.?\d*)'
    tax_pattern = r'(?:TAX|Tax|IVA|Impuesto)\s*[\$]?\s*([\d,]+\.?\d*)'
    date_pattern = r'(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})'

    total = re.search(total_pattern, text)
    tax = re.search(tax_pattern, text)
    date = re.search(date_pattern, text)

    return {
        "raw_text": text,
        "total": float(total.group(1).replace(',', '')) if total else None,
        "tax": float(tax.group(1).replace(',', '')) if tax else None,
        "date": date.group(1) if date else None,
        "confidence": "low",  # User should verify
        "needs_review": True
    }
```

### OCR Configuration in App Settings
User can choose in Settings:
- **Auto (recommended):** Try Claude API first, fall back to Tesseract
- **Cloud only:** Always use Claude API
- **Offline only:** Always use Tesseract (no API costs)
- **Manual only:** Skip OCR, just store receipt image

---

## BANK STATEMENT IMPORT

### Supported Formats

**CSV Import:**
Most banks allow downloading transaction history as CSV. Column layouts vary by bank, so the importer uses a flexible mapping approach.

```python
import csv
import pandas as pd
from io import StringIO
from datetime import datetime

# Common bank CSV column patterns
BANK_COLUMN_MAPS = {
    "chase": {"date": "Posting Date", "description": "Description", "amount": "Amount", "type": "Type"},
    "bofa": {"date": "Date", "description": "Payee", "amount": "Amount", "type": "Type"},
    "wells_fargo": {"date": "Date", "description": "Description", "amount": "Amount"},
    "generic": {"date": 0, "description": 1, "amount": 2},  # column index fallback
}

async def import_csv_transactions(
    user_id: str,
    csv_content: str,
    bank_preset: str = "auto"
) -> dict:
    """
    Import transactions from bank CSV.
    Auto-detect bank format or use manual column mapping.
    """
    df = pd.read_csv(StringIO(csv_content))

    if bank_preset == "auto":
        bank_preset = detect_bank_format(df.columns.tolist())

    col_map = BANK_COLUMN_MAPS.get(bank_preset, BANK_COLUMN_MAPS["generic"])
    transactions = []

    for _, row in df.iterrows():
        amount = parse_amount(str(row[col_map["amount"]]))
        transactions.append({
            "date": parse_date(str(row[col_map["date"]])),
            "description": str(row[col_map["description"]]),
            "amount": abs(amount),
            "is_expense": amount < 0,
            "needs_categorization": True,  # User reviews categories after import
        })

    return {"parsed": len(transactions), "transactions": transactions}
```

**PDF Import (Bank Statements):**
Bank statements downloaded as PDFs contain transaction tables. Use Claude Vision API (same as receipt scanning) or pdfplumber for table extraction.

```python
import pdfplumber

async def import_pdf_statement(pdf_bytes: bytes) -> dict:
    """
    Extract transactions from bank statement PDF.
    Strategy: try pdfplumber table extraction first, fall back to Claude Vision.
    """
    transactions = []

    with pdfplumber.open(io.BytesIO(pdf_bytes)) as pdf:
        for page in pdf.pages:
            tables = page.extract_tables()
            for table in tables:
                for row in table[1:]:  # skip header
                    parsed = parse_statement_row(row)
                    if parsed:
                        transactions.append(parsed)

    # If pdfplumber finds no tables (scanned PDF), fall back to Claude Vision
    if not transactions:
        return await extract_pdf_with_claude_vision(pdf_bytes)

    return {"parsed": len(transactions), "transactions": transactions}


async def extract_pdf_with_claude_vision(pdf_bytes: bytes) -> dict:
    """
    For scanned/image-based PDFs, convert pages to images
    and use Claude Vision API to extract transaction tables.
    """
    # Convert PDF pages to images using pdf2image
    from pdf2image import convert_from_bytes
    images = convert_from_bytes(pdf_bytes, dpi=200)

    all_transactions = []
    for img in images:
        # Convert to base64 and send to Claude
        result = await extract_statement_page(image_to_base64(img))
        all_transactions.extend(result.get("transactions", []))

    return {"parsed": len(all_transactions), "transactions": all_transactions}
```

### Import UI Flow

1. User clicks "Import Statement" on Expenses page
2. Drag-and-drop or file picker for PDF/CSV
3. App detects format and parses transactions
4. **Review screen**: table of parsed transactions, each row has:
   - Date | Description | Amount | Category (dropdown) | Include? (checkbox)
   - Auto-suggested categories based on description keywords
5. User reviews, adjusts categories, unchecks duplicates
6. "Import Selected" button creates all expenses at once
7. Summary: "Imported 47 transactions from March 2026 statement"

### Duplicate Detection

When importing, check for existing expenses with same date + amount + similar description to avoid double-counting:

```python
async def find_potential_duplicates(user_id, transactions):
    """Flag transactions that might already exist in the database."""
    for tx in transactions:
        existing = await db.execute(
            select(Expense).where(
                Expense.user_id == user_id,
                Expense.expense_date == tx["date"],
                Expense.amount == tx["amount"],
            )
        )
        if existing.scalar():
            tx["possible_duplicate"] = True
    return transactions
```

---

## CREDIT CARD & LOAN DEBT TRACKING

### Credit Card Tracking

Users can add their credit cards and track balances over time. Credit card statements can be imported (same PDF/CSV pipeline as bank statements) to pull in charges automatically.

**Per credit card, the app tracks:**
- Card name / last 4 digits (for display)
- Current balance
- Credit limit (for utilization percentage)
- APR (annual percentage rate) — stored as yearly, displayed as monthly equivalent
- Minimum payment amount
- Statement due date (day of month)
- Payment history (how much paid each month)

```python
# Credit card payoff projection
def calculate_cc_payoff(balance: float, apr: float, monthly_payment: float) -> dict:
    """
    Calculate how long to pay off a credit card at a given monthly payment.
    Returns months to payoff, total interest paid.
    """
    monthly_rate = apr / 12
    if monthly_payment <= balance * monthly_rate:
        return {"payoff_months": float('inf'), "total_interest": float('inf'),
                "warning": "Payment doesn't cover interest — balance will grow!"}

    months = 0
    total_interest = 0.0
    remaining = balance

    while remaining > 0:
        interest = remaining * monthly_rate
        total_interest += interest
        remaining = remaining + interest - monthly_payment
        months += 1
        if remaining < 0:
            remaining = 0

    return {"payoff_months": months, "total_interest": round(total_interest, 2),
            "payoff_date": (datetime.now() + timedelta(days=months * 30)).strftime("%B %Y")}
```

### Personal Loan Tracking

Users can add personal loans (car, student, personal, mortgage) and track payoff progress. Two ways to update a loan:

1. **Manual balance update** — User enters current balance directly (e.g., after checking lender's site)
2. **Log a payment** — User tells the app "I just paid $500 toward this loan" and the app deducts it from the balance, accounting for how much went to interest vs. principal

**Per loan, the app tracks:**
- Loan name / lender
- Original principal amount
- Current balance
- Interest rate (monthly or yearly — user specifies, app converts internally to monthly)
- Minimum monthly payment
- Payment due date (day of month)
- Loan type (car, student, personal, mortgage, other)
- Payment history log

```python
# Loan payoff timeline with amortization
def calculate_loan_payoff(
    balance: float,
    annual_rate: float,
    monthly_payment: float,
    extra_payment: float = 0
) -> dict:
    """
    Amortization schedule for a loan.
    Shows month-by-month breakdown of principal vs interest.
    """
    monthly_rate = annual_rate / 12
    schedule = []
    remaining = balance
    month = 0

    while remaining > 0.01:
        month += 1
        interest = remaining * monthly_rate
        payment = min(monthly_payment + extra_payment, remaining + interest)
        principal = payment - interest
        remaining -= principal

        schedule.append({
            "month": month,
            "payment": round(payment, 2),
            "principal": round(principal, 2),
            "interest": round(interest, 2),
            "remaining": round(max(remaining, 0), 2),
        })

    return {
        "total_months": month,
        "total_interest": round(sum(s["interest"] for s in schedule), 2),
        "payoff_date": (datetime.now() + timedelta(days=month * 30)).strftime("%B %Y"),
        "schedule": schedule,  # Full amortization table
    }
```

### Debt Payoff Strategy Recommendations

When a user has multiple debts (credit cards + loans), the app recommends which to pay first using four strategies. The user specifies a total monthly budget for debt payments; the app allocates minimum payments to all debts and then distributes the remaining "extra" money according to each strategy.

**Strategy 1 — Avalanche (Lowest total cost)**
Pay minimums on everything, throw all extra money at the highest-interest debt first. Mathematically optimal — minimizes total interest paid.

**Strategy 2 — Snowball (Fastest psychological wins)**
Pay minimums on everything, throw all extra money at the smallest-balance debt first. You eliminate individual debts faster, which builds motivation.

**Strategy 3 — Hybrid (Balance of both)**
Start with Snowball for the first 1-2 small debts to get quick wins, then switch to Avalanche for the rest. Combines psychological momentum with mathematical efficiency.

**Strategy 4 — Snowflake (Micro-payments from windfalls)**
On top of whichever base strategy (Avalanche or Snowball), the user logs small windfalls (tax refund, cashback, found money, side gig income) as lump-sum payments toward a chosen debt. The app tracks these "snowflake" contributions separately.

```python
# Multi-debt payoff comparison engine
def compare_payoff_strategies(
    debts: list[dict],      # [{name, balance, apr, min_payment}, ...]
    monthly_budget: float    # Total available for all debt payments combined
) -> dict:
    """
    Run all strategies and compare total interest + timeline.
    Returns side-by-side comparison for the user.
    """
    extra = monthly_budget - sum(d["min_payment"] for d in debts)
    if extra <= 0:
        return {"error": "Budget doesn't cover minimum payments",
                "shortfall": sum(d["min_payment"] for d in debts) - monthly_budget}

    # Avalanche: sort by APR descending
    avalanche = simulate_payoff(sorted(debts, key=lambda d: -d["apr"]), extra)

    # Snowball: sort by balance ascending
    snowball = simulate_payoff(sorted(debts, key=lambda d: d["balance"]), extra)

    # Hybrid: first debt by smallest balance, rest by highest APR
    hybrid_order = hybrid_sort(debts)
    hybrid = simulate_payoff(hybrid_order, extra)

    return {
        "avalanche": avalanche,   # {total_months, total_interest, order_eliminated}
        "snowball": snowball,
        "hybrid": hybrid,
        "recommendation": pick_best(avalanche, snowball, hybrid),
        "savings_vs_minimums": calculate_minimum_only(debts),
    }
```

**Debt Dashboard UI:**
- Card/tile per debt showing: name, balance, APR, minimum payment, utilization (for CCs)
- "Total Debt" summary at top with progress bar
- Strategy comparison panel: side-by-side table showing months-to-payoff and total interest for each strategy
- Amortization chart (line graph showing balance decrease over time per strategy)
- "Next payment priority" callout showing which debt to focus extra money on
- Snowflake log: button to add windfall payments with quick-add

---

## FRIEND DEBT CALCULATOR

> **Admin-toggle feature.** This feature is only visible to users for whom the system admin has enabled it. It will NOT appear in the menu or UI for users who don't have the flag turned on.

This is a specialized calculator for Armando's specific situation: a friend deposits her salary into Armando's bank account (using it as a "piggy bank"), and Armando's own spending occasionally dips into those funds, creating a debt.

**How it works:**

1. **Friend's accumulated total** — Track each salary deposit the friend makes. The app maintains a running total of all deposits minus all withdrawals the friend has made.
2. **Current bank balance** — Armando enters (or the app reads from bank import) the current balance of the bank account where the friend's money sits.
3. **External accounts** — Armando can register other accounts he has access to (savings, secondary accounts) with their balances. These represent money he could pull from to repay the friend if she asked for all her money back.
4. **The calculation:**
   ```
   Amount owed = Friend's accumulated total - Current bank balance
   Safety net  = External accounts total
   True shortfall = Amount owed - Safety net (if positive, Armando is short)
   ```
5. **If amount owed is negative** (bank balance > friend's total), Armando is in the clear.

```python
# Friend debt calculation
def calculate_friend_debt(
    friend_total_deposits: float,     # Sum of all salary deposits
    friend_total_withdrawals: float,  # Sum of all money friend has taken out
    current_bank_balance: float,      # Current balance in the shared account
    external_accounts: list[dict],    # [{name, balance}, ...]
) -> dict:
    friend_balance = friend_total_deposits - friend_total_withdrawals
    amount_owed = friend_balance - current_bank_balance
    external_total = sum(a["balance"] for a in external_accounts)

    return {
        "friend_accumulated": round(friend_balance, 2),
        "current_bank_balance": round(current_bank_balance, 2),
        "amount_owed": round(max(amount_owed, 0), 2),
        "external_safety_net": round(external_total, 2),
        "true_shortfall": round(max(amount_owed - external_total, 0), 2),
        "status": "clear" if amount_owed <= 0 else ("covered" if amount_owed <= external_total else "shortfall"),
    }
```

**Friend Debt UI:**
- Simple, clean screen — NOT visible from main nav unless admin-enabled
- Top card: "You owe [Friend Name]: $X,XXX" or "You're in the clear!"
- Deposit log: list of friend's salary deposits with dates
- Withdrawal log: list of money friend has taken out
- External accounts: list with editable balances
- "Update Bank Balance" quick-input
- History chart showing the owed amount over time

---

## HIDDEN CATEGORIES

> **Admin-toggle feature.** When enabled for a user by the system admin, the user gets access to hidden categories. When disabled, the feature is completely invisible.

Hidden categories work exactly like regular categories for accounting purposes — expenses in hidden categories count toward all totals, budgets, and analytics. The difference is **visibility**: expenses in hidden categories are not shown on the main dashboard, recent expenses list, or standard analytics views.

**How hidden categories work:**
- Admin enables "hidden categories" for a user via the admin panel
- A new toggle appears when creating/editing a category: "Make this category hidden"
- Hidden categories appear in the category list with a subtle lock/eye icon
- Expenses logged to hidden categories:
  - DO count in "Total Spent" calculations everywhere
  - DO appear in tax exports and full data exports
  - Do NOT appear on the home dashboard's recent transactions
  - Do NOT appear in the main Expenses list by default
  - Do NOT appear in the main Analytics charts by default
- Accessing hidden expenses: a discrete menu item "Private Expenses" (or accessed via a special gesture/PIN) shows a filtered view of only hidden-category expenses
- On the Quick Add screen, hidden categories appear in the category grid with a subtle indicator

**For bank statement / CSV import:** The auto-labeling engine (see below) can assign imported transactions to hidden categories based on keyword rules. For example, a config rule like `{"keyword": "OnlyFans", "category": "Private Entertainment", "hidden": true}` would auto-label matching transactions into a hidden category.

---

## AUTO-LABELING ENGINE

When transactions are imported via bank statement (PDF or CSV), the app automatically suggests a category for each transaction based on keyword matching. Users review and correct labels before finalizing the import.

**How it works:**

1. **Rules table** — Each user has a set of auto-label rules stored in the database: keyword → category mapping
2. **On import** — Each transaction description is checked against the user's rules (case-insensitive substring match)
3. **Confidence levels:**
   - **Exact match** (keyword found in description) → auto-assign category, mark as "auto-labeled"
   - **No match** → leave as "Uncategorized", user must assign manually
4. **Learning** — When a user manually categorizes an imported transaction, the app offers: "Always categorize [keyword] as [category]?" If yes, a new rule is created.
5. **Hidden category rules** — Some rules can target hidden categories. These rules are stored in a config/rules table and are only active for users who have hidden categories enabled.

```python
# Auto-labeling engine
from sqlalchemy import select

async def auto_label_transactions(
    user_id: str,
    transactions: list[dict],
    db: AsyncSession,
) -> list[dict]:
    """
    Apply user's auto-label rules to imported transactions.
    Returns transactions with suggested categories.
    """
    # Fetch user's rules, ordered by priority
    rules = await db.execute(
        select(AutoLabelRule)
        .where(AutoLabelRule.user_id == user_id, AutoLabelRule.is_active == True)
        .order_by(AutoLabelRule.priority)
    )
    rules = rules.scalars().all()

    for tx in transactions:
        desc = tx["description"].lower()
        tx["auto_labeled"] = False
        tx["suggested_category_id"] = None
        tx["is_hidden"] = False

        for rule in rules:
            if rule.keyword.lower() in desc:
                tx["auto_labeled"] = True
                tx["suggested_category_id"] = str(rule.category_id)
                tx["is_hidden"] = rule.assign_hidden
                tx["label_rule_name"] = rule.keyword
                break  # First matching rule wins

    return transactions


async def learn_from_user_correction(
    user_id: str,
    transaction_description: str,
    chosen_category_id: str,
    db: AsyncSession,
) -> dict:
    """
    When user manually categorizes a transaction, offer to create a rule.
    Extract the most distinctive keyword from the description.
    """
    # Simple: use the merchant name or first significant word
    keyword = extract_keyword(transaction_description)

    return {
        "suggested_rule": {
            "keyword": keyword,
            "category_id": chosen_category_id,
            "description_sample": transaction_description,
        },
        "prompt": f'Always categorize "{keyword}" as this category?',
    }
```

**Auto-Label Rules Management UI:**
- Accessible from Settings → "Auto-Label Rules"
- Table: Keyword | Category | Hidden? | Active? | Actions (edit/delete)
- "Add Rule" form: keyword input, category dropdown, hidden toggle
- Bulk import: paste a list of keyword→category mappings
- Test tool: paste a description, see which rule would match

---

## ADMIN PANEL

Separate interface for system administrators (Armando) to manage users and toggle optional features. Accessible at `finance.armandointeligencia.com/admin` — only visible to users with `is_superuser = true`.

**Admin capabilities:**
- **User management:** View all registered users, deactivate/reactivate accounts, reset passwords
- **Feature flags per user:**
  - Toggle "Friend Debt Calculator" on/off per user
  - Toggle "Hidden Categories" on/off per user
  - Future-proof: any new optional feature gets a flag here
- **Global settings:** Default currency, default categories for new users, OCR mode default
- **System stats:** Total users, total expenses logged, storage usage, API call counts
- **Auto-label rule oversight:** View/edit any user's auto-label rules (for setup assistance)

```python
# Feature flag check middleware
from functools import wraps

async def get_user_features(user_id: str, db: AsyncSession) -> dict:
    """Get all feature flags for a user."""
    flags = await db.execute(
        select(UserFeatureFlag).where(UserFeatureFlag.user_id == user_id)
    )
    return {f.feature_name: f.is_enabled for f in flags.scalars().all()}


def require_feature(feature_name: str):
    """Decorator to gate endpoints behind a feature flag."""
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, current_user=None, db=None, **kwargs):
            features = await get_user_features(current_user.id, db)
            if not features.get(feature_name, False):
                raise HTTPException(status_code=403, detail="Feature not enabled for your account")
            return await func(*args, current_user=current_user, db=db, **kwargs)
        return wrapper
    return decorator


# Usage on endpoints:
@router.get("/friend-debt/summary")
@require_feature("friend_debt_calculator")
async def get_friend_debt_summary(current_user=Depends(get_current_user), db=Depends(get_db)):
    ...
```

**Admin Panel UI:**
- Left sidebar: Users | Feature Flags | Settings | Stats
- Users page: table of all users with status, creation date, last login
- Feature Flags page: user selector dropdown → toggle switches for each feature
- Clean, minimal — this is a management tool, not a user-facing feature

---

## DATABASE SCHEMA

```sql
-- Users (managed by FastAPI-Users)
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    hashed_password VARCHAR(255) NOT NULL,
    display_name VARCHAR(100),
    currency VARCHAR(3) DEFAULT 'USD',
    timezone VARCHAR(50) DEFAULT 'America/New_York',
    is_active BOOLEAN DEFAULT true,
    is_superuser BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Expense Categories (user-defined, reorderable)
CREATE TABLE IF NOT EXISTS categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    icon VARCHAR(50) DEFAULT 'receipt',      -- emoji or icon name
    color VARCHAR(7) DEFAULT '#3B82F6',      -- hex color
    sort_order INTEGER DEFAULT 0,            -- drag-and-drop position
    is_active BOOLEAN DEFAULT true,          -- soft delete
    is_hidden BOOLEAN DEFAULT false,         -- hidden category (admin-toggle feature)
    monthly_budget DECIMAL(10,2),            -- optional budget limit
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, name)
);

-- Default categories seeded per user:
-- Food & Dining, Transportation, Shopping, Entertainment,
-- Bills & Utilities, Health, Education, Personal, Other

-- Expenses (the core table)
CREATE TABLE IF NOT EXISTS expenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    category_id UUID REFERENCES categories(id) ON DELETE SET NULL,
    amount DECIMAL(10,2) NOT NULL,
    tax_amount DECIMAL(10,2) DEFAULT 0,
    currency VARCHAR(3) DEFAULT 'USD',
    description VARCHAR(500),
    merchant_name VARCHAR(255),
    expense_date DATE NOT NULL DEFAULT CURRENT_DATE,
    expense_time TIME,
    notes TEXT,
    -- Receipt data
    receipt_image_path VARCHAR(500),          -- MinIO path or filesystem path
    receipt_ocr_data JSONB,                   -- Full OCR extraction result
    ocr_method VARCHAR(20),                   -- 'claude', 'tesseract', 'paddleocr', 'manual'
    ocr_confidence DECIMAL(3,2),              -- 0.00 to 1.00
    -- Metadata
    is_recurring BOOLEAN DEFAULT false,
    tags TEXT[],                               -- flexible tagging
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Recurring Expenses (templates for auto-creation)
CREATE TABLE IF NOT EXISTS recurring_expenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    category_id UUID REFERENCES categories(id),
    amount DECIMAL(10,2) NOT NULL,
    description VARCHAR(500),
    merchant_name VARCHAR(255),
    frequency VARCHAR(20) NOT NULL,           -- 'daily', 'weekly', 'biweekly', 'monthly', 'yearly'
    next_due_date DATE NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Import History (bank statement imports)
CREATE TABLE IF NOT EXISTS import_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source_type VARCHAR(10) NOT NULL,         -- 'csv' or 'pdf'
    bank_preset VARCHAR(50),                  -- 'chase', 'bofa', 'generic', etc.
    original_filename VARCHAR(255),
    transactions_parsed INTEGER DEFAULT 0,
    transactions_imported INTEGER DEFAULT 0,
    import_date TIMESTAMPTZ DEFAULT NOW()
);

-- Receipt Archive (organized for tax season)
CREATE TABLE IF NOT EXISTS receipt_archive (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    expense_id UUID NOT NULL REFERENCES expenses(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    image_path VARCHAR(500) NOT NULL,         -- MinIO: receipts/{user_id}/{year}/{month}/{filename}
    thumbnail_path VARCHAR(500),              -- compressed thumbnail for quick browse
    file_size_bytes INTEGER,
    mime_type VARCHAR(50) DEFAULT 'image/jpeg',
    tax_year INTEGER NOT NULL,                -- 2026, 2027, etc.
    tax_month INTEGER NOT NULL,               -- 1-12
    is_tax_deductible BOOLEAN DEFAULT false,  -- user can flag for tax purposes
    tax_category VARCHAR(100),                -- 'business', 'medical', 'charitable', etc.
    uploaded_at TIMESTAMPTZ DEFAULT NOW()
);

-- Monthly Spending Summary (materialized/cached)
CREATE TABLE IF NOT EXISTS monthly_summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    year INTEGER NOT NULL,
    month INTEGER NOT NULL,
    total_spent DECIMAL(12,2) DEFAULT 0,
    total_tax DECIMAL(12,2) DEFAULT 0,
    category_breakdown JSONB,                 -- {"Food": 450.00, "Transport": 120.00, ...}
    transaction_count INTEGER DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, year, month)
);

-- ═══════════════════════════════════════════════════════════
-- DEBT TRACKING TABLES
-- ═══════════════════════════════════════════════════════════

-- Credit Cards
CREATE TABLE IF NOT EXISTS credit_cards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    card_name VARCHAR(100) NOT NULL,          -- "Chase Sapphire", "Amex Gold"
    last_four VARCHAR(4),                     -- last 4 digits for display
    current_balance DECIMAL(12,2) DEFAULT 0,
    credit_limit DECIMAL(12,2),
    apr DECIMAL(5,4) NOT NULL,                -- annual rate, e.g. 0.2499 = 24.99%
    minimum_payment DECIMAL(10,2),
    statement_day INTEGER,                    -- day of month statement closes (1-31)
    due_day INTEGER,                          -- day of month payment due (1-31)
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Loans (car, student, personal, mortgage, etc.)
CREATE TABLE IF NOT EXISTS loans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    loan_name VARCHAR(100) NOT NULL,          -- "Car Loan - Toyota", "Student Loan"
    lender VARCHAR(100),
    loan_type VARCHAR(30) NOT NULL,           -- 'car', 'student', 'personal', 'mortgage', 'other'
    original_principal DECIMAL(12,2) NOT NULL,
    current_balance DECIMAL(12,2) NOT NULL,
    interest_rate DECIMAL(5,4) NOT NULL,      -- annual rate
    interest_rate_type VARCHAR(10) DEFAULT 'yearly', -- 'yearly' or 'monthly' (converted internally)
    minimum_payment DECIMAL(10,2),
    due_day INTEGER,                          -- day of month
    start_date DATE,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Debt Payments (tracks payments toward credit cards and loans)
CREATE TABLE IF NOT EXISTS debt_payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    debt_type VARCHAR(15) NOT NULL,           -- 'credit_card' or 'loan'
    debt_id UUID NOT NULL,                    -- FK to credit_cards.id or loans.id
    amount DECIMAL(10,2) NOT NULL,
    principal_portion DECIMAL(10,2),          -- how much went to principal
    interest_portion DECIMAL(10,2),           -- how much went to interest
    payment_date DATE NOT NULL DEFAULT CURRENT_DATE,
    is_snowflake BOOLEAN DEFAULT false,       -- windfall/extra payment
    notes VARCHAR(500),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Debt Snapshots (monthly balance history for charts)
CREATE TABLE IF NOT EXISTS debt_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    debt_type VARCHAR(15) NOT NULL,
    debt_id UUID NOT NULL,
    balance DECIMAL(12,2) NOT NULL,
    snapshot_date DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(debt_id, snapshot_date)
);

-- ═══════════════════════════════════════════════════════════
-- FRIEND DEBT CALCULATOR TABLES (admin-toggle feature)
-- ═══════════════════════════════════════════════════════════

-- Friend Deposits (salary deposits into user's account)
CREATE TABLE IF NOT EXISTS friend_deposits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    friend_name VARCHAR(100) NOT NULL,        -- name of the friend
    amount DECIMAL(12,2) NOT NULL,
    transaction_type VARCHAR(15) NOT NULL,     -- 'deposit' or 'withdrawal'
    description VARCHAR(500),
    transaction_date DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- External Accounts (other accounts user has access to for safety net)
CREATE TABLE IF NOT EXISTS external_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    account_name VARCHAR(100) NOT NULL,       -- "Savings - BofA", "Mom's account"
    current_balance DECIMAL(12,2) DEFAULT 0,
    last_updated TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════
-- FEATURE FLAGS & AUTO-LABELING
-- ═══════════════════════════════════════════════════════════

-- User Feature Flags (admin-managed)
CREATE TABLE IF NOT EXISTS user_feature_flags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    feature_name VARCHAR(50) NOT NULL,        -- 'friend_debt_calculator', 'hidden_categories'
    is_enabled BOOLEAN DEFAULT false,
    enabled_by UUID REFERENCES users(id),     -- admin who toggled it
    enabled_at TIMESTAMPTZ,
    UNIQUE(user_id, feature_name)
);

-- Auto-Label Rules (keyword → category mapping for imports)
CREATE TABLE IF NOT EXISTS auto_label_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    keyword VARCHAR(100) NOT NULL,            -- substring to match in transaction description
    category_id UUID NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
    assign_hidden BOOLEAN DEFAULT false,      -- assign to hidden category
    priority INTEGER DEFAULT 100,             -- lower = higher priority (first match wins)
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, keyword)
);

-- Indexes
CREATE INDEX idx_expenses_user_date ON expenses(user_id, expense_date DESC);
CREATE INDEX idx_expenses_category ON expenses(category_id);
CREATE INDEX idx_expenses_merchant ON expenses(merchant_name);
CREATE INDEX idx_categories_user_order ON categories(user_id, sort_order);
CREATE INDEX idx_categories_hidden ON categories(user_id, is_hidden);
CREATE INDEX idx_receipt_archive_tax ON receipt_archive(user_id, tax_year, tax_month);
CREATE INDEX idx_monthly_summaries_user ON monthly_summaries(user_id, year, month);
CREATE INDEX idx_credit_cards_user ON credit_cards(user_id);
CREATE INDEX idx_loans_user ON loans(user_id);
CREATE INDEX idx_debt_payments_debt ON debt_payments(debt_type, debt_id, payment_date);
CREATE INDEX idx_debt_snapshots_debt ON debt_snapshots(debt_id, snapshot_date);
CREATE INDEX idx_friend_deposits_user ON friend_deposits(user_id, transaction_date);
CREATE INDEX idx_feature_flags_user ON user_feature_flags(user_id, feature_name);
CREATE INDEX idx_auto_label_rules_user ON auto_label_rules(user_id, priority);
```

---

## API ENDPOINTS

```python
# ─── AUTH (FastAPI-Users) ───
POST   /api/v1/auth/register          # Create account
POST   /api/v1/auth/login             # Get JWT tokens
POST   /api/v1/auth/refresh           # Refresh access token
POST   /api/v1/auth/forgot-password   # Send reset email
POST   /api/v1/auth/reset-password    # Reset with token
GET    /api/v1/users/me               # Current user profile
PATCH  /api/v1/users/me               # Update profile (name, currency, timezone)

# ─── CATEGORIES ───
GET    /api/v1/categories              # List all (sorted by sort_order)
POST   /api/v1/categories              # Create new
PATCH  /api/v1/categories/{id}         # Update (name, color, icon, budget)
DELETE /api/v1/categories/{id}         # Soft delete (archive)
PUT    /api/v1/categories/reorder      # Bulk update sort_order (drag-and-drop)

# ─── EXPENSES (Core CRUD) ───
GET    /api/v1/expenses                # List with filters:
       # ?start_date=2026-03-01&end_date=2026-03-31
       # ?category_id=uuid
       # ?search=walmart
       # ?min_amount=10&max_amount=100
       # ?page=1&per_page=50
POST   /api/v1/expenses                # Create expense (manual entry)
POST   /api/v1/expenses/quick          # Quick add (amount + category only)
GET    /api/v1/expenses/{id}           # Get one
PATCH  /api/v1/expenses/{id}           # Update
DELETE /api/v1/expenses/{id}           # Delete

# ─── RECEIPT SCANNING ───
POST   /api/v1/receipts/scan           # Upload image → OCR → return extracted data
POST   /api/v1/receipts/confirm        # Confirm extracted data → create expense + archive receipt
GET    /api/v1/receipts/archive        # Browse receipts by year/month
       # ?year=2026&month=3
       # ?tax_deductible=true
GET    /api/v1/receipts/{id}/image     # Serve receipt image

# ─── BANK STATEMENT IMPORT ───
POST   /api/v1/import/upload           # Upload PDF or CSV → parse → return preview
       # Returns: list of parsed transactions with auto-suggested categories
POST   /api/v1/import/confirm          # Confirm selected transactions → bulk create expenses
GET    /api/v1/import/history          # List past imports (date, source, count)
GET    /api/v1/import/templates        # Available bank presets (Chase, BofA, etc.)

# ─── ANALYTICS / DASHBOARD ───
GET    /api/v1/dashboard/today         # Today's total + recent expenses
GET    /api/v1/dashboard/summary       # Current week + month totals
GET    /api/v1/analytics/daily         # Daily spending for date range
GET    /api/v1/analytics/weekly        # Weekly aggregation
GET    /api/v1/analytics/monthly       # Monthly aggregation with YoY comparison
GET    /api/v1/analytics/by-category   # Spending breakdown by category (pie chart data)
GET    /api/v1/analytics/by-merchant   # Top merchants (treemap data)
GET    /api/v1/analytics/trends        # Spending trends over time (line chart data)
GET    /api/v1/analytics/budget-status # Budget vs actual per category

# ─── TAX EXPORT ───
GET    /api/v1/tax/summary/{year}      # Annual tax summary
GET    /api/v1/tax/export/{year}       # Download CSV of all expenses for tax year
GET    /api/v1/tax/receipts/{year}     # Download ZIP of all receipt images for tax year

# ─── RECURRING ───
GET    /api/v1/recurring               # List recurring expenses
POST   /api/v1/recurring               # Create
PATCH  /api/v1/recurring/{id}          # Update
DELETE /api/v1/recurring/{id}          # Delete

# ─── CREDIT CARDS ───
GET    /api/v1/credit-cards            # List all user's credit cards
POST   /api/v1/credit-cards            # Add a credit card
GET    /api/v1/credit-cards/{id}       # Get card details + payment history
PATCH  /api/v1/credit-cards/{id}       # Update balance, APR, limit, etc.
DELETE /api/v1/credit-cards/{id}       # Remove card
POST   /api/v1/credit-cards/{id}/payment  # Log a payment toward this card
GET    /api/v1/credit-cards/{id}/payoff    # Payoff projection (months, interest)
POST   /api/v1/credit-cards/import     # Import CC statement (PDF/CSV) → parse charges

# ─── LOANS ───
GET    /api/v1/loans                   # List all user's loans
POST   /api/v1/loans                   # Add a loan
GET    /api/v1/loans/{id}              # Get loan details + payment history + amortization
PATCH  /api/v1/loans/{id}              # Update balance manually
DELETE /api/v1/loans/{id}              # Remove loan
POST   /api/v1/loans/{id}/payment      # Log a payment toward this loan
GET    /api/v1/loans/{id}/amortization # Full amortization schedule
POST   /api/v1/loans/{id}/snowflake    # Log a windfall/extra payment

# ─── DEBT STRATEGY ───
GET    /api/v1/debt/summary            # Total debt overview (all CCs + loans)
GET    /api/v1/debt/strategies         # Compare payoff strategies
       # ?monthly_budget=500           # How much user can pay total per month
GET    /api/v1/debt/history            # Debt balance over time (for charts)

# ─── FRIEND DEBT (feature-gated) ───
GET    /api/v1/friend-debt/summary     # Current friend debt calculation
POST   /api/v1/friend-debt/deposits    # Log a friend deposit/withdrawal
GET    /api/v1/friend-debt/deposits    # List all deposits/withdrawals
DELETE /api/v1/friend-debt/deposits/{id} # Delete a deposit entry
GET    /api/v1/friend-debt/external-accounts  # List external accounts
POST   /api/v1/friend-debt/external-accounts  # Add external account
PATCH  /api/v1/friend-debt/external-accounts/{id}  # Update balance
DELETE /api/v1/friend-debt/external-accounts/{id}   # Remove

# ─── HIDDEN CATEGORIES (feature-gated) ───
GET    /api/v1/expenses/hidden         # List hidden-category expenses only
GET    /api/v1/analytics/hidden        # Analytics for hidden categories only

# ─── AUTO-LABEL RULES ───
GET    /api/v1/auto-label/rules        # List user's auto-label rules
POST   /api/v1/auto-label/rules        # Create a rule
PATCH  /api/v1/auto-label/rules/{id}   # Update a rule
DELETE /api/v1/auto-label/rules/{id}   # Delete a rule
POST   /api/v1/auto-label/test         # Test a description against rules
POST   /api/v1/auto-label/learn        # Create rule from user correction

# ─── ADMIN PANEL (superuser only) ───
GET    /api/v1/admin/users             # List all users
GET    /api/v1/admin/users/{id}        # User details
PATCH  /api/v1/admin/users/{id}        # Deactivate/reactivate user
POST   /api/v1/admin/users/{id}/reset-password  # Force password reset
GET    /api/v1/admin/users/{id}/features  # Get feature flags for user
PATCH  /api/v1/admin/users/{id}/features  # Toggle feature flags
GET    /api/v1/admin/stats             # System-wide stats
GET    /api/v1/admin/auto-label/rules/{user_id}  # View any user's rules
```

---

## FRONTEND: MOBILE-FIRST UX

### Key Screens

**1. Home / Dashboard (Default Screen)**
- Large "+" floating action button (FAB) for quick expense add
- Today's total prominently displayed
- This week's and this month's totals
- Mini pie chart of top 3 categories this month
- Last 5 recent expenses (swipe to edit/delete)

**2. Quick Add Expense (Modal/Sheet)**
- Opens from FAB button
- Numpad-style amount input (like a calculator)
- Category grid (icons with colors, scrollable)
- Optional: description, merchant, date override
- "Scan Receipt" button → opens camera
- Submit creates expense in < 1 second

**3. Scan Receipt Flow**
- Camera opens with rear-facing mode
- User takes photo → preview shown
- "Analyzing..." loading state
- OCR results shown: amount, tax, merchant, date
- User can edit any field before confirming
- "Confirm & Save" creates expense + archives receipt

**4. Expenses List**
- Grouped by date (Today, Yesterday, This Week, Earlier)
- Each row: category icon | description | amount (right-aligned)
- Search bar at top
- Filter chips: category, date range, amount range
- Swipe left to delete, tap to edit

**5. Analytics**
- Time period tabs: Day | Week | Month | Year
- Spending over time (bar chart for daily, line for weekly/monthly)
- Category breakdown (pie/donut chart)
- Top merchants list
- Budget progress bars per category
- Compare to previous period (↑12% vs last month)

**6. Categories Management**
- List with drag handles for reorder (@dnd-kit)
- Each row: icon | name | monthly budget | edit button
- Add new category: name, pick icon, pick color, optional budget
- Archive (soft delete) unused categories

**7. Bank Statement Import**
- Drag-and-drop zone for PDF/CSV files (react-dropzone)
- Bank preset selector (Chase, BofA, Wells Fargo, Generic)
- Preview table of parsed transactions with category auto-suggestions
- Checkbox per row to include/exclude, duplicate warnings highlighted in yellow
- "Import Selected" button with summary count
- Import history log showing past imports

**8. Receipt Archive**
- Grid view of receipt thumbnails
- Filter by year, month, tax-deductible flag
- Tap to view full image + linked expense
- "Export for Tax" button → downloads ZIP of year's receipts
- Toggle "Tax Deductible" flag per receipt

**9. Settings**
- Profile (name, email, password change)
- Default currency
- OCR preference (Auto/Cloud/Offline/Manual)
- Auto-label rules management (keyword → category mappings)
- Default categories reset
- Data export (CSV download)
- Theme (light/dark/system)

**10. Debt Dashboard**
- Total debt summary card at top (sum of all CCs + loans)
- Credit card tiles: card name, balance, APR, utilization bar, min payment
- Loan tiles: loan name, balance, APR, type badge, progress bar (paid vs. original)
- "Add Credit Card" and "Add Loan" buttons
- Tap any card/loan → detail view with payment history and payoff projection

**11. Debt Payoff Strategies**
- Monthly budget input at top ("How much can you pay toward debt each month?")
- Side-by-side comparison table: Avalanche vs. Snowball vs. Hybrid
  - Each column shows: months to freedom, total interest paid, first debt eliminated
- Line chart: balance over time per strategy (overlaid)
- "Recommended" badge on the best strategy for the user
- "Next Priority" callout: which debt to throw extra money at this month
- Snowflake section: "Log a windfall" quick-add (tax refund, bonus, etc.)

**12. Credit Card / Loan Detail**
- Balance history chart (line over months)
- Payment history list (date, amount, principal vs. interest)
- Payoff projection: "At current payment: paid off by [date], total interest: $X"
- "What if" slider: adjust monthly payment → see how timeline changes
- Import statement button (for credit cards)

**13. Friend Debt Calculator (admin-toggle)**
- NOT in main nav unless feature is enabled for the user
- Top card: debt status with large number and status color (green/yellow/red)
- Deposit/withdrawal log with add button
- External accounts list with editable balances
- Quick "Update Bank Balance" input
- Trend chart: owed amount over time

**14. Hidden Expenses (admin-toggle)**
- Discrete menu item, NOT on main dashboard
- Same list/filter UI as main Expenses but only shows hidden-category expenses
- Category filter only shows hidden categories
- Analytics sub-view for hidden expenses (totals, by category)
- No exports include hidden category names in headers (just "Other" or generic)

**15. Admin Panel (/admin)**
- Only accessible to superusers
- User management table: name, email, status, last login, created date
- Per-user feature flag toggles (friend debt, hidden categories)
- System stats: total users, total expenses, storage used
- Auto-label rule viewer per user

---

## RECEIPT IMAGE STORAGE

### Strategy: Filesystem for v1, MinIO for v2

**v1 (Simple — filesystem):**
```
/data/receipts/
  /{user_id}/
    /2026/
      /03/
        /receipt_abc123.jpg         # full image (compressed to <200KB)
        /receipt_abc123_thumb.jpg   # thumbnail (100x150px, <20KB)
      /04/
        /...
```

PostgreSQL stores the path. Images served via FastAPI static files or Traefik.

**v2 (Scalable — MinIO):**
- MinIO Docker container alongside other services
- S3-compatible API (boto3 Python SDK)
- Bucket: `receipts` with lifecycle policy (move to cold after 2 years)
- Presigned URLs for direct browser upload (skip backend for large files)

### Image Processing Pipeline
```python
from PIL import Image
import io

def process_receipt_image(raw_bytes: bytes) -> tuple[bytes, bytes]:
    """Compress and create thumbnail"""
    img = Image.open(io.BytesIO(raw_bytes))

    # Auto-rotate based on EXIF
    img = ImageOps.exif_transpose(img)

    # Resize if too large (max 1200px on longest side)
    img.thumbnail((1200, 1200), Image.Resampling.LANCZOS)

    # Save compressed full image
    full_buf = io.BytesIO()
    img.save(full_buf, format='JPEG', quality=80, optimize=True)

    # Create thumbnail (200px wide)
    thumb = img.copy()
    thumb.thumbnail((200, 300), Image.Resampling.LANCZOS)
    thumb_buf = io.BytesIO()
    thumb.save(thumb_buf, format='JPEG', quality=70)

    return full_buf.getvalue(), thumb_buf.getvalue()
```

---

## WEB APP CONFIGURATION

> **This is a website, not a native app.** It runs at finance.armandointeligencia.com behind
> Traefik with HTTPS. Users visit the URL in any browser, log in, and use it. The optional
> PWA features below simply allow users to tap "Add to Home Screen" in Safari/Chrome for a
> nice icon shortcut — no App Store, no developer license, no publishing required.

### next-pwa Setup (Optional Enhancement)
```javascript
// next.config.js
const withPWA = require('next-pwa')({
  dest: 'public',
  register: true,
  skipWaiting: true,
  disable: process.env.NODE_ENV === 'development',
});

module.exports = withPWA({
  // ... Next.js config
});
```

### manifest.json
```json
{
  "name": "Expense Tracker",
  "short_name": "Expenses",
  "description": "Track your spending with receipt scanning",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#3B82F6",
  "icons": [
    { "src": "/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icon-512.png", "sizes": "512x512", "type": "image/png" }
  ]
}
```

### Camera Access for Receipt Scanning
```typescript
// Must be served over HTTPS (Traefik handles this in production)
// For local development: use --experimental-https or ngrok

async function captureReceipt(): Promise<Blob> {
  const stream = await navigator.mediaDevices.getUserMedia({
    video: { facingMode: 'environment', width: 1200, height: 1600 }
  });

  const video = document.createElement('video');
  video.srcObject = stream;
  await video.play();

  const canvas = document.createElement('canvas');
  canvas.width = video.videoWidth;
  canvas.height = video.videoHeight;
  canvas.getContext('2d')!.drawImage(video, 0, 0);

  stream.getTracks().forEach(track => track.stop());

  return new Promise(resolve => {
    canvas.toBlob(blob => resolve(blob!), 'image/jpeg', 0.85);
  });
}
```

---

## DOCKER COMPOSE

```yaml
finance-api:
  build:
    context: ./backend
    dockerfile: Dockerfile
  depends_on:
    postgres:
      condition: service_healthy
  environment:
    DATABASE_URL: postgresql+asyncpg://postgres:${DB_PASSWORD}@postgres:5432/finance_db
    ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
    OCR_MODE: auto  # auto, cloud, offline, manual
    RECEIPT_STORAGE_PATH: /data/receipts
    JWT_SECRET: ${JWT_SECRET}
  volumes:
    - receipt_data:/data/receipts
  networks:
    - backend
    - frontend
  deploy:
    resources:
      limits:
        cpus: '0.5'
        memory: 512M
  restart: unless-stopped
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8002/health"]
    interval: 30s
    timeout: 10s
    retries: 3
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.finance-api.rule=Host(`api.finance.armandointeligencia.com`)"
    - "traefik.http.routers.finance-api.entrypoints=websecure"
    - "traefik.http.routers.finance-api.tls.certresolver=letsencrypt"
    - "traefik.http.services.finance-api.loadbalancer.server.port=8002"

finance-web:
  build:
    context: ./frontend
    dockerfile: Dockerfile
  depends_on:
    - finance-api
  environment:
    NEXT_PUBLIC_API_URL: https://api.finance.armandointeligencia.com
  networks:
    - frontend
  deploy:
    resources:
      limits:
        cpus: '0.3'
        memory: 256M
  restart: unless-stopped
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.finance.rule=Host(`finance.armandointeligencia.com`)"
    - "traefik.http.routers.finance.entrypoints=websecure"
    - "traefik.http.routers.finance.tls.certresolver=letsencrypt"
    - "traefik.http.services.finance.loadbalancer.server.port=3000"

volumes:
  receipt_data:
    driver: local
```

---

## ESTIMATED TIMELINE

| Task | Hours |
|------|-------|
| Database schema + migrations (all tables) | 3 |
| Auth system (FastAPI-Users) + admin roles | 2.5 |
| Category CRUD + reorder + hidden flag | 2.5 |
| Expense CRUD + quick-add API | 3 |
| Receipt upload + OCR pipeline | 4 |
| Receipt storage + archive API | 2 |
| Bank statement import (PDF + CSV parser) | 4 |
| Import review UI + duplicate detection | 3 |
| Auto-labeling engine + rules CRUD | 3 |
| Credit card CRUD + statement import + payoff calc | 4 |
| Loan CRUD + payment logging + amortization engine | 4 |
| Debt payoff strategy comparison engine | 3 |
| Friend debt calculator (backend + frontend) | 3 |
| Feature flag system + admin toggle API | 2 |
| Hidden categories logic (filtering, discrete UI) | 2.5 |
| Analytics/dashboard endpoints | 3 |
| Tax export endpoints | 1.5 |
| Frontend: Dashboard + quick add | 4 |
| Frontend: Expense list + filters | 3 |
| Frontend: Receipt scan flow | 3 |
| Frontend: Analytics charts | 3 |
| Frontend: Categories management | 2 |
| Frontend: Receipt archive | 2 |
| Frontend: Debt dashboard + strategy comparison | 4 |
| Frontend: CC/Loan detail + "what if" slider | 3 |
| Frontend: Admin panel (users, flags, stats) | 3 |
| Responsive web optimization | 1.5 |
| Testing (pytest + vitest) | 4 |
| **Subtotal v3** | **~78 hours** |
| | |
| **AI FINANCE CHAT TAB (v4 expansion)** | |
| Database schema (chat_conversations, chat_messages) | 1.5 |
| Chat API endpoints (create, list, send, history) | 3 |
| Claude integration (Haiku/Sonnet toggling, streaming) | 2.5 |
| Financial context builder (queries, formatting) | 2 |
| Suggested prompts logic + backend | 1 |
| Frontend: Chat UI + conversation sidebar | 3.5 |
| Frontend: Message bubbles + streaming display | 2 |
| Frontend: Suggested prompts + settings toggle | 1.5 |
| Testing (chat endpoints + RAG pipeline) | 2 |
| **Subtotal: AI Chat** | **~19 hours** |
| | |
| **TELEGRAM BOT (v4 expansion)** | |
| Database schema (telegram_links) | 1 |
| Telegram bot setup + python-telegram-bot library | 1.5 |
| Quick expense add command (/add) | 1.5 |
| Receipt photo processing (OCR via Claude Vision) | 2 |
| Receipt confirmation flow (inline keyboard UI) | 1.5 |
| Spending query commands (/today, /month, /budget) | 2 |
| Account linking flow (code generation + verification) | 2 |
| Docker service + healthcheck + shared DB connection | 1.5 |
| Testing (bot commands, OCR, linking) | 1.5 |
| **Subtotal: Telegram Bot** | **~15 hours** |
| | |
| **Total (v3 + v4)** | **~112 hours** |

---

## SUGGESTED IMPROVEMENTS BEYOND v1

- **Recurring expense auto-creation:** Cron job creates monthly bills automatically
- **Multi-currency:** Convert expenses in MXN, EUR etc. using live exchange rates
- **Shared expenses:** Split costs between users (Armando pays, mom reimburses half)
- **Budget alerts:** Push notifications when approaching category budget limits
- **Receipt text search:** Full-text search across OCR-extracted receipt text
- **Expense trends prediction:** Simple time-series forecast of next month's spending
- **Debt consolidation calculator:** Compare current debts vs. a single consolidation loan
- **Credit score impact estimator:** Show how payoff strategies affect utilization ratio
- **Plaid integration:** Auto-sync bank balances and transactions (no manual import)
- **Recurring debt auto-pay reminders:** Push notification before CC/loan due dates

---

## VERSION 4.0 EXPANSION: AI FINANCE CHAT + TELEGRAM BOT

### AI FINANCE CHAT TAB

**Overview:**
A new tab in the web app (alongside Dashboard, Expenses, Debt, etc.) that provides a conversational interface to Claude for intelligent financial insights based on the user's actual spending data.

**User Interface:**
- Full chat interface with message bubbles (user messages right-aligned, assistant left-aligned)
- Message input box at the bottom with send button
- Conversation sidebar on the left showing previous chat titles (e.g., "March Budget Review", "Debt Payoff Plan")
- Create new conversation button
- When chat is empty: display 4-6 clickable suggested prompts as cards or chips
- Settings toggle in chat header: "Haiku" / "Sonnet" to switch LLM model
- Conversation history: users can scroll through past messages in a conversation

**Capabilities:**

1. **Spending Queries:**
   - "How much did I spend on groceries last month?"
   - "What's my biggest expense category this year?"
   - "Compare my spending in March vs February"
   - Backend queries expenses table, formats as context, Claude responds with analysis

2. **Budget Advice:**
   - "How can I reduce my monthly expenses?"
   - "Am I on track with my budget this month?"
   - "What categories am I overspending in?"
   - Backend queries budgets, expenses, calculates trends, Claude provides personalized recommendations

3. **Debt Coaching:**
   - "What's the fastest way to pay off my credit cards?"
   - "If I add $200/month to debt payments, how much sooner will I be debt-free?"
   - "Should I pay off my car loan or credit card first?"
   - Backend queries debts table, runs payoff calculations, Claude provides strategic advice

**How It Works (RAG-like Pipeline):**
1. User types message in chat input
2. Message sent to POST /api/v1/chat/conversations/{id}/messages with streaming enabled
3. Backend:
   - Analyzes intent (spending query vs. advice vs. debt coaching)
   - Queries PostgreSQL for relevant financial data (expenses, budgets, debts, monthly totals, trends)
   - Formats data as context JSON (e.g., `{"monthly_spending": {...}, "budget_status": {...}, "debts": {...}}`)
   - Calls Claude API (Haiku by default, or Sonnet if toggled)
   - Includes user's actual data as context in the prompt
   - Streams response back to frontend
4. Frontend receives streamed response and displays it character-by-character for real-time feel
5. Message saved to `chat_messages` table with financial_context_json for audit/analysis

**Suggested Prompts (Empty Chat State):**
- "📊 Monthly spending summary"
- "💳 Debt payoff timeline"
- "🏷️ Top expense categories"
- "📈 Spending trends analysis"
- "💰 Budget status check"
- "🎯 Where can I save money?"

**LLM Model Toggle:**
- Default: Haiku (faster, cheaper, ~99% accurate for most queries)
- User can toggle to Sonnet in chat settings for more complex analysis
- Toggle is per-user setting, stored in users table

**Database Schema:**
```sql
CREATE TABLE chat_conversations (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE chat_messages (
    id SERIAL PRIMARY KEY,
    conversation_id INTEGER NOT NULL REFERENCES chat_conversations(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL, -- 'user' or 'assistant'
    content TEXT NOT NULL,
    financial_context_json JSONB, -- Null for user messages, populated for assistant responses
    model_used VARCHAR(50), -- 'haiku' or 'sonnet'
    tokens_used INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Update users table:
ALTER TABLE users ADD COLUMN preferred_chat_model VARCHAR(50) DEFAULT 'haiku';
```

**API Endpoints:**
```
POST /api/v1/chat/conversations
  - Body: { "title": "Optional title" }
  - Returns: { "id": 123, "user_id": ..., "created_at": ... }

GET /api/v1/chat/conversations
  - Returns: List of conversations for authenticated user, sorted by updated_at DESC

POST /api/v1/chat/conversations/{id}/messages
  - Body: { "content": "user message" }
  - Streaming: Server-Sent Events (SSE) or JSON streaming (newline-delimited)
  - Returns: streamed response from Claude API in real-time

GET /api/v1/chat/conversations/{id}/messages
  - Query params: ?limit=50&offset=0
  - Returns: List of messages in conversation (paginated)

PUT /api/v1/chat/conversations/{id}
  - Body: { "title": "New title" }
  - Returns: Updated conversation
```

**Frontend Implementation:**
- New route: `/chat` in Next.js app
- Use React Query for data fetching (conversations list, message history)
- Use EventSource or native fetch streaming for real-time response display
- Suggested prompts: Show only on empty chat, hide after first message
- Message storage: Optimistic UI (show message immediately, save to DB after success)
- Settings button: Modal to toggle model preference

---

### TELEGRAM BOT

**Overview:**
A separate Telegram bot (@ArmandoFinanceBot or similar) that connects to the same PostgreSQL database, allowing users to log expenses, upload receipt photos, and query spending from Telegram.

**Bot Features:**

**1. Quick Expense Add (Text)**
- User: "coffee 4.50"
- Bot: Creates expense with amount=4.50, asks user to select category (inline keyboard with buttons)
- User: Taps ☕ Coffee
- Bot: "✅ Added: coffee $4.50 to Coffee"
- Supports: "coffee 4.50", "groceries 85.20", "uber 12.45 uber" (amount + optional category description)

**2. Receipt Photo OCR**
- User: Sends photo of receipt
- Bot: "📸 Processing receipt..."
- Bot runs Claude Vision OCR on image (same pipeline as web app)
- Extracts: amount, tax, merchant, items
- Bot replies: "✅ Found: $45.99 (tax: $3.50) from Whole Foods\nCategory?" + inline keyboard (🍔 Groceries, 🥤 Food, ❓ Other)
- User: Taps category
- Bot: "✅ Added receipt. Items: [extracted items list]"

**3. Spending Queries**
- /today — "Today's spending: $52.30 (Coffee, Lunch, Gas)"
- /month — "This month: $1,243.50 across 8 categories"
- /budget — "Budget status: Groceries 65% of $300, Dining 80% of $250, etc."
- /category [name] — "Groceries this month: $245.80"

**4. Account Linking**
- First run: Bot detects no linked account
- Bot: "👋 Hi! Link your Finance Tracker account:\n1. Visit: https://finance.armandointeligencia.com/telegram-link\n2. Copy your code\n3. Send: /verify [code]"
- User clicks link on web app → generates code (e.g., "ABC123DEF")
- User sends: /verify ABC123DEF
- Bot: Validates code from telegram_links table, marks is_active=true
- From now on: All expenses logged via bot are attributed to that user

**Commands:**
```
/add <amount> [description] [category] — Quick add (e.g., /add 5.50 coffee)
/today — Today's expenses summary
/month — Month-to-date summary
/budget — Budget status per category
/category <name> — Spending in specific category
/history — Last 10 expenses
/help — Show all commands
/verify <code> — Link to web account
/unlink — Unlink Telegram account
```

**Database Schema:**
```sql
CREATE TABLE telegram_links (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    telegram_user_id BIGINT NOT NULL UNIQUE,
    telegram_username VARCHAR(255),
    link_code VARCHAR(50) UNIQUE, -- Temporary linking code
    linked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT true,
    UNIQUE(user_id, telegram_user_id)
);

-- Linking flow:
-- 1. Web app generates: INSERT INTO telegram_links (user_id, link_code, is_active) VALUES (123, 'ABC123DEF', false)
-- 2. Bot verifies: SELECT * FROM telegram_links WHERE link_code='ABC123DEF' AND is_active=false
-- 3. Bot updates: UPDATE telegram_links SET telegram_user_id=456, telegram_username='john_doe', is_active=true WHERE link_code='ABC123DEF'
```

**API Endpoints (Backend):**
```
POST /api/v1/telegram/link
  - Body: { "user_id": 123 }
  - Returns: { "code": "ABC123DEF", "expires_at": "2026-04-08T12:00:00Z" }
  - Link code valid for 24 hours

POST /api/v1/telegram/verify
  - Body: { "link_code": "ABC123DEF", "telegram_user_id": 456, "telegram_username": "john_doe" }
  - Returns: { "success": true, "user_id": 123 }

GET /api/v1/telegram/user/{telegram_user_id}
  - Returns: { "user_id": 123, "linked": true } or 404 if not linked
```

**Bot Architecture:**
- Library: `python-telegram-bot` 20.x
- Framework: Runs as separate Docker container/service
- Database: Connects to same PostgreSQL instance
- Entry point: `/backend/telegram_bot/main.py`
- Config: Bot token stored in environment variable `TELEGRAM_BOT_TOKEN`
- OCR: Reuses same Claude Vision pipeline as web app (shared module)
- Expense creation: Calls shared `create_expense()` function to ensure consistency

**Bot Implementation (Pseudocode):**
```python
# telegram_bot/main.py
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes
import aiohttp
from shared_modules import create_expense, extract_receipt_data, query_expenses

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    telegram_id = update.message.from_user.id
    user = get_user_by_telegram_id(telegram_id)
    if not user:
        await update.message.reply_text("👋 Not linked. Visit https://finance.armandointeligencia.com/telegram-link to link your account.")
    else:
        await update.message.reply_text(f"Welcome, {user.name}! Use /help for commands.")

async def add_expense(update: Update, context: ContextTypes.DEFAULT_TYPE):
    # /add 5.50 coffee
    args = context.args
    if len(args) < 1:
        await update.message.reply_text("Usage: /add <amount> [description]")
        return

    amount = float(args[0])
    description = " ".join(args[1:]) if len(args) > 1 else "Expense"
    user = get_user_by_telegram_id(update.message.from_user.id)

    # Show category buttons
    keyboard = [[InlineKeyboardButton("☕ Coffee", callback_data="cat_coffee"),
                 InlineKeyboardButton("🍔 Food", callback_data="cat_food")],
                [InlineKeyboardButton("❓ Other", callback_data="cat_other")]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await context.bot.send_message(chat_id=update.effective_chat.id, text="Pick a category:", reply_markup=reply_markup)
    # Store amount/description in context.user_data for callback handler

async def handle_photo(update: Update, context: ContextTypes.DEFAULT_TYPE):
    file = await update.message.photo[-1].get_file()
    image_data = await file.download_as_bytearray()

    await update.message.reply_text("📸 Processing receipt...")

    extracted = extract_receipt_data(image_data)  # Claude Vision OCR
    user = get_user_by_telegram_id(update.message.from_user.id)

    keyboard = [[InlineKeyboardButton("✅ Confirm", callback_data=f"confirm_receipt_{extracted['id']}"),
                 InlineKeyboardButton("✏️ Edit", callback_data=f"edit_receipt_{extracted['id']}"),
                 InlineKeyboardButton("❌ Cancel", callback_data="cancel")]]
    reply_markup = InlineKeyboardMarkup(keyboard)

    text = f"✅ Found: ${extracted['amount']} from {extracted['merchant']}\nCategory?"
    await context.bot.send_message(chat_id=update.effective_chat.id, text=text, reply_markup=reply_markup)

async def today_expenses(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = get_user_by_telegram_id(update.message.from_user.id)
    expenses = query_expenses(user_id=user.id, days=1)
    total = sum(e.amount for e in expenses)
    categories = ", ".join([e.category for e in expenses])
    await update.message.reply_text(f"Today: ${total:.2f}\nCategories: {categories}")

def main():
    app = Application.builder().token(os.getenv("TELEGRAM_BOT_TOKEN")).build()

    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("add", add_expense))
    app.add_handler(CommandHandler("today", today_expenses))
    app.add_handler(MessageHandler(filters.PHOTO, handle_photo))

    app.run_polling()

if __name__ == "__main__":
    main()
```

**Docker Setup:**
```yaml
telegram-bot:
  build:
    context: ./backend
    dockerfile: Dockerfile.telegram
  depends_on:
    - finance-db
  environment:
    DATABASE_URL: postgresql://user:pass@finance-db:5432/finance
    TELEGRAM_BOT_TOKEN: ${TELEGRAM_BOT_TOKEN}
  networks:
    - backend
  restart: unless-stopped
  healthcheck:
    test: ["CMD", "python", "-c", "import requests; requests.get('http://localhost:8003/health')"]
    interval: 30s
    timeout: 10s
    retries: 3
  deploy:
    resources:
      limits:
        cpus: '0.2'
        memory: 256M
```

**Frontend Additions:**

New routes/pages:
- `/telegram-link` — Page for generating link code (shows code, QR code to bot, copy button)
- Settings page: Add "Telegram" section showing linked account (username + unlink button)

Components:
- TelegramLinkModal: Modal to show code, QR for @ArmandoFinanceBot + /verify instructions
- TelegramSection: Display linked Telegram account in settings

---

**Application Version:** 4.0 (AI Finance Chat + Telegram)
**Status:** Production-ready plan
