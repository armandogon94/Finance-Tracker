# Development Commands

## Backend

```bash
cd backend
uv sync                          # Install dependencies
uv run uvicorn src.app.main:app --reload --port 8002  # Run dev server
uv run alembic upgrade head      # Run migrations
uv run alembic revision --autogenerate -m "description"  # Create migration
uv run pytest                    # Run tests
uv run pytest -x -v              # Run tests (verbose, stop on first failure)
```

## Frontend

```bash
cd frontend
npm install                      # Install dependencies
npm run dev                      # Run dev server (port 3000)
npm run dev -- --experimental-https  # Dev with HTTPS (for camera testing)
npm run build                    # Production build
npm run test                     # Run vitest tests
```

## Docker

```bash
docker compose up -d             # Start all services
docker compose -f docker-compose.dev.yml up  # Dev mode with hot-reload
docker compose down              # Stop all services
docker compose logs -f finance-api  # Tail API logs
```

## Makefile

```bash
make dev          # Start local development
make test         # Run all tests (backend + frontend)
make migrate      # Run database migrations
make build        # Build Docker images
```

## Quick Start

```bash
cd /path/to/04-Finance-Tracker

# Start database
docker compose -f docker-compose.dev.yml up -d postgres

# Terminal 1: Backend
cd backend && uv sync --dev && uv run alembic upgrade head
uv run uvicorn src.app.main:app --reload --port 8002

# Terminal 2: Frontend
cd frontend && npm install && npm run dev

# Run tests
make test  # or: backend: uv run pytest; frontend: npm test
```

## API Health Checks

- Backend: GET `/api/v1/health`
- Telegram bot: GET `http://localhost:8003/health`
