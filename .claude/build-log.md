# Build Log -- Finance Tracker

## Session 1: Initial Build (2026-03-29)
**Scope**: v1.0 -- Expense tracking, receipt OCR, bank import, debt tracking, admin panel
**Result**: Backend (55 files, 30 tests passing) + Frontend (25 files, 13 tests passing, build succeeds)

### What was built
- Full FastAPI backend with 13 routers (77 routes), 16 SQLAlchemy models, 6 services
- Full Next.js frontend with 13 App Router pages, 5 components, 3 lib modules
- Docker Compose (prod + dev), Makefile, README, CLAUDE.md
- OCR service (Claude Vision primary + Tesseract fallback)
- Debt calculator with 4 payoff strategies (Avalanche, Snowball, Hybrid, Snowflake)
- Admin panel with per-user feature flags
- Friend debt calculator (feature-flagged)
- Hidden categories (feature-flagged)
- Bank statement CSV parser with auto-detect (Chase, BofA, Wells Fargo, Citi, Discover)

### Bugs fixed
- JSONB/ARRAY -> JSON for SQLite test compatibility
- passlib -> bcrypt direct (compatibility issue)
- next.config.ts -> .mjs (Next.js 14 requirement)
- lucide-react title prop issue
- ringColor -> outlineColor CSS fix
- vitest.config.ts excluded from tsconfig

---

## Session 2: v4.0 Expansion (2026-04-01)
**Scope**: AI Finance Chat + Telegram Bot (per PLAN.md VERSION 4.0 EXPANSION)
**Result**: +14 new files, 12 modified files, 63 backend tests + 24 frontend tests ALL PASSING

### New features built

#### AI Finance Chat
- **Backend service** (`services/chat.py`):
  - `classify_intent()` -- keyword-based intent detection (spending, budget, debt, category, trend) supporting EN + ES
  - `get_financial_context()` -- queries PostgreSQL for monthly spending, category breakdowns, budget status, debt summary, trends, recent expenses based on detected intents
  - `stream_chat_response()` -- calls Claude API with financial context, streams response via async generator
  - `DecimalEncoder` -- JSON encoder for Decimal/date/UUID types
  - Model map: haiku -> `claude-haiku-4-5-20251001`, sonnet -> `claude-sonnet-4-5-20241022`
  - System prompt instructs Claude to be concise, reference actual data, support bilingual
- **Backend router** (`routers/chat.py`):
  - CRUD for conversations (create, list with last message preview, update title, delete)
  - List messages with pagination
  - Send message with SSE streaming (`StreamingResponse` with `text/event-stream`)
  - Auto-generates conversation title from first message
  - Stores financial_context_json per assistant response for auditability
- **Backend models** (`models/chat.py`):
  - `ChatConversation` -- UUID PK, user_id FK, title, created_at, updated_at, messages relationship
  - `ChatMessage` -- UUID PK, conversation_id FK, role (user/assistant), content, financial_context_json, model_used, tokens_used, created_at
- **Frontend page** (`app/chat/page.tsx`):
  - Conversation sidebar (create, select, delete) -- slides in on mobile
  - Message bubbles (user right-aligned blue, assistant left-aligned white)
  - Real-time streaming display with cursor animation
  - Suggested prompt chips (6 prompts) shown on empty chat
  - Model toggle (Haiku/Sonnet) in header
  - Auto-scroll to bottom on new messages
  - Loading indicator (bouncing dots)
  - Keyboard support (Enter to send, Shift+Enter for newline)
  - SSE parsing: reads `data: {json}\n\n` format, handles text + done events

#### Telegram Bot
- **Bot service** (`telegram_bot/main.py`):
  - `/start` -- Welcome message, instructions if not linked
  - `/help` -- Full command reference
  - `/verify <code>` -- Link account via one-time code
  - `/unlink` -- Directs to web app
  - `/add <amount> [description]` -- Quick expense with category inline keyboard
  - `/today` -- Today's spending summary
  - `/month` -- Month-to-date total
  - `/history` -- Last 10 expenses
  - Photo handler -- Downloads photo, base64 encodes, calls OCR API, shows confirm keyboard
  - Text handler -- Parses "coffee 4.50" / "4.50 coffee" via regex, shows category keyboard
  - Callback handlers for category selection and receipt confirmation
  - Health check server on port 8003 (aiohttp) for Docker HEALTHCHECK
  - Communicates with main API via httpx (internal Docker network)
- **Backend router** (`routers/telegram.py`):
  - `POST /link` -- Generate 8-char hex code (24h expiry), invalidates previous unused codes
  - `POST /verify` -- Verify code from bot, activate link, prevent duplicate telegram_user_id
  - `GET /user/{telegram_user_id}` -- Lookup user by Telegram ID
  - `GET /status` -- Current user's link status
  - `DELETE /unlink` -- Remove Telegram link
  - Naive/aware datetime fix for SQLite test compatibility
- **Backend model** (`models/telegram.py`):
  - `TelegramLink` -- UUID PK, user_id FK, telegram_user_id (BigInteger, unique), telegram_username, link_code (unique), is_active, linked_at, expires_at
- **Frontend pages**:
  - `/telegram-link` -- Generate link code, copy button, instructions
  - Settings page updated with Telegram section (linked status, unlink button, or link CTA)

### Tests added
- `test_chat.py` (21 tests): Intent classification (9), financial data retrieval (4), conversation API (5), messages API (3)
- `test_telegram.py` (12 tests): Link generation (2), verification (4), lookup (2), status (2), unlink (2)
- `chat.test.ts` (13 tests): Chat types (2), SSE parsing (3), model selection (2), suggested prompts (2), telegram types (2)

### Infrastructure changes
- `docker-compose.yml` -- Added telegram-bot service with Dockerfile.telegram
- `Dockerfile.telegram` -- Python 3.12-slim, uv for deps, non-root user, port 8003
- `pyproject.toml` -- Added python-telegram-bot>=21.0, aiohttp>=3.9.0, sse-starlette>=2.0.0
- `package.json` -- Upgraded vitest 1.6->4.1.2, @vitejs/plugin-react 4.3->6.0.1, jsdom 24->29
- `vitest.config.ts` -- Added `pool: "threads"` (fixes forks timeout with spaces in path)

### Bugs fixed in this session
- Naive/aware datetime comparison in telegram verify endpoint (SQLite doesn't store tz)
- conftest.py: drop_all before create_all to handle stale test.db
- TypeScript null-safety: `conversationId` (string | null) fixed with non-null assertion + local variable
- vitest hanging: root cause was vitest 1.6.1 paired with vite 7.3.1 (incompatible). Fixed by upgrading to vitest 4.1.2 + switching to threads pool

---

## Complete File Inventory (v4.0)

### Backend: backend/src/app/
```
models/
  __init__.py          -- exports all 18+ model classes
  user.py              -- User, RefreshToken
  category.py          -- Category
  expense.py           -- Expense
  receipt.py           -- ReceiptArchive
  import_history.py    -- ImportHistory
  recurring.py         -- RecurringExpense
  credit_card.py       -- CreditCard
  loan.py              -- Loan
  debt_payment.py      -- DebtPayment, DebtSnapshot
  friend_debt.py       -- FriendDeposit, ExternalAccount
  feature_flag.py      -- UserFeatureFlag
  auto_label.py        -- AutoLabelRule
  monthly_summary.py   -- MonthlySummary
  chat.py              -- ChatConversation, ChatMessage [v4.0]
  telegram.py          -- TelegramLink [v4.0]

schemas/
  __init__.py
  auth.py
  category.py
  expense.py
  debt.py
  imports.py
  friend_debt.py
  admin.py
  auto_label.py
  chat.py              -- [v4.0]
  telegram.py          -- [v4.0]

routers/
  __init__.py
  auth.py
  categories.py
  expenses.py
  receipts.py
  imports.py
  credit_cards.py
  loans.py
  debt_strategy.py
  friend_debt.py
  analytics.py
  tax_export.py
  auto_label.py
  admin.py
  chat.py              -- [v4.0]
  telegram.py          -- [v4.0]

services/
  __init__.py
  ocr.py
  image_processor.py
  csv_parser.py
  debt_calculator.py
  debt_strategies.py
  friend_debt_calc.py
  chat.py              -- [v4.0]

dependencies/
  __init__.py
  auth.py
  feature_flags.py

config.py
database.py
main.py
```

### Backend: backend/telegram_bot/
```
__init__.py            -- [v4.0]
main.py                -- [v4.0]
```

### Backend: backend/tests/
```
conftest.py
test_auth.py           -- 6 tests
test_chat.py           -- 21 tests [v4.0]
test_telegram.py       -- 12 tests [v4.0]
test_csv_parser.py     -- 6 tests
test_debt_calculator.py -- 6 tests
test_debt_strategies.py -- 5 tests
test_feature_flags.py  -- 3 tests
test_friend_debt.py    -- 4 tests
```

### Frontend: frontend/src/
```
app/
  layout.tsx
  page.tsx              -- Home/Dashboard
  globals.css
  login/page.tsx
  expenses/page.tsx
  debt/page.tsx
  chat/page.tsx         -- [v4.0]
  analytics/page.tsx
  categories/page.tsx
  import/page.tsx
  receipts/page.tsx
  settings/page.tsx     -- (modified for Telegram section) [v4.0]
  friend-debt/page.tsx
  hidden/page.tsx
  admin/page.tsx
  telegram-link/page.tsx -- [v4.0]

components/
  Navigation.tsx        -- (modified: Chat tab added) [v4.0]
  ReceiptScanner.tsx
  QuickAddModal.tsx

contexts/
  AuthContext.tsx
  FeatureFlagsContext.tsx

lib/
  api.ts                -- (modified: 8 new methods) [v4.0]
  debt-math.ts
  image-compress.ts
  chat.test.ts          -- [v4.0]

types/
  index.ts              -- (modified: Chat + Telegram types) [v4.0]
```

### Frontend: frontend/__tests__/
```
debt-math.test.ts      -- 10 tests
image-compress.test.ts -- 2 tests (note: in __tests__/ not src/lib/)
```

### Infrastructure
```
CLAUDE.md              -- (modified for v4.0)
README.md              -- (rewritten for v4.0)
PLAN.md                -- Full spec (unchanged, reference document)
AGENTS.md              -- 7 specialist roles (unchanged)
PORT-MAP.md            -- Port assignments (unchanged)
Makefile               -- (unchanged)
docker-compose.yml     -- (modified: telegram-bot service added) [v4.0]
docker-compose.dev.yml -- (unchanged)
backend/pyproject.toml -- (modified: new deps, version bump) [v4.0]
backend/Dockerfile.telegram -- [v4.0]
frontend/package.json  -- (modified: vitest upgrade) [v4.0]
frontend/vitest.config.ts -- (modified: pool threads) [v4.0]
.claude/memory.md      -- This session's full context
.claude/scratchpad.md  -- Quick-reference status + TODO
.claude/build-log.md   -- This file
```
