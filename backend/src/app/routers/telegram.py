"""
Telegram bot account linking router.

Provides endpoints for generating link codes, verifying accounts,
and managing Telegram connections from the web app.
"""

import secrets
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.database import get_db
from src.app.dependencies.auth import get_current_user
from src.app.models.telegram import TelegramLink
from src.app.models.user import User
from src.app.schemas.telegram import (
    TelegramLinkResponse,
    TelegramStatusResponse,
    TelegramUnlinkResponse,
    TelegramVerifyRequest,
    TelegramVerifyResponse,
    TelegramUserResponse,
)

router = APIRouter(prefix="/api/v1/telegram", tags=["telegram"])


@router.post("/link", response_model=TelegramLinkResponse)
async def generate_link_code(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Generate a one-time code for linking a Telegram account."""
    # Invalidate any existing unused codes for this user
    existing = await db.execute(
        select(TelegramLink).where(
            TelegramLink.user_id == current_user.id,
            TelegramLink.is_active == False,  # noqa: E712
        )
    )
    for old_link in existing.scalars().all():
        await db.delete(old_link)

    # Generate new code
    code = secrets.token_hex(4).upper()  # e.g., "A1B2C3D4"
    expires_at = datetime.now(timezone.utc) + timedelta(hours=24)

    link = TelegramLink(
        user_id=current_user.id,
        link_code=code,
        is_active=False,
        expires_at=expires_at,
    )
    db.add(link)
    await db.commit()

    return TelegramLinkResponse(code=code, expires_at=expires_at)


@router.post("/verify", response_model=TelegramVerifyResponse)
async def verify_link_code(
    data: TelegramVerifyRequest,
    db: AsyncSession = Depends(get_db),
):
    """Verify a link code sent from the Telegram bot. Called by the bot, not the web app."""
    result = await db.execute(
        select(TelegramLink).where(
            TelegramLink.link_code == data.link_code,
            TelegramLink.is_active == False,  # noqa: E712
        )
    )
    link = result.scalar_one_or_none()

    if not link:
        raise HTTPException(status_code=404, detail="Invalid or expired link code")

    # Compare as naive datetimes to handle SQLite (no tz) vs PostgreSQL (tz-aware)
    expires = link.expires_at.replace(tzinfo=None) if link.expires_at else None
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    if expires and expires < now:
        await db.delete(link)
        await db.commit()
        raise HTTPException(status_code=410, detail="Link code has expired")

    # Check if this telegram_user_id is already linked to another account
    existing = await db.execute(
        select(TelegramLink).where(
            TelegramLink.telegram_user_id == data.telegram_user_id,
            TelegramLink.is_active == True,  # noqa: E712
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(
            status_code=409,
            detail="This Telegram account is already linked to another user",
        )

    # Activate the link
    link.telegram_user_id = data.telegram_user_id
    link.telegram_username = data.telegram_username
    link.is_active = True
    link.link_code = None  # Clear used code
    link.linked_at = datetime.now(timezone.utc)
    await db.commit()

    return TelegramVerifyResponse(success=True, user_id=link.user_id)


@router.get("/user/{telegram_user_id}", response_model=TelegramUserResponse)
async def get_user_by_telegram_id(
    telegram_user_id: int,
    db: AsyncSession = Depends(get_db),
):
    """Look up a Finance Tracker user by their Telegram user ID. Called by the bot."""
    result = await db.execute(
        select(TelegramLink).where(
            TelegramLink.telegram_user_id == telegram_user_id,
            TelegramLink.is_active == True,  # noqa: E712
        )
    )
    link = result.scalar_one_or_none()

    if not link:
        raise HTTPException(status_code=404, detail="No linked account found")

    return TelegramUserResponse(
        user_id=link.user_id,
        linked=True,
        telegram_username=link.telegram_username,
    )


@router.get("/status", response_model=TelegramStatusResponse)
async def get_link_status(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get current user's Telegram link status."""
    result = await db.execute(
        select(TelegramLink).where(
            TelegramLink.user_id == current_user.id,
            TelegramLink.is_active == True,  # noqa: E712
        )
    )
    link = result.scalar_one_or_none()

    if not link:
        return TelegramStatusResponse(linked=False)

    return TelegramStatusResponse(
        linked=True,
        telegram_username=link.telegram_username,
        linked_at=link.linked_at,
    )


@router.delete("/unlink", response_model=TelegramUnlinkResponse)
async def unlink_telegram(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Unlink the current user's Telegram account."""
    result = await db.execute(
        select(TelegramLink).where(
            TelegramLink.user_id == current_user.id,
            TelegramLink.is_active == True,  # noqa: E712
        )
    )
    link = result.scalar_one_or_none()

    if not link:
        raise HTTPException(status_code=404, detail="No Telegram account linked")

    await db.delete(link)
    await db.commit()

    return TelegramUnlinkResponse(success=True)
