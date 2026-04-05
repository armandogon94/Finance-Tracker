# Scratchpad -- Finance Tracker v4.0

## Current Status (2026-04-01)
v4.0 BUILD COMPLETE. AI Finance Chat + Telegram Bot added to existing expense tracker.
- Backend: 61 Python files, 15 routers, 63 pytest tests ALL PASSING
- Frontend: 17 routes, 24 vitest tests ALL PASSING, `tsc --noEmit` CLEAN, `next build` SUCCEEDS
- Infrastructure: Docker Compose with 4 services (api, web, postgres, telegram-bot)

## How to Run (for next session)

### Quick start
```bash
cd /Users/armandogonzalez/Documents/Claude/Deep\ Research\ Claude\ Code/04-Finance-Tracker

# Start database
docker compose -f docker-compose.dev.yml up -d postgres

# Backend (terminal 1)
cd backend
uv sync --dev
uv run alembic upgrade head
uv run uvicorn src.app.main:app --reload --port 8002

# Frontend (terminal 2)
cd frontend
npm install
npm run dev
```

### Run tests
```bash
# Backend (63 tests)
cd backend && uv run python -m pytest -v

# Frontend (24 tests)
cd frontend && npx vitest run

# Both
make test
```

### TypeScript check
```bash
cd frontend && npx tsc --noEmit
```

## What's Left to Do (Next Session)

### High Priority
- [ ] Run the app end-to-end and verify all pages render correctly
- [ ] Add `.env` file with real ANTHROPIC_API_KEY for receipt OCR testing
- [ ] Test receipt scanning with a real receipt photo
- [ ] Test AI Chat with real Claude API calls (needs ANTHROPIC_API_KEY)
- [ ] Test bank statement import with a real Chase/BofA CSV
- [ ] Create Alembic migration for the new chat + telegram tables
- [ ] Git init + first commit
- [ ] Deploy to VPS via Docker Compose

### Telegram Bot
- [ ] Create Telegram bot via @BotFather and get token
- [ ] Add TELEGRAM_BOT_TOKEN to .env
- [ ] Test bot locally: `cd backend && uv run python -m telegram_bot.main`
- [ ] Test account linking flow end-to-end
- [ ] Test receipt photo via Telegram

### Polish
- [ ] Add Alembic migration: `cd backend && uv run alembic revision --autogenerate -m "add chat and telegram tables"`
- [ ] Add `.env.example` with all required variables documented
- [ ] Add rate limiting on chat endpoint (prevent API cost abuse)
- [ ] Add token usage tracking / cost display in chat UI
- [ ] Consider adding conversation search in the sidebar
- [ ] Test on iPhone Safari (PWA mode) and Android Chrome

### Known Issues
- vitest requires `pool: "threads"` in vitest.config.ts (forks pool times out with spaces in path)
- The Telegram bot's `/today`, `/month`, `/history` commands call internal API endpoints that may need a bot-internal auth mechanism (currently they pass user_id as query param which is not production-secure)
- The chat `send_message` endpoint saves the assistant response after streaming completes using `db.begin_nested()` -- verify this works correctly under real load

## Environment Notes
- **Node.js**: v24.14.0 at /opt/homebrew/bin/node
- **Python**: 3.13.9 via miniconda base
- **uv**: ~/.local/bin/uv
- **npm**: 11.12.1
- **vitest**: 4.1.2 (upgraded from 1.6.1 during this session)
- **vite**: 8.0.3 (was 7.3.1 before vitest upgrade)
- Project path has spaces: `Deep Research Claude Code` -- affects vitest forks pool

## v4.0 New Files Created (14 total)

### Backend (11 files)
1. `backend/src/app/models/chat.py` -- ChatConversation + ChatMessage models
2. `backend/src/app/models/telegram.py` -- TelegramLink model
3. `backend/src/app/schemas/chat.py` -- Pydantic schemas for chat
4. `backend/src/app/schemas/telegram.py` -- Pydantic schemas for telegram
5. `backend/src/app/services/chat.py` -- Intent classification + financial data retrieval + Claude streaming
6. `backend/src/app/routers/chat.py` -- 6 endpoints (CRUD conversations, messages, SSE streaming)
7. `backend/src/app/routers/telegram.py` -- 6 endpoints (link, verify, lookup, status, unlink)
8. `backend/telegram_bot/__init__.py` -- Package init
9. `backend/telegram_bot/main.py` -- Full bot (8 commands, photo handler, NLP parsing)
10. `backend/tests/test_chat.py` -- 21 tests
11. `backend/tests/test_telegram.py` -- 12 tests
12. `backend/Dockerfile.telegram` -- Bot container Dockerfile

### Frontend (3 files)
13. `frontend/src/app/chat/page.tsx` -- Full chat UI with sidebar, streaming, prompts, model toggle
14. `frontend/src/app/telegram-link/page.tsx` -- Link code generation page
15. `frontend/src/lib/chat.test.ts` -- 13 vitest tests

## API Endpoints Added in v4.0

### Chat (`/api/v1/chat/`)
- `POST /conversations` -- Create conversation
- `GET /conversations` -- List conversations (with last message preview)
- `PUT /conversations/{id}` -- Update title
- `DELETE /conversations/{id}` -- Delete conversation + messages
- `GET /conversations/{id}/messages` -- List messages (paginated)
- `POST /conversations/{id}/messages` -- Send message + stream AI response (SSE)

### Telegram (`/api/v1/telegram/`)
- `POST /link` -- Generate one-time link code (24h expiry)
- `POST /verify` -- Verify link code from bot (unauthenticated, bot calls this)
- `GET /user/{telegram_user_id}` -- Look up user by Telegram ID (bot calls this)
- `GET /status` -- Get current user's Telegram link status
- `DELETE /unlink` -- Unlink Telegram account
