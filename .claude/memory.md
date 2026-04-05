# Project Memory -- Finance Tracker v4.0

## User Profile
- **Armando** -- developer building a portfolio of 10+ self-hosted web apps on Hostinger KVM2 VPS (2 vCPU, 8GB RAM, Ubuntu) behind Traefik with auto-SSL
- Two domains: 305-ai.com and armandointeligencia.com
- This project: finance.armandointeligencia.com
- Multi-user: Armando (superuser/admin) + Mom + future users
- Bilingual support: English + Spanish (receipts, transactions)

## Technical Preferences
- Python backend: FastAPI + SQLAlchemy 2.0 + Alembic, managed with `uv` (NOT pip/conda)
- Frontend: Next.js 14+ with TypeScript, App Router, TailwindCSS + Shadcn/UI
- Database: PostgreSQL 16
- Testing: pytest (backend) + vitest (frontend)
- No Python notebooks -- all code as proper modules
- Docker Compose for deployment, multi-stage builds
- Local dev on Apple Silicon Mac, deploy to VPS
- Memory must be stored in local `.claude/` directory (not global `~/.claude/`)

## Project Context
- This is a **website** at finance.armandointeligencia.com -- NOT a native app, NOT on any App Store
- No Apple Developer License needed
- Users can "Add to Home Screen" for a native-like shortcut (free browser feature)
- Core philosophy: logging an expense should take <10 seconds
- PLAN.md has the full v4.0 spec (AI Finance Chat + Telegram Bot + all original features)

## Key Technical Decisions

### Original (v1.0, 2026-03-29)
- **Receipt OCR**: Claude Haiku 4.5 (`claude-haiku-4-5-20251001`) primary (~$0.40/month), pytesseract offline fallback
- **Camera input**: `<input type="file" accept="image/*" capture="environment">` primary (better iPhone quality)
- **PDF parsing**: pdfplumber for text PDFs, pdf2image + Claude Vision for scanned
- **Fuzzy matching**: rapidfuzz (NOT fuzzywuzzy) -- 10-16x faster, MIT license
- **Drag-and-drop**: @dnd-kit/sortable with TouchSensor for mobile
- **Charts**: Recharts with ResponsiveContainer
- **Auth**: FastAPI-Users + custom refresh tokens (JWT 15min access + 7-day refresh in http-only cookie)
- **Feature flags**: DB table + FastAPI `require_feature()` dependency
- **Client-side debt math**: TypeScript in `debt-math.ts` for instant "what-if" slider
- **Bank CSV auto-detect**: inspect header row keywords to identify Chase/BofA/Wells Fargo/Citi/Discover
- **Debt strategies**: Avalanche, Snowball, Hybrid (Snowball->Avalanche after 1-2 debts), Snowflake (windfalls)

### v4.0 Expansion (2026-04-01)
- **AI Chat**: SSE streaming via FastAPI StreamingResponse, keyword-based intent classification (spending/budget/debt/category/trend), financial context retrieved from PostgreSQL queries
- **Chat models**: Haiku default (`claude-haiku-4-5-20251001`), Sonnet toggle (`claude-sonnet-4-5-20241022`), per-conversation model selection
- **Chat storage**: ChatConversation + ChatMessage tables, UUID primary keys, financial_context_json stored per assistant message for auditability
- **Telegram bot**: python-telegram-bot 21.x, runs as separate Docker container, communicates with main API via internal Docker network (http://finance-api:8002)
- **Telegram linking**: One-time code flow -- web app generates code, user sends `/verify CODE` to bot, bot calls /api/v1/telegram/verify to activate link
- **Telegram expense parsing**: Regex-based natural language parsing ("coffee 4.50", "4.50 coffee"), inline keyboard for category selection
- **Telegram OCR**: Reuses same Claude Vision pipeline as web app via internal API calls
- **Health checks**: Telegram bot runs aiohttp on port 8003 for Docker HEALTHCHECK

## Current Build Status (as of 2026-04-01)

### Application Version: 4.0.0

### Backend (63 pytest tests -- ALL PASSING)
- **61 Python files** across src/app/ and telegram_bot/
- **18 SQLAlchemy models**: User, RefreshToken, Category, Expense, ReceiptArchive, ImportHistory, RecurringExpense, CreditCard, Loan, DebtPayment, DebtSnapshot, FriendDeposit, ExternalAccount, UserFeatureFlag, AutoLabelRule, MonthlySummary, ChatConversation, ChatMessage, TelegramLink
- **15 API routers**: auth, categories, expenses, receipts, imports, credit_cards, loans, debt_strategy, friend_debt, analytics, tax_export, auto_label, admin, chat, telegram
- **7 services**: ocr.py, image_processor.py, csv_parser.py, debt_calculator.py, debt_strategies.py, friend_debt_calc.py, chat.py
- **8 test files**: test_auth (6), test_chat (21), test_telegram (12), test_csv_parser (6), test_debt_calculator (6), test_debt_strategies (5), test_feature_flags (3), test_friend_debt (4)
- **Telegram bot**: telegram_bot/main.py with 8 command handlers + photo handler + NLP expense parsing

### Frontend (24 vitest tests -- ALL PASSING)
- **17 App Router pages**: /, /login, /expenses, /debt, /chat, /analytics, /categories, /import, /receipts, /settings, /friend-debt, /hidden, /admin, /telegram-link (+ /scan implied by Navigation)
- **3 components**: Navigation.tsx, ReceiptScanner.tsx, QuickAddModal.tsx
- **3 lib modules**: api.ts, debt-math.ts, image-compress.ts
- **2 contexts**: AuthContext.tsx, FeatureFlagsContext.tsx
- **Types**: types/index.ts (User, Category, Expense, CreditCard, Loan, DebtPayment, ParsedTransaction, StrategyResult, FriendDebtSummary, ChatConversation, ChatMessage, TelegramLinkCode, TelegramStatus)
- **3 test files**: chat.test.ts (13 tests), debt-math.test.ts (10 tests), image-compress.test.ts (2 tests -- note: in __tests__/ dir)

### Infrastructure
- **Docker**: 4 services (finance-api, finance-web, postgres, telegram-bot)
- **docker-compose.yml**: Production config with Traefik labels for auto-SSL
- **docker-compose.dev.yml**: Dev config with hot-reload
- **Makefile**: dev, dev-api, dev-web, test, test-api, test-web, migrate, build, up, down, logs
- **Dockerfile.telegram**: Separate Dockerfile for the Telegram bot container

### Key Files Modified in v4.0 Session
- `backend/src/app/models/__init__.py` -- added ChatConversation, ChatMessage, TelegramLink
- `backend/src/app/config.py` -- added telegram_bot_token setting
- `backend/src/app/main.py` -- added chat + telegram routers, bumped to v4.0.0
- `backend/pyproject.toml` -- added python-telegram-bot, aiohttp, sse-starlette deps
- `docker-compose.yml` -- added telegram-bot service + TELEGRAM_BOT_TOKEN env var
- `frontend/src/components/Navigation.tsx` -- added Chat tab (MessageCircle icon)
- `frontend/src/types/index.ts` -- added Chat + Telegram types
- `frontend/src/lib/api.ts` -- added 8 methods (chat CRUD + streaming, telegram link/status/unlink)
- `frontend/src/app/settings/page.tsx` -- added Telegram section (linked/unlink UI)
- `frontend/vitest.config.ts` -- upgraded to pool: "threads" for vitest 4.x compatibility
- `frontend/package.json` -- upgraded vitest 1.6→4.1.2, @vitejs/plugin-react 4.3→6.0, jsdom 24→29
- `CLAUDE.md`, `README.md`, `.claude/memory.md` -- updated for v4.0

## Gotchas & Patterns Learned
- Use `JSON` not `JSONB`/`ARRAY` in SQLAlchemy models -- JSONB is PostgreSQL-only, breaks SQLite tests
- Use `bcrypt` directly, not `passlib` -- passlib has compatibility issues with bcrypt 4.x on Python 3.12+
- Next.js 14 uses `.mjs` not `.ts` for config files
- Exclude `vitest.config.ts` from tsconfig to prevent vite version conflicts
- lucide-react icons don't accept `title` prop -- wrap in `<span title="">` instead
- `ringColor` is not a valid CSS style property -- use `outlineColor` instead
- SQLite stores datetimes without timezone -- strip tzinfo before comparing with timezone-aware values
- conftest.py must drop_all BEFORE create_all to handle stale test.db files
- pytest needs `uv pip install pytest pytest-asyncio` if not picked up from dev deps
- **vitest + vite version mismatch**: vitest 1.x is incompatible with vite 7+. Must use vitest 4.x with vite 8.x
- **vitest pool: "threads"**: The default `forks` pool times out when the project path contains spaces. Use `pool: "threads"` in vitest.config.ts
- **Node.js on this machine**: v24.14.0 (via /opt/homebrew/bin/node)
- **Python on this machine**: 3.13.9 (via miniconda base)

## Feedback & Learned Preferences
- Store all memory/notes locally in `.claude/` directory, not global `~/.claude/`
- Project folder should be fully portable (copy to another computer with all context)
- `.claude/` directory should be committed to git
- User wants things fixed, not explained away -- when vitest was hanging, user said "find a way to fix it and do it"
