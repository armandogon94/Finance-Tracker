"""Tests for the per-user sliding-window rate limiter."""

from __future__ import annotations

import uuid
from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException

from src.app.dependencies.rate_limit import rate_limit, reset_rate_limits


@pytest.fixture(autouse=True)
def _reset_buckets():
    reset_rate_limits()
    yield
    reset_rate_limits()


def _fake_user(uid: uuid.UUID | None = None) -> MagicMock:
    user = MagicMock()
    user.id = uid or uuid.uuid4()
    return user


@pytest.mark.asyncio
async def test_rate_limit_allows_under_cap():
    limiter = rate_limit(max_requests=3, window_seconds=60.0, bucket="test")
    user = _fake_user()

    # Three calls within the cap — all succeed silently.
    for _ in range(3):
        await limiter(current_user=user)


@pytest.mark.asyncio
async def test_rate_limit_blocks_over_cap():
    limiter = rate_limit(max_requests=3, window_seconds=60.0, bucket="test")
    user = _fake_user()

    for _ in range(3):
        await limiter(current_user=user)

    with pytest.raises(HTTPException) as excinfo:
        await limiter(current_user=user)

    assert excinfo.value.status_code == 429
    assert "Retry-After" in excinfo.value.headers


@pytest.mark.asyncio
async def test_rate_limit_isolated_per_user():
    limiter = rate_limit(max_requests=1, window_seconds=60.0, bucket="test")
    alice = _fake_user()
    bob = _fake_user()

    await limiter(current_user=alice)
    # Bob should still be allowed even though Alice is maxed out
    await limiter(current_user=bob)

    # Alice hitting again should 429
    with pytest.raises(HTTPException) as excinfo:
        await limiter(current_user=alice)
    assert excinfo.value.status_code == 429


@pytest.mark.asyncio
async def test_rate_limit_isolated_per_bucket():
    chat_limiter = rate_limit(max_requests=1, window_seconds=60.0, bucket="chat")
    ocr_limiter = rate_limit(max_requests=1, window_seconds=60.0, bucket="ocr")
    user = _fake_user()

    # Each bucket has its own counter
    await chat_limiter(current_user=user)
    await ocr_limiter(current_user=user)

    # Second call on either bucket should 429
    with pytest.raises(HTTPException):
        await chat_limiter(current_user=user)
    with pytest.raises(HTTPException):
        await ocr_limiter(current_user=user)


@pytest.mark.asyncio
async def test_rate_limit_window_decays(monkeypatch):
    """After the window passes, the oldest entries drop out and new calls succeed."""
    import src.app.dependencies.rate_limit as rl

    fake_now = [100.0]

    def _monotonic() -> float:
        return fake_now[0]

    monkeypatch.setattr(rl.time, "monotonic", _monotonic)

    limiter = rate_limit(max_requests=2, window_seconds=10.0, bucket="test")
    user = _fake_user()

    await limiter(current_user=user)
    await limiter(current_user=user)

    with pytest.raises(HTTPException):
        await limiter(current_user=user)

    # Advance clock past the window
    fake_now[0] += 11.0
    # Now the old timestamps should be evicted and the call should succeed
    await limiter(current_user=user)
