"""
Finance Tracker API -- main FastAPI application entry point.

Configures middleware, mounts static files for receipt images, includes all
routers, and provides a health check endpoint.
"""

import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from src.app.config import settings
from src.app.database import Base, engine

logger = logging.getLogger(__name__)


# ─── Lifespan ────────────────────────────────────────────────────────────────


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler.

    On startup:
      - Creates all database tables if they don't exist (dev convenience).
      - Ensures the receipt storage directory exists.

    On shutdown:
      - Disposes of the database engine connection pool.
    """
    # Startup
    logger.info("Starting Finance Tracker API...")

    # Create tables (dev convenience -- use Alembic migrations in production)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    logger.info("Database tables ensured.")

    # Ensure receipt storage path exists
    receipt_path = Path(settings.receipt_storage_path)
    receipt_path.mkdir(parents=True, exist_ok=True)
    logger.info("Receipt storage path: %s", receipt_path)

    yield

    # Shutdown
    await engine.dispose()
    logger.info("Finance Tracker API shut down.")


# ─── App factory ─────────────────────────────────────────────────────────────


app = FastAPI(
    title="Finance Tracker API",
    version="4.0.0",
    description=(
        "Personal finance tracking with receipt OCR, bank statement import, "
        "debt management, AI finance chat, Telegram bot, and analytics."
    ),
    lifespan=lifespan,
)


# ─── Middleware ───────────────────────────────────────────────────────────────


app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─── Static files for receipt images ─────────────────────────────────────────


receipt_storage = Path(settings.receipt_storage_path)
if receipt_storage.exists():
    app.mount(
        "/receipts",
        StaticFiles(directory=str(receipt_storage)),
        name="receipts",
    )


# ─── Routers ─────────────────────────────────────────────────────────────────


from src.app.routers.auth import router as auth_router
from src.app.routers.categories import router as categories_router
from src.app.routers.expenses import router as expenses_router
from src.app.routers.receipts import router as receipts_router
from src.app.routers.imports import router as imports_router
from src.app.routers.credit_cards import router as credit_cards_router
from src.app.routers.loans import router as loans_router
from src.app.routers.debt_strategy import router as debt_strategy_router
from src.app.routers.friend_debt import router as friend_debt_router
from src.app.routers.analytics import router as analytics_router
from src.app.routers.tax_export import router as tax_export_router
from src.app.routers.auto_label import router as auto_label_router
from src.app.routers.admin import router as admin_router
from src.app.routers.chat import router as chat_router
from src.app.routers.telegram import router as telegram_router

app.include_router(auth_router)
app.include_router(categories_router)
app.include_router(expenses_router)
app.include_router(receipts_router)
app.include_router(imports_router)
app.include_router(credit_cards_router)
app.include_router(loans_router)
app.include_router(debt_strategy_router)
app.include_router(friend_debt_router)
app.include_router(analytics_router)
app.include_router(tax_export_router)
app.include_router(auto_label_router)
app.include_router(admin_router)
app.include_router(chat_router)
app.include_router(telegram_router)


# ─── Health check ────────────────────────────────────────────────────────────


@app.get("/health", tags=["health"])
async def health_check():
    """Basic health check endpoint.

    Returns service status and configuration info. Used by load balancers,
    Docker HEALTHCHECK, and monitoring systems.
    """
    return {
        "status": "healthy",
        "service": settings.app_name,
        "version": app.version,
        "debug": settings.debug,
    }
