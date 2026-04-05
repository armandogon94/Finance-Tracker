"""Tests for authentication endpoints."""

import hashlib
import secrets
from datetime import datetime, timedelta, timezone

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.dependencies.auth import create_access_token
from src.app.models.user import RefreshToken, User


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------


async def test_register(client: AsyncClient):
    """POST /api/v1/auth/register should create a user and return tokens."""
    resp = await client.post(
        "/api/v1/auth/register",
        json={
            "email": "newuser@example.com",
            "password": "securepass123",
            "display_name": "New User",
        },
    )
    assert resp.status_code == 201

    data = resp.json()
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["token_type"] == "bearer"
    assert data["expires_in"] > 0


async def test_register_seeds_default_categories(client: AsyncClient):
    """Registration should create 9 default categories for the new user."""
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={"email": "catcheck@example.com", "password": "securepass123"},
    )
    assert reg_resp.status_code == 201
    token = reg_resp.json()["access_token"]

    # Fetch categories with the new user's token
    cat_resp = await client.get(
        "/api/v1/categories/",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert cat_resp.status_code == 200
    categories = cat_resp.json()
    assert len(categories) == 9
    names = {c["name"] for c in categories}
    assert "Food & Dining" in names
    assert "Other" in names


async def test_register_duplicate_email(client: AsyncClient):
    """Registering the same email twice should return 409 Conflict."""
    payload = {
        "email": "duplicate@example.com",
        "password": "securepass123",
        "display_name": "First User",
    }

    resp1 = await client.post("/api/v1/auth/register", json=payload)
    assert resp1.status_code == 201

    resp2 = await client.post("/api/v1/auth/register", json=payload)
    assert resp2.status_code == 409


# ---------------------------------------------------------------------------
# Login
# ---------------------------------------------------------------------------


async def test_login(client: AsyncClient):
    """Login with correct credentials should return 200 and tokens."""
    # First register
    await client.post(
        "/api/v1/auth/register",
        json={
            "email": "loginuser@example.com",
            "password": "mypassword",
            "display_name": "Login User",
        },
    )

    # Then login
    resp = await client.post(
        "/api/v1/auth/login",
        json={
            "email": "loginuser@example.com",
            "password": "mypassword",
        },
    )
    assert resp.status_code == 200

    data = resp.json()
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["token_type"] == "bearer"


async def test_login_wrong_password(client: AsyncClient):
    """Login with wrong password should return 401."""
    # Register first
    await client.post(
        "/api/v1/auth/register",
        json={
            "email": "wrongpw@example.com",
            "password": "correctpassword",
        },
    )

    # Try wrong password
    resp = await client.post(
        "/api/v1/auth/login",
        json={
            "email": "wrongpw@example.com",
            "password": "wrongpassword",
        },
    )
    assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Authenticated user info
# ---------------------------------------------------------------------------


async def test_get_me(auth_client: AsyncClient, test_user: User):
    """GET /api/v1/auth/me with a valid token should return user data."""
    resp = await auth_client.get("/api/v1/auth/me")
    assert resp.status_code == 200

    data = resp.json()
    assert data["email"] == test_user.email
    assert data["display_name"] == test_user.display_name
    assert data["is_active"] is True
    assert data["is_superuser"] is False


async def test_get_me_no_token(client: AsyncClient):
    """GET /api/v1/auth/me without a token should return 401."""
    resp = await client.get("/api/v1/auth/me")
    assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Refresh token expiry
# ---------------------------------------------------------------------------


async def test_refresh_with_expired_token(
    client: AsyncClient, test_user: User, db_session: AsyncSession
):
    """POST /api/v1/auth/refresh with an expired refresh token should return 401."""
    # Create a refresh token that expired 1 hour ago
    raw_token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(raw_token.encode()).hexdigest()
    expired_token = RefreshToken(
        user_id=test_user.id,
        token_hash=token_hash,
        expires_at=datetime.now(timezone.utc) - timedelta(hours=1),
    )
    db_session.add(expired_token)
    await db_session.commit()

    # Try to refresh with the expired token
    resp = await client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": raw_token},
    )
    assert resp.status_code == 401


async def test_refresh_with_valid_token(client: AsyncClient):
    """POST /api/v1/auth/refresh with a valid refresh token should return new tokens."""
    # Register to get a fresh refresh token
    reg_resp = await client.post(
        "/api/v1/auth/register",
        json={"email": "refresh@example.com", "password": "securepass123"},
    )
    assert reg_resp.status_code == 201
    refresh_token = reg_resp.json()["refresh_token"]

    # Use the refresh token
    resp = await client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": refresh_token},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "access_token" in data
    assert "refresh_token" in data
