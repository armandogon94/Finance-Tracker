"""Tests for Telegram bot: account linking, verification, and status endpoints."""

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.models.telegram import TelegramLink
from src.app.models.user import User


class TestTelegramLink:
    async def test_generate_link_code(self, auth_client: AsyncClient):
        resp = await auth_client.post("/api/v1/telegram/link")
        assert resp.status_code == 200
        data = resp.json()
        assert "code" in data
        assert "expires_at" in data
        assert len(data["code"]) == 8  # hex(4) = 8 chars

    async def test_generate_replaces_old_codes(self, auth_client: AsyncClient):
        # Generate two codes — first should be invalidated
        resp1 = await auth_client.post("/api/v1/telegram/link")
        code1 = resp1.json()["code"]

        resp2 = await auth_client.post("/api/v1/telegram/link")
        code2 = resp2.json()["code"]

        assert code1 != code2


class TestTelegramVerify:
    async def test_verify_valid_code(
        self, auth_client: AsyncClient, bot_client: AsyncClient, test_user: User
    ):
        # Generate code via authenticated endpoint
        gen_resp = await auth_client.post("/api/v1/telegram/link")
        code = gen_resp.json()["code"]

        # Verify via bot-authenticated endpoint (bot client sends X-Bot-Secret)
        verify_resp = await bot_client.post("/api/v1/telegram/verify", json={
            "link_code": code,
            "telegram_user_id": 123456789,
            "telegram_username": "testuser",
        })
        assert verify_resp.status_code == 200
        data = verify_resp.json()
        assert data["success"] is True
        assert data["user_id"] == str(test_user.id)

    async def test_verify_invalid_code(self, bot_client: AsyncClient):
        resp = await bot_client.post("/api/v1/telegram/verify", json={
            "link_code": "INVALID123",
            "telegram_user_id": 123456789,
        })
        assert resp.status_code == 404

    async def test_verify_expired_code(
        self, auth_client: AsyncClient, bot_client: AsyncClient, db_session: AsyncSession, test_user: User
    ):
        # Create an expired link directly in DB
        link = TelegramLink(
            user_id=test_user.id,
            link_code="EXPIRED1",
            is_active=False,
            expires_at=datetime.now(timezone.utc) - timedelta(hours=1),
        )
        db_session.add(link)
        await db_session.commit()

        resp = await bot_client.post("/api/v1/telegram/verify", json={
            "link_code": "EXPIRED1",
            "telegram_user_id": 123456789,
        })
        assert resp.status_code == 410

    async def test_verify_duplicate_telegram_id(
        self, auth_client: AsyncClient, bot_client: AsyncClient, db_session: AsyncSession, test_user: User
    ):
        # First link
        gen_resp = await auth_client.post("/api/v1/telegram/link")
        code1 = gen_resp.json()["code"]
        await bot_client.post("/api/v1/telegram/verify", json={
            "link_code": code1,
            "telegram_user_id": 999888777,
            "telegram_username": "user1",
        })

        # Try to link same telegram_id to another code
        gen_resp2 = await auth_client.post("/api/v1/telegram/link")
        code2 = gen_resp2.json()["code"]
        resp = await bot_client.post("/api/v1/telegram/verify", json={
            "link_code": code2,
            "telegram_user_id": 999888777,
            "telegram_username": "user1",
        })
        assert resp.status_code == 409

    async def test_verify_missing_secret_returns_401(self, client: AsyncClient):
        """A request without X-Bot-Secret is rejected even with a valid code."""
        resp = await client.post("/api/v1/telegram/verify", json={
            "link_code": "WHATEVER",
            "telegram_user_id": 123,
        })
        assert resp.status_code == 401

    async def test_verify_wrong_secret_returns_401(self, client: AsyncClient):
        """A request with the wrong X-Bot-Secret is rejected."""
        resp = await client.post(
            "/api/v1/telegram/verify",
            json={"link_code": "WHATEVER", "telegram_user_id": 123},
            headers={"X-Bot-Secret": "this-is-not-the-secret"},
        )
        assert resp.status_code == 401


class TestTelegramLookup:
    async def test_lookup_linked_user(
        self, auth_client: AsyncClient, bot_client: AsyncClient
    ):
        # Link an account
        gen_resp = await auth_client.post("/api/v1/telegram/link")
        code = gen_resp.json()["code"]
        await bot_client.post("/api/v1/telegram/verify", json={
            "link_code": code,
            "telegram_user_id": 111222333,
            "telegram_username": "linked_user",
        })

        # Look up via bot-authenticated client
        resp = await bot_client.get("/api/v1/telegram/user/111222333")
        assert resp.status_code == 200
        data = resp.json()
        assert data["linked"] is True
        assert data["telegram_username"] == "linked_user"

    async def test_lookup_unknown_user(self, bot_client: AsyncClient):
        resp = await bot_client.get("/api/v1/telegram/user/000000000")
        assert resp.status_code == 404

    async def test_lookup_without_secret_returns_401(self, client: AsyncClient):
        resp = await client.get("/api/v1/telegram/user/111222333")
        assert resp.status_code == 401


class TestTelegramStatus:
    async def test_status_not_linked(self, auth_client: AsyncClient):
        resp = await auth_client.get("/api/v1/telegram/status")
        assert resp.status_code == 200
        assert resp.json()["linked"] is False

    async def test_status_linked(self, auth_client: AsyncClient, bot_client: AsyncClient):
        gen_resp = await auth_client.post("/api/v1/telegram/link")
        code = gen_resp.json()["code"]
        await bot_client.post("/api/v1/telegram/verify", json={
            "link_code": code,
            "telegram_user_id": 444555666,
            "telegram_username": "mybot",
        })

        resp = await auth_client.get("/api/v1/telegram/status")
        assert resp.status_code == 200
        data = resp.json()
        assert data["linked"] is True
        assert data["telegram_username"] == "mybot"


class TestTelegramUnlink:
    async def test_unlink(self, auth_client: AsyncClient, bot_client: AsyncClient):
        # Link first
        gen_resp = await auth_client.post("/api/v1/telegram/link")
        code = gen_resp.json()["code"]
        await bot_client.post("/api/v1/telegram/verify", json={
            "link_code": code,
            "telegram_user_id": 777888999,
            "telegram_username": "unlink_me",
        })

        # Unlink
        resp = await auth_client.delete("/api/v1/telegram/unlink")
        assert resp.status_code == 200
        assert resp.json()["success"] is True

        # Verify it's gone
        status_resp = await auth_client.get("/api/v1/telegram/status")
        assert status_resp.json()["linked"] is False

    async def test_unlink_not_linked(self, auth_client: AsyncClient):
        resp = await auth_client.delete("/api/v1/telegram/unlink")
        assert resp.status_code == 404
