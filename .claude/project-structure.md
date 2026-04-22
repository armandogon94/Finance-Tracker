# Project Structure

```
04-Finance-Tracker/
├── CLAUDE.md           # This file — AI working context
├── README.md           # Public-facing documentation
├── PLAN.md             # Detailed technical specification
├── PRD.md              # Product requirements document
├── AGENTS.md           # Specialist role checklists
├── USER-STORY-MAP.md   # Story map: 8 activities, 50+ tasks, 60+ stories
├── PORT-MAP.md         # Port allocation for all projects
├── .claude/            # Local AI memory (committed to git)
│   ├── memory.md       # Persistent context
│   ├── scratchpad.md   # Quick reference
│   └── build-log.md    # Session history
├── backend/
│   ├── pyproject.toml          # uv dependencies
│   ├── src/app/
│   │   ├── models/             # 18 SQLAlchemy models
│   │   │   ├── __init__.py     # Exports all models
│   │   │   ├── user.py         # User, RefreshToken
│   │   │   ├── category.py     # Category
│   │   │   ├── expense.py      # Expense
│   │   │   ├── receipt.py      # ReceiptArchive
│   │   │   ├── import_history.py
│   │   │   ├── recurring.py    # RecurringExpense
│   │   │   ├── credit_card.py  # CreditCard
│   │   │   ├── loan.py         # Loan
│   │   │   ├── debt_payment.py # DebtPayment, DebtSnapshot
│   │   │   ├── friend_debt.py  # FriendDeposit, ExternalAccount
│   │   │   ├── feature_flag.py # UserFeatureFlag
│   │   │   ├── auto_label.py   # AutoLabelRule
│   │   │   ├── monthly_summary.py # MonthlySummary
│   │   │   ├── chat.py         # ChatConversation, ChatMessage [v4.0]
│   │   │   └── telegram.py     # TelegramLink [v4.0]
│   │   ├── schemas/            # Pydantic v2 schemas (request/response)
│   │   │   ├── auth.py, category.py, expense.py, debt.py, imports.py
│   │   │   ├── friend_debt.py, admin.py, auto_label.py
│   │   │   ├── chat.py         # [v4.0]
│   │   │   └── telegram.py     # [v4.0]
│   │   ├── routers/            # 15 API routers
│   │   │   ├── auth.py, categories.py, expenses.py, receipts.py, imports.py
│   │   │   ├── credit_cards.py, loans.py, debt_strategy.py, friend_debt.py
│   │   │   ├── analytics.py, tax_export.py, auto_label.py, admin.py
│   │   │   ├── chat.py         # 6 endpoints (CRUD + streaming) [v4.0]
│   │   │   └── telegram.py     # 5 endpoints (link, verify, lookup, status, unlink) [v4.0]
│   │   ├── services/           # 7 business logic services
│   │   │   ├── ocr.py          # Claude Vision + Tesseract
│   │   │   ├── image_processor.py
│   │   │   ├── csv_parser.py   # Bank statement parser
│   │   │   ├── debt_calculator.py
│   │   │   ├── debt_strategies.py # Avalanche, Snowball, Hybrid, Snowflake
│   │   │   ├── friend_debt_calc.py
│   │   │   └── chat.py         # Intent classification, financial context, streaming [v4.0]
│   │   ├── dependencies/       # FastAPI dependencies
│   │   │   ├── auth.py         # JWT auth
│   │   │   └── feature_flags.py # require_feature()
│   │   ├── config.py           # Pydantic settings (.env)
│   │   ├── database.py         # SQLAlchemy setup
│   │   └── main.py             # FastAPI app init
│   ├── telegram_bot/           # Telegram bot service [v4.0]
│   │   ├── __init__.py
│   │   └── main.py             # Bot: 8 commands, photo handler, NLP, health check
│   ├── alembic/                # Database migrations
│   ├── tests/                  # pytest test suite (63 tests)
│   │   ├── conftest.py
│   │   ├── test_auth.py (6 tests)
│   │   ├── test_chat.py (21 tests) [v4.0]
│   │   ├── test_telegram.py (12 tests) [v4.0]
│   │   ├── test_csv_parser.py (6 tests)
│   │   ├── test_debt_calculator.py (6 tests)
│   │   ├── test_debt_strategies.py (5 tests)
│   │   └── test_feature_flags.py, test_friend_debt.py
│   ├── Dockerfile             # Backend container
│   ├── Dockerfile.telegram    # Telegram bot container [v4.0]
│   └── pyproject.toml         # uv deps: fastapi, sqlalchemy, alembic, pytest, python-telegram-bot
├── frontend/
│   ├── src/
│   │   ├── app/                # 17 Next.js App Router pages
│   │   │   ├── layout.tsx
│   │   │   ├── page.tsx        # Home/Dashboard
│   │   │   ├── login/page.tsx
│   │   │   ├── expenses/page.tsx
│   │   │   ├── debt/page.tsx
│   │   │   ├── chat/page.tsx   # Full chat UI with sidebar, streaming [v4.0]
│   │   │   ├── analytics/page.tsx
│   │   │   ├── categories/page.tsx
│   │   │   ├── import/page.tsx
│   │   │   ├── receipts/page.tsx
│   │   │   ├── settings/page.tsx # Updated with Telegram section [v4.0]
│   │   │   ├── friend-debt/page.tsx
│   │   │   ├── hidden/page.tsx
│   │   │   ├── admin/page.tsx
│   │   │   ├── telegram-link/page.tsx # Link code generation [v4.0]
│   │   │   ├── scan/page.tsx   # Receipt scanner (implied)
│   │   │   └── globals.css
│   │   ├── components/         # 3 components
│   │   │   ├── Navigation.tsx  # Tab bar (modified for Chat) [v4.0]
│   │   │   ├── ReceiptScanner.tsx
│   │   │   └── QuickAddModal.tsx
│   │   ├── contexts/           # 2 React contexts
│   │   │   ├── AuthContext.tsx
│   │   │   └── FeatureFlagsContext.tsx
│   │   ├── lib/                # 3 utilities + tests
│   │   │   ├── api.ts          # API client (8 new chat/telegram methods) [v4.0]
│   │   │   ├── debt-math.ts    # Debt strategy calculations
│   │   │   ├── image-compress.ts
│   │   │   └── chat.test.ts    # 13 vitest tests [v4.0]
│   │   └── types/
│   │       └── index.ts        # TypeScript interfaces (Chat + Telegram types) [v4.0]
│   ├── __tests__/              # Unit tests outside src/
│   │   ├── debt-math.test.ts (10 tests)
│   │   └── image-compress.test.ts (2 tests)
│   ├── package.json            # npm deps (vitest 4.1.2, next, react, etc)
│   ├── vitest.config.ts        # pool: "threads" (fixes forks timeout)
│   ├── next.config.mjs         # Next.js configuration
│   ├── tsconfig.json
│   ├── Dockerfile              # Frontend container
│   └── .next/                  # Next.js build output (git-ignored)
├── Makefile                    # Convenience commands
├── docker-compose.yml          # Production config (Traefik labels)
├── docker-compose.dev.yml      # Dev config (hot-reload)
└── .gitignore                  # Node modules, .env, build artifacts
```

**[v4.0] markers** show files created/modified in v4.0 session (2026-04-01).
