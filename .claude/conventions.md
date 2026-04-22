# Code Conventions & Standards

## Code Style

- **Python:** ruff for linting/formatting
- **TypeScript:** ESLint + Prettier via Next.js defaults
- **Mobile-first CSS:** design for phone screens, enhance for desktop
- **No Python notebooks** — all code as proper modules

## API Design

- All endpoints under `/api/v1/`
- JWT auth via HTTP-only cookies (access token) + refresh token endpoint
- Feature-gated endpoints use `require_feature("flag_name")` dependency
- Admin endpoints use `require_superuser` dependency
- Pydantic v2 schemas for request/response validation

## Database

- UUID primary keys everywhere
- Soft deletes via `is_active` flag (not hard deletes)
- `created_at` / `updated_at` timestamps on all tables
- Alembic for all schema changes (never raw SQL in production)

## Testing

- Backend: pytest + httpx AsyncClient + mocked external APIs (Claude, etc.)
- Frontend: vitest + React Testing Library
- Test files mirror source structure

## Environment Variables

- Backend reads from `.env` via pydantic-settings
- Frontend uses `NEXT_PUBLIC_` prefix for client-side vars
- Never commit `.env` — use `.env.example` as template

## Feature Flags

Two admin-toggle features:
- `friend_debt_calculator` — Friend debt tracking (Armando-specific)
- `hidden_categories` — Private expense categories hidden from main views

## Dependency Management

- **Package manager:** `uv` (NOT pip or conda) — 10-100x faster, locking, workspaces
- **Python version:** 3.13.9 (local via miniconda), 3.12-slim in Docker
- **Node.js version:** v24.14.0 (local via homebrew), 22-alpine in Docker
