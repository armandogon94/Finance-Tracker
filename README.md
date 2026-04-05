# Finance Tracker

Smart expense tracking with receipt OCR, AI-powered financial chat, bank statement import, debt payoff strategies, and Telegram bot integration.

**Live at:** [finance.armandointeligencia.com](https://finance.armandointeligencia.com)

## Features

### Five Ways to Log Expenses

| Method | Description | Speed |
|--------|------------|-------|
| **Quick Add** | Amount + category in 2 taps | ~5 seconds |
| **Receipt Scanner** | Snap a photo, AI reads the receipt, confirm and save | ~15 seconds |
| **Bank Statement Import** | Upload PDF or CSV from your bank, auto-parse all transactions | Bulk |
| **Credit Card Statement** | Upload CC statement, track charges and running balance | Bulk |
| **Telegram Bot** | Text "coffee 4.50" or send a receipt photo to the bot | ~5 seconds |

### Receipt OCR Architecture

```
Camera Photo --> Client Compression (<200KB)
                     |
              +------+------+
              |             |
        Claude Haiku    Tesseract
        (Primary)      (Fallback)
              |             |
              +------+------+
                     |
            Structured JSON
     (merchant, date, total, tax, items)
                     |
              User Review --> Save Expense
```

- **Primary:** Claude Haiku 4.5 Vision API (~$0.40/month at 100 receipts)
- **Fallback:** Tesseract OCR (offline, free) with English + Spanish support
- **User configurable:** Auto / Cloud Only / Offline Only / Manual

### AI Finance Chat

Conversational interface powered by Claude for intelligent financial insights based on your actual spending data.

```
User: "How much did I spend on groceries last month?"
                |
         Intent Classification
         (spending, budget, debt, trend)
                |
         Financial Data Retrieval
         (queries PostgreSQL for relevant data)
                |
         Claude API (Haiku / Sonnet)
         (streaming SSE response)
                |
         Chat UI (real-time display)
```

**Capabilities:**
- **Spending queries** -- "What's my biggest expense category this year?"
- **Budget advice** -- "Am I on track with my budget this month?"
- **Debt coaching** -- "What's the fastest way to pay off my credit cards?"
- **Trend analysis** -- "Compare my spending in March vs February"
- **Model toggle** -- Haiku (fast/cheap) or Sonnet (deep analysis) per conversation

### Debt Tracking & Payoff Strategies

- Track credit cards (balance, APR, utilization, minimum payment)
- Track loans (car, student, personal, mortgage) with amortization schedules
- **Four payoff strategies compared side-by-side:**
  - **Avalanche** -- Highest interest first (saves the most money)
  - **Snowball** -- Smallest balance first (fastest psychological wins)
  - **Hybrid** -- Quick wins first, then switch to Avalanche
  - **Snowflake** -- Micro-payments from windfalls on top of any strategy
- Interactive "what-if" slider to see how extra payments change the timeline

### Telegram Bot

Log expenses and query spending from Telegram -- no need to open the web app.

**Commands:**
- `/add 5.50 coffee` -- Quick expense logging
- Send a photo -- Receipt OCR scanning
- `/today` -- Today's spending summary
- `/month` -- Month-to-date totals
- `/budget` -- Budget status per category
- `/history` -- Last 10 expenses

**Account linking:** Generate a code in the web app, send `/verify CODE` to the bot.

### Admin Panel & Feature Flags

- Superuser-only `/admin` panel for managing users and features
- Per-user feature flags toggle optional features:
  - **Friend Debt Calculator** -- Track money owed when a friend uses your account
  - **Hidden Categories** -- Private expenses counted in totals but hidden from main views

### Spending Analytics

- Daily, weekly, monthly spending charts
- Category breakdown pie charts
- Budget progress bars with alerts
- Period-over-period comparisons
- Tax-season CSV export and receipt ZIP download

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | Next.js 14, TypeScript, TailwindCSS, Shadcn/UI, Recharts |
| Backend | FastAPI, Python 3.11+, SQLAlchemy 2.0, Pydantic v2 |
| Database | PostgreSQL 16 |
| Auth | JWT (access + refresh tokens) |
| OCR | Claude Haiku 4.5 + Tesseract |
| AI Chat | Claude Haiku/Sonnet with SSE streaming |
| PDF Parsing | pdfplumber + pdf2image |
| Telegram | python-telegram-bot 21.x |
| Deployment | Docker Compose, Traefik (auto-SSL) |

## Quick Start

### Prerequisites
- Python 3.11+ with [uv](https://docs.astral.sh/uv/)
- Node.js 20+
- Docker Desktop (for PostgreSQL)

### Setup
```bash
# Clone
git clone https://github.com/your-username/finance-tracker.git
cd finance-tracker

# Copy environment variables
cp .env.example .env
# Edit .env with your settings (API keys, bot token, etc.)

# Start database
make dev

# Backend (terminal 1)
cd backend
uv sync
uv run alembic upgrade head
make dev-api

# Frontend (terminal 2)
cd frontend
npm install
make dev-web
```

### Environment Variables

```env
# Required
DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5432/finance_db
JWT_SECRET=your-secret-key

# OCR & AI Chat
ANTHROPIC_API_KEY=sk-ant-...

# Telegram Bot
TELEGRAM_BOT_TOKEN=123456:ABC-DEF...

# Optional
OCR_MODE=auto                # auto|cloud|offline|manual
CORS_ORIGINS=["http://localhost:3000"]
```

### Telegram Bot Setup

1. Create a bot via [@BotFather](https://t.me/BotFather) on Telegram
2. Copy the bot token to `TELEGRAM_BOT_TOKEN` in `.env`
3. Deploy with `docker compose up -d` (the bot runs as a separate container)
4. In the web app, go to Settings > Telegram > Link Account
5. Send `/verify YOUR_CODE` to your bot on Telegram

### Mobile Testing

Camera access requires HTTPS. For local testing on your phone:
```bash
# Option 1: Next.js experimental HTTPS
make dev-web-https

# Option 2: ngrok tunnel
ngrok http 3000
```

## Deployment

Deploy to VPS with Docker Compose behind Traefik:
```bash
make build
docker compose up -d
```

Services:
- `finance.armandointeligencia.com` -- Frontend (Next.js)
- `api.finance.armandointeligencia.com` -- Backend API (FastAPI)
- Telegram bot -- Separate container, long-polling
- Receipt images stored in Docker volume `receipt_data`

## Project Structure

```
├── backend/              FastAPI Python backend
│   ├── src/app/
│   │   ├── models/       SQLAlchemy models (18 tables)
│   │   ├── schemas/      Pydantic request/response schemas
│   │   ├── routers/      API route handlers (15 routers)
│   │   ├── services/     Business logic (OCR, chat, debt calc)
│   │   └── dependencies/ Auth, feature flags
│   ├── telegram_bot/     Telegram bot service
│   └── tests/            pytest test suite (63 tests)
├── frontend/             Next.js TypeScript frontend
│   ├── src/app/          App Router pages (17 routes)
│   ├── src/components/   React components
│   ├── src/contexts/     Auth + feature flag contexts
│   └── src/lib/          API client, debt math, image compression
└── docker-compose.yml    Production deployment config (4 services)
```

## API Overview

| Prefix | Description |
|--------|------------|
| `/api/v1/auth/*` | Registration, login, token refresh |
| `/api/v1/expenses/*` | CRUD, quick-add, search, export |
| `/api/v1/categories/*` | CRUD, reorder, hidden categories |
| `/api/v1/receipts/*` | OCR scan, receipt archive |
| `/api/v1/import/*` | Bank statement upload (CSV/PDF) |
| `/api/v1/credit-cards/*` | Credit card tracking |
| `/api/v1/loans/*` | Loan tracking |
| `/api/v1/debt/*` | Payoff strategies, summary |
| `/api/v1/chat/*` | AI conversations, streaming messages |
| `/api/v1/telegram/*` | Account linking, verification |
| `/api/v1/analytics/*` | Spending charts, budget status |
| `/api/v1/admin/*` | User management, feature flags |

## Testing

```bash
# All tests
make test

# Backend only (63 tests)
make test-api

# Frontend only
make test-web
```

## License

Private project. All rights reserved.
