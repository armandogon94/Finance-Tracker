# Finance Tracker — Expense Tracking with Receipt Scanner & Debt Tracking

## Project Overview
Mobile-first expense tracking web app at **finance.armandointeligencia.com**. This is a responsive website (NOT a native app) with a login screen. Works on iPhone Safari, Android Chrome, and desktop browsers. Users can "Add to Home Screen" for a native-like shortcut.

**Core features:** Quick expense add (<10 seconds), receipt photo scanning with ML extraction (Claude Vision + Tesseract), bank/CC statement import (PDF + CSV), credit card & loan debt tracking with payoff strategy engine, AI Finance Chat (Claude-powered), Telegram bot for on-the-go logging, admin panel with per-user feature flags.

**Users:** Armando (superuser/admin) + Mom + future users. Bilingual: English + Spanish.

## Tech Stack
- **Frontend:** Next.js 14+ (TypeScript, App Router) + TailwindCSS + Shadcn/UI + Recharts
- **Backend:** FastAPI (Python 3.11+) + SQLAlchemy 2.0 + Alembic + Pydantic v2
- **Database:** PostgreSQL 16
- **Auth:** FastAPI-Users with JWT (15-min access + 7-day refresh tokens)
- **OCR:** Claude Haiku 4.5 (primary) + pytesseract (offline fallback)
- **AI Chat:** Claude Haiku/Sonnet with SSE streaming
- **Telegram:** python-telegram-bot 21.x (separate Docker service)
- **PDF Parsing:** pdfplumber + pdf2image (scanned PDF fallback)
- **Deployment:** Docker Compose behind Traefik with auto-SSL

## Project Structure
```
04-Finance-Tracker/
├── CLAUDE.md          # This file
├── PLAN.md            # Detailed project plan with schema + API spec
├── README.md          # GitHub-facing documentation
├── .claude/           # Local AI memory (committed to git)
│   ├── memory.md      # Persistent notes and decisions
│   └── scratchpad.md  # Temporary working notes
├── backend/           # FastAPI Python backend
│   ├── pyproject.toml # Dependencies managed with uv
│   ├── src/app/       # Application code
│   │   ├── models/    # SQLAlchemy models (18 tables)
│   │   ├── schemas/   # Pydantic schemas
│   │   ├── routers/   # API route handlers (15 routers)
│   │   ├── services/  # Business logic (OCR, chat, parsers, debt calc)
│   │   └── dependencies/ # FastAPI dependencies (auth, feature flags)
│   ├── telegram_bot/  # Telegram bot service
│   ├── alembic/       # Database migrations
│   └── tests/         # pytest tests (63 tests)
└── frontend/          # Next.js TypeScript frontend
    ├── src/app/       # App Router pages
    ├── src/components/ # React components
    ├── src/contexts/  # Auth + feature flag contexts
    ├── src/lib/       # Utilities (API client, debt math, image compress)
    └── __tests__/     # vitest tests
```

## Development Commands

### Backend
```bash
cd backend
uv sync                          # Install dependencies
uv run uvicorn src.app.main:app --reload --port 8002  # Run dev server
uv run alembic upgrade head      # Run migrations
uv run alembic revision --autogenerate -m "description"  # Create migration
uv run pytest                    # Run tests
uv run pytest -x -v              # Run tests (verbose, stop on first failure)
```

### Frontend
```bash
cd frontend
npm install                      # Install dependencies
npm run dev                      # Run dev server (port 3000)
npm run dev -- --experimental-https  # Dev with HTTPS (for camera testing)
npm run build                    # Production build
npm run test                     # Run vitest tests
```

### Docker
```bash
docker compose up -d             # Start all services
docker compose -f docker-compose.dev.yml up  # Dev mode with hot-reload
docker compose down              # Stop all services
docker compose logs -f finance-api  # Tail API logs
```

### Makefile
```bash
make dev          # Start local development
make test         # Run all tests (backend + frontend)
make migrate      # Run database migrations
make build        # Build Docker images
```

## Key Conventions

### Code Style
- Python: ruff for linting/formatting
- TypeScript: ESLint + Prettier via Next.js defaults
- Mobile-first CSS: design for phone screens, enhance for desktop
- No Python notebooks — all code as proper modules

### API Design
- All endpoints under `/api/v1/`
- JWT auth via HTTP-only cookies (access token) + refresh token endpoint
- Feature-gated endpoints use `require_feature("flag_name")` dependency
- Admin endpoints use `require_superuser` dependency
- Pydantic v2 schemas for request/response validation

### Database
- UUID primary keys everywhere
- Soft deletes via `is_active` flag (not hard deletes)
- `created_at` / `updated_at` timestamps on all tables
- Alembic for all schema changes (never raw SQL in production)

### Testing
- Backend: pytest + httpx AsyncClient + mocked external APIs (Claude, etc.)
- Frontend: vitest + React Testing Library
- Test files mirror source structure

### Environment Variables
- Backend reads from `.env` via pydantic-settings
- Frontend uses `NEXT_PUBLIC_` prefix for client-side vars
- Never commit `.env` — use `.env.example` as template

## Feature Flags
Two admin-toggle features:
- `friend_debt_calculator` — Friend debt tracking (Armando-specific)
- `hidden_categories` — Private expense categories hidden from main views

## Domain
- **Production:** finance.armandointeligencia.com (frontend), api.finance.armandointeligencia.com (backend)
- **Local dev:** localhost:3000 (frontend), localhost:8002 (backend)
