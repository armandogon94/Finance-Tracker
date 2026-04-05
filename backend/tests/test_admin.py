"""Tests for admin endpoints (users, feature flags, system stats).

Uses admin_client for superuser access and auth_client for non-admin tests.
"""

import uuid

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.models.user import User


# ---------------------------------------------------------------------------
# List users
# ---------------------------------------------------------------------------


async def test_list_users_as_admin(admin_client: AsyncClient, admin_user: User):
    """GET /api/v1/admin/users as superuser returns user list."""
    resp = await admin_client.get("/api/v1/admin/users")
    assert resp.status_code == 200

    data = resp.json()
    assert isinstance(data, list)
    assert len(data) >= 1

    # The admin user should be in the list
    emails = [u["email"] for u in data]
    assert "admin@example.com" in emails


async def test_list_users_as_non_admin(auth_client: AsyncClient, test_user: User):
    """GET /api/v1/admin/users as regular user returns 403."""
    resp = await auth_client.get("/api/v1/admin/users")
    assert resp.status_code == 403


async def test_list_users_unauthenticated(client: AsyncClient):
    """GET /api/v1/admin/users without auth returns 401."""
    resp = await client.get("/api/v1/admin/users")
    assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Get specific user
# ---------------------------------------------------------------------------


async def test_get_user_as_admin(admin_client: AsyncClient, admin_user: User, test_user: User):
    """GET /api/v1/admin/users/{id} returns user details."""
    resp = await admin_client.get(f"/api/v1/admin/users/{test_user.id}")
    assert resp.status_code == 200

    data = resp.json()
    assert data["email"] == "test@example.com"
    assert data["display_name"] == "Test User"
    assert data["is_superuser"] is False


async def test_get_user_not_found(admin_client: AsyncClient, admin_user: User):
    """GET /api/v1/admin/users/{unknown_id} returns 404."""
    fake_id = uuid.uuid4()
    resp = await admin_client.get(f"/api/v1/admin/users/{fake_id}")
    assert resp.status_code == 404


async def test_get_user_as_non_admin(auth_client: AsyncClient, test_user: User):
    """Regular users cannot view other users via admin endpoint."""
    resp = await auth_client.get(f"/api/v1/admin/users/{test_user.id}")
    assert resp.status_code == 403


# ---------------------------------------------------------------------------
# Toggle user active
# ---------------------------------------------------------------------------


async def test_toggle_user_active(admin_client: AsyncClient, admin_user: User, test_user: User):
    """PATCH /api/v1/admin/users/{id} toggles is_active."""
    # test_user starts active
    resp = await admin_client.patch(f"/api/v1/admin/users/{test_user.id}")
    assert resp.status_code == 200
    data = resp.json()
    assert data["is_active"] is False

    # Toggle again to reactivate
    resp2 = await admin_client.patch(f"/api/v1/admin/users/{test_user.id}")
    assert resp2.status_code == 200
    assert resp2.json()["is_active"] is True


async def test_toggle_self_forbidden(admin_client: AsyncClient, admin_user: User):
    """Admin cannot deactivate their own account."""
    resp = await admin_client.patch(f"/api/v1/admin/users/{admin_user.id}")
    assert resp.status_code == 400
    assert "own account" in resp.json()["detail"].lower()


async def test_toggle_user_not_found(admin_client: AsyncClient, admin_user: User):
    """Toggle for non-existent user returns 404."""
    fake_id = uuid.uuid4()
    resp = await admin_client.patch(f"/api/v1/admin/users/{fake_id}")
    assert resp.status_code == 404


async def test_toggle_user_as_non_admin(auth_client: AsyncClient, test_user: User):
    """Regular users cannot toggle user status."""
    resp = await auth_client.patch(f"/api/v1/admin/users/{test_user.id}")
    assert resp.status_code == 403


# ---------------------------------------------------------------------------
# Feature flags
# ---------------------------------------------------------------------------


async def test_get_user_features_empty(
    admin_client: AsyncClient, admin_user: User, test_user: User
):
    """Feature flags for a user with none set returns empty list."""
    resp = await admin_client.get(f"/api/v1/admin/users/{test_user.id}/features")
    assert resp.status_code == 200
    assert resp.json() == []


async def test_toggle_feature_flag_create(
    admin_client: AsyncClient, admin_user: User, test_user: User
):
    """PATCH feature flag creates a new flag record when it doesn't exist."""
    resp = await admin_client.patch(
        f"/api/v1/admin/users/{test_user.id}/features",
        json={"feature_name": "friend_debt_calculator", "is_enabled": True},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["feature_name"] == "friend_debt_calculator"
    assert data["is_enabled"] is True
    assert data["enabled_at"] is not None


async def test_toggle_feature_flag_disable(
    admin_client: AsyncClient, admin_user: User, test_user: User
):
    """Enable then disable a feature flag; enabled_at should be null when disabled."""
    # Enable
    await admin_client.patch(
        f"/api/v1/admin/users/{test_user.id}/features",
        json={"feature_name": "hidden_categories", "is_enabled": True},
    )

    # Disable
    resp = await admin_client.patch(
        f"/api/v1/admin/users/{test_user.id}/features",
        json={"feature_name": "hidden_categories", "is_enabled": False},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["is_enabled"] is False
    assert data["enabled_at"] is None


async def test_list_features_after_toggle(
    admin_client: AsyncClient, admin_user: User, test_user: User
):
    """After toggling, feature appears in the list endpoint."""
    await admin_client.patch(
        f"/api/v1/admin/users/{test_user.id}/features",
        json={"feature_name": "friend_debt_calculator", "is_enabled": True},
    )

    resp = await admin_client.get(f"/api/v1/admin/users/{test_user.id}/features")
    assert resp.status_code == 200
    flags = resp.json()
    assert len(flags) >= 1
    names = [f["feature_name"] for f in flags]
    assert "friend_debt_calculator" in names


async def test_feature_flag_nonexistent_user(admin_client: AsyncClient, admin_user: User):
    """Feature flag operations on non-existent user return 404."""
    fake_id = uuid.uuid4()
    resp = await admin_client.get(f"/api/v1/admin/users/{fake_id}/features")
    assert resp.status_code == 404

    resp2 = await admin_client.patch(
        f"/api/v1/admin/users/{fake_id}/features",
        json={"feature_name": "test", "is_enabled": True},
    )
    assert resp2.status_code == 404


async def test_feature_flags_as_non_admin(auth_client: AsyncClient, test_user: User):
    """Regular users cannot access feature flag endpoints."""
    resp = await auth_client.get(f"/api/v1/admin/users/{test_user.id}/features")
    assert resp.status_code == 403

    resp2 = await auth_client.patch(
        f"/api/v1/admin/users/{test_user.id}/features",
        json={"feature_name": "test", "is_enabled": True},
    )
    assert resp2.status_code == 403


# ---------------------------------------------------------------------------
# System stats
# ---------------------------------------------------------------------------


async def test_system_stats(admin_client: AsyncClient, admin_user: User):
    """GET /api/v1/admin/stats returns aggregate system statistics."""
    resp = await admin_client.get("/api/v1/admin/stats")
    assert resp.status_code == 200

    data = resp.json()
    assert "total_users" in data
    assert "active_users" in data
    assert "total_expenses" in data
    assert "total_receipts" in data
    assert "total_debt_items" in data
    # At minimum the admin user exists
    assert data["total_users"] >= 1
    assert data["active_users"] >= 1


async def test_system_stats_as_non_admin(auth_client: AsyncClient, test_user: User):
    """Regular users cannot view system stats."""
    resp = await auth_client.get("/api/v1/admin/stats")
    assert resp.status_code == 403


async def test_system_stats_unauthenticated(client: AsyncClient):
    """Unauthenticated access to stats returns 401."""
    resp = await client.get("/api/v1/admin/stats")
    assert resp.status_code == 401
