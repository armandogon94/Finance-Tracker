# Port Allocation — Project 04: Finance Tracker

> All host-exposed ports are globally unique across all 16 projects so every project can run simultaneously. See `../PORT-MAP.md` for the full map.

## Current Assignments

| Service | Host Port | Container Port | File |
|---------|-----------|---------------|------|
| Frontend (Next.js) | **3040** | 3000 | docker-compose.dev.yml |
| Backend (FastAPI) | **8040** | 8002 | docker-compose.dev.yml |
| Telegram Bot | **8041** | 8001 | docker-compose.yml (prod) |
| PostgreSQL | **5434** | 5432 | docker-compose.dev.yml |

> Note: Backend container port is 8002 (not 8000) — the FastAPI app is configured with `--port 8002`. The host-facing port is 8040.

## Allowed Range for New Services

If you need to add a new service to this project, pick from these ranges **only**:

| Type | Allowed Host Ports |
|------|--------------------|
| Frontend / UI | `3040 – 3049` |
| Backend / API | `8040 – 8049` |
| PostgreSQL | `5434` (already assigned — do not spin up a second instance) |
| Redis | Not assigned yet. If needed, request an assignment in `../PORT-MAP.md` (6379-6385 are taken). |

## Do Not Use

Every port outside the ranges above is reserved by another project. Always check `../PORT-MAP.md` before picking a port.

Key ranges already taken:
- `3020-3029 / 8020-8029` → Project 02
- `3030-3039 / 8030-8039` → Project 03
- `3050-3059 / 8050-8059` → Project 05
- `5432` → Project 02 PostgreSQL
- `5433` → Project 03 PostgreSQL
- `5435-5439` → Projects 05, 11, 12, 13, 15 PostgreSQL
- `6379-6385` → Projects 02, 05, 10, 12, 13, 15, 16 Redis
- `3000` → macOS/generic default — never use as a host port
- `8080` → Reserved (common proxy) — never use
