"""Per-user sliding-window rate limiting.

Keeps a bounded in-memory deque of recent request timestamps per
(user_id, bucket_key). Sized for a single-process deployment serving a
handful of authenticated users — fine for this app, not a distributed
API gateway.
"""

from __future__ import annotations

import asyncio
import time
from collections import deque

from fastapi import Depends, HTTPException, status

from src.app.dependencies.auth import get_current_user
from src.app.models.user import User

_BucketKey = tuple[str, str]  # (user_id, bucket_name)
_buckets: dict[_BucketKey, deque[float]] = {}
_lock = asyncio.Lock()


def rate_limit(max_requests: int, window_seconds: float, bucket: str):
    """Build a FastAPI dependency that enforces a per-user sliding window.

    Args:
        max_requests:   Requests allowed per window.
        window_seconds: Size of the rolling window.
        bucket:         Logical bucket name (separate counters per bucket).

    Raises:
        HTTPException(429) when the caller exceeds the limit.
    """

    async def _enforce(current_user: User = Depends(get_current_user)) -> None:
        now = time.monotonic()
        key: _BucketKey = (str(current_user.id), bucket)

        async with _lock:
            q = _buckets.setdefault(key, deque())
            while q and now - q[0] > window_seconds:
                q.popleft()

            if len(q) >= max_requests:
                retry_after = max(1, int(window_seconds - (now - q[0])) + 1)
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail=(
                        f"Rate limit exceeded for '{bucket}' "
                        f"({max_requests}/{int(window_seconds)}s). "
                        f"Retry in {retry_after}s."
                    ),
                    headers={"Retry-After": str(retry_after)},
                )

            q.append(now)

    return _enforce


def reset_rate_limits() -> None:
    """Test hook: wipe all in-memory buckets."""
    _buckets.clear()
