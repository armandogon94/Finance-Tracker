# Technical Decisions & Architecture

## Original Release (v1.0, 2026-03-29)

- **Receipt OCR:** Claude Haiku 4.5 primary (cost: ~$0.40/month at 100 receipts), pytesseract offline fallback
- **Camera input:** `<input type="file" accept="image/*" capture="environment">` for better iPhone quality
- **PDF parsing:** pdfplumber for text PDFs, pdf2image + Claude Vision for scanned
- **Fuzzy matching:** rapidfuzz (NOT fuzzywuzzy) — 10-16x faster, MIT license
- **Drag-and-drop:** @dnd-kit/sortable with TouchSensor for mobile
- **Charts:** Recharts with ResponsiveContainer
- **Auth:** FastAPI-Users + custom JWT (15-min access, 7-day refresh in http-only cookie)
- **Feature flags:** DB table + FastAPI `require_feature()` dependency
- **Debt math:** TypeScript in `debt-math.ts` for instant "what-if" slider calculations
- **Bank CSV auto-detect:** Keyword-based header detection for Chase, BofA, Wells Fargo, Citi, Discover
- **Debt strategies:** Avalanche, Snowball, Hybrid (Snowball→Avalanche after 1-2 debts), Snowflake (windfalls)

## v4.0 Expansion (2026-04-01)

- **AI Chat:** SSE streaming via FastAPI StreamingResponse
- **Intent classification:** Keyword-based (spending, budget, debt, category, trend), supports EN + ES
- **Chat models:** Haiku default, Sonnet toggle, per-conversation model selection
- **Chat storage:** ChatConversation + ChatMessage tables, UUID PKs, financial_context_json per response
- **Telegram bot:** python-telegram-bot 21.x, separate Docker container, internal HTTP network
- **Telegram linking:** One-time code flow (24h expiry, user sends `/verify CODE` to bot)
- **Telegram NLP:** Regex-based parsing ("coffee 4.50", "4.50 coffee"), inline keyboard category selection
- **Health checks:** Telegram bot runs aiohttp on port 8003 for Docker HEALTHCHECK

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
