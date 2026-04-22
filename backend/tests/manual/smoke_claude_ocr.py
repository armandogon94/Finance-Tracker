"""Manual smoke test: hit Claude Vision with a real receipt, verify the new
schema (no tax_amount/subtotal) and print the result.

Run:  uv run python -m tests.manual.smoke_claude_ocr <path-to-jpg-or-webp>
"""

from __future__ import annotations

import base64
import json
import os
import sys
from pathlib import Path

from dotenv import dotenv_values

PROJECT_ROOT = Path(__file__).resolve().parents[3]
_ENV_PATH = PROJECT_ROOT / ".env"
for _k, _v in dotenv_values(_ENV_PATH).items():
    if _v is not None and not os.environ.get(_k):
        os.environ[_k] = _v

# Import after env is loaded so settings pick up the key
from src.app.services.ocr import extract_receipt_claude  # noqa: E402


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: smoke_claude_ocr.py <image-path>")
        return 2

    img_path = Path(sys.argv[1])
    if not img_path.exists():
        print(f"file not found: {img_path}")
        return 2

    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("ANTHROPIC_API_KEY not set")
        return 2

    b64 = base64.b64encode(img_path.read_bytes()).decode()
    result = extract_receipt_claude(b64)

    print(json.dumps(result, indent=2, default=str))

    # Verify shape
    for forbidden in ("tax_amount", "subtotal"):
        if forbidden in result:
            print(f"FAIL: forbidden field {forbidden!r} present in response")
            return 1

    for required in ("merchant_name", "total_amount", "method"):
        if required not in result:
            print(f"FAIL: required field {required!r} missing from response")
            return 1

    if result.get("error"):
        print(f"FAIL: Claude returned an error: {result['error']}")
        return 1

    print("OK: schema matches, no tax/subtotal fields present")
    return 0


if __name__ == "__main__":
    sys.exit(main())
