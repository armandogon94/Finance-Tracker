"""Manual smoke test: stream a chat response from Claude via the chat service.

Run:  uv run python -m tests.manual.smoke_claude_chat
"""

from __future__ import annotations

import asyncio
import os
import sys
from pathlib import Path

from dotenv import dotenv_values

PROJECT_ROOT = Path(__file__).resolve().parents[3]
for _k, _v in dotenv_values(PROJECT_ROOT / ".env").items():
    if _v is not None and not os.environ.get(_k):
        os.environ[_k] = _v

from src.app.services.chat import classify_intent, stream_chat_response  # noqa: E402


async def main() -> int:
    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("ANTHROPIC_API_KEY not set")
        return 2

    user_msg = "What did I spend the most on this month?"

    # Fake but realistic financial context
    fake_context = {
        "current_month": {
            "total_spent": 1423.55,
            "by_category": [
                {"name": "Groceries", "total": 512.30},
                {"name": "Dining", "total": 283.00},
                {"name": "Transportation", "total": 195.20},
                {"name": "Subscriptions", "total": 89.99},
            ],
        },
        "budget_status": [
            {"category": "Groceries", "limit": 600.0, "spent": 512.30, "pct": 85},
        ],
    }

    intents = classify_intent(user_msg)
    print(f"Intents detected: {intents}")
    print(f"Streaming response for: {user_msg!r}")
    print("-" * 60)

    chunk_count = 0
    total_chars = 0
    async for chunk in stream_chat_response(
        user_message=user_msg,
        conversation_history=[],
        financial_context=fake_context,
        model="haiku",
    ):
        sys.stdout.write(chunk)
        sys.stdout.flush()
        chunk_count += 1
        total_chars += len(chunk)

    print()
    print("-" * 60)
    print(f"stream chunks: {chunk_count}, total chars: {total_chars}")

    if chunk_count == 0 or total_chars < 10:
        print("FAIL: empty or suspiciously short response")
        return 1

    print("OK: stream produced a usable response")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
