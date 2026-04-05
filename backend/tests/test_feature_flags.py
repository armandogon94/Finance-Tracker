"""Tests for feature flag gating via API endpoints."""

import uuid
from datetime import datetime, timezone

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.models.feature_flag import UserFeatureFlag
from src.app.models.user import User


async def test_feature_gated_endpoint_without_flag(
    auth_client: AsyncClient,
    test_user: User,
):
    """Calling friend-debt/summary without the feature flag should return 403."""
    resp = await auth_client.get(
        "/api/v1/friend-debt/summary", params={"bank_balance": 1000}
    )
    assert resp.status_code == 403
    assert "friend_debt_calculator" in resp.json()["detail"].lower()


async def test_feature_gated_endpoint_with_flag(
    auth_client: AsyncClient,
    test_user: User,
    db_session: AsyncSession,
):
    """With the feature flag enabled, friend-debt/summary should not return 403."""
    # Create the feature flag for the test user
    flag = UserFeatureFlag(
        id=uuid.uuid4(),
        user_id=test_user.id,
        feature_name="friend_debt_calculator",
        is_enabled=True,
        enabled_by=test_user.id,
        enabled_at=datetime.now(timezone.utc),
    )
    db_session.add(flag)
    await db_session.commit()

    resp = await auth_client.get(
        "/api/v1/friend-debt/summary", params={"bank_balance": 1000}
    )
    # Should not be 403 -- may be 200 or another status depending on data,
    # but the feature gate should no longer block
    assert resp.status_code != 403


async def test_admin_toggle_flag(
    admin_client: AsyncClient,
    test_user: User,
    db_session: AsyncSession,
):
    """Admin should be able to toggle a feature flag for another user."""
    # Enable the flag
    resp = await admin_client.patch(
        f"/api/v1/admin/users/{test_user.id}/features",
        json={
            "feature_name": "friend_debt_calculator",
            "is_enabled": True,
        },
    )
    assert resp.status_code == 200

    data = resp.json()
    assert data["feature_name"] == "friend_debt_calculator"
    assert data["is_enabled"] is True
    assert data["enabled_at"] is not None

    # Verify it's stored: fetch the flags for the user
    resp2 = await admin_client.get(
        f"/api/v1/admin/users/{test_user.id}/features"
    )
    assert resp2.status_code == 200

    flags = resp2.json()
    flag_names = {f["feature_name"]: f["is_enabled"] for f in flags}
    assert flag_names.get("friend_debt_calculator") is True

    # Disable the flag
    resp3 = await admin_client.patch(
        f"/api/v1/admin/users/{test_user.id}/features",
        json={
            "feature_name": "friend_debt_calculator",
            "is_enabled": False,
        },
    )
    assert resp3.status_code == 200
    assert resp3.json()["is_enabled"] is False
