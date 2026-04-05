.PHONY: dev dev-api dev-web test test-api test-web migrate build up down logs clean

# Development
dev:
	docker compose -f docker-compose.dev.yml up -d postgres
	@echo "Postgres running on localhost:5432"
	@echo "Run 'make dev-api' and 'make dev-web' in separate terminals"

dev-api:
	cd backend && uv run uvicorn src.app.main:app --reload --port 8002

dev-web:
	cd frontend && npm run dev

dev-web-https:
	cd frontend && npm run dev:https

# Testing
test: test-api test-web

test-api:
	cd backend && uv run pytest -x -v

test-web:
	cd frontend && npm run test

# Database
migrate:
	cd backend && uv run alembic upgrade head

migration:
	cd backend && uv run alembic revision --autogenerate -m "$(msg)"

# Docker
build:
	docker compose build

up:
	docker compose up -d

down:
	docker compose down

logs:
	docker compose logs -f

logs-api:
	docker compose logs -f finance-api

# Cleanup
clean:
	docker compose down -v
	rm -rf backend/.venv frontend/node_modules frontend/.next
