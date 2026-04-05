"""Tests for Ollama OCR extraction and updated dispatcher logic."""

import json
from unittest.mock import MagicMock, patch

import httpx
import pytest

from src.app.services.ocr import (
    _extract_json_from_text,
    extract_receipt,
    extract_receipt_ollama,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_VALID_OCR_RESPONSE = {
    "merchant_name": "Walmart Supercenter",
    "date": "2026-04-01",
    "subtotal": 42.50,
    "tax_amount": 3.40,
    "total_amount": 45.90,
    "currency": "USD",
    "items": [
        {"description": "Milk 1gal", "quantity": 1, "unit_price": 3.99},
        {"description": "Bread", "quantity": 2, "unit_price": 2.50},
    ],
    "payment_method": "credit",
    "category_suggestion": "Groceries",
}


def _mock_ollama_response(content: str) -> httpx.Response:
    """Build a fake httpx.Response mimicking Ollama /api/chat output."""
    body = json.dumps({"message": {"role": "assistant", "content": content}})
    return httpx.Response(200, json=json.loads(body))


# ---------------------------------------------------------------------------
# _extract_json_from_text
# ---------------------------------------------------------------------------


def test_extract_json_plain():
    raw = json.dumps(_VALID_OCR_RESPONSE)
    assert _extract_json_from_text(raw) == raw


def test_extract_json_with_markdown_fences():
    raw = "```json\n" + json.dumps(_VALID_OCR_RESPONSE) + "\n```"
    result = _extract_json_from_text(raw)
    parsed = json.loads(result)
    assert parsed["merchant_name"] == "Walmart Supercenter"


def test_extract_json_with_surrounding_text():
    raw = "Here is the extracted data:\n" + json.dumps(_VALID_OCR_RESPONSE) + "\nDone."
    result = _extract_json_from_text(raw)
    parsed = json.loads(result)
    assert parsed["total_amount"] == 45.90


# ---------------------------------------------------------------------------
# extract_receipt_ollama — happy path
# ---------------------------------------------------------------------------


@patch("src.app.services.ocr.settings")
@patch("src.app.services.ocr.httpx.Client")
def test_ollama_happy_path(mock_client_cls, mock_settings):
    mock_settings.ollama_base_url = "http://localhost:11434"
    mock_settings.ollama_model = "gemma4"

    mock_client = MagicMock()
    mock_client_cls.return_value.__enter__ = MagicMock(return_value=mock_client)
    mock_client_cls.return_value.__exit__ = MagicMock(return_value=False)

    mock_response = MagicMock()
    mock_response.json.return_value = {
        "message": {"content": json.dumps(_VALID_OCR_RESPONSE)}
    }
    mock_client.post.return_value = mock_response

    result = extract_receipt_ollama("base64imagedata")

    assert result["method"] == "ollama"
    assert result["confidence"] == "medium"
    assert result["needs_review"] is True
    assert result["merchant_name"] == "Walmart Supercenter"
    assert result["total_amount"] == 45.90
    assert result["category_suggestion"] == "Groceries"


@patch("src.app.services.ocr.settings")
@patch("src.app.services.ocr.httpx.Client")
def test_ollama_markdown_fenced_response(mock_client_cls, mock_settings):
    mock_settings.ollama_base_url = "http://localhost:11434"
    mock_settings.ollama_model = "gemma4"

    mock_client = MagicMock()
    mock_client_cls.return_value.__enter__ = MagicMock(return_value=mock_client)
    mock_client_cls.return_value.__exit__ = MagicMock(return_value=False)

    fenced = "```json\n" + json.dumps(_VALID_OCR_RESPONSE) + "\n```"
    mock_response = MagicMock()
    mock_response.json.return_value = {"message": {"content": fenced}}
    mock_client.post.return_value = mock_response

    result = extract_receipt_ollama("base64imagedata")

    assert "error" not in result
    assert result["merchant_name"] == "Walmart Supercenter"


# ---------------------------------------------------------------------------
# extract_receipt_ollama — error cases
# ---------------------------------------------------------------------------


@patch("src.app.services.ocr.settings")
def test_ollama_no_base_url(mock_settings):
    mock_settings.ollama_base_url = ""

    result = extract_receipt_ollama("base64imagedata")
    assert "error" in result
    assert result["method"] == "ollama"


@patch("src.app.services.ocr.settings")
@patch("src.app.services.ocr.httpx.Client")
def test_ollama_connect_error(mock_client_cls, mock_settings):
    mock_settings.ollama_base_url = "http://localhost:11434"
    mock_settings.ollama_model = "gemma4"

    mock_client = MagicMock()
    mock_client_cls.return_value.__enter__ = MagicMock(return_value=mock_client)
    mock_client_cls.return_value.__exit__ = MagicMock(return_value=False)
    mock_client.post.side_effect = httpx.ConnectError("Connection refused")

    result = extract_receipt_ollama("base64imagedata")

    assert "error" in result
    assert "Cannot connect" in result["error"]
    assert result["method"] == "ollama"


@patch("src.app.services.ocr.settings")
@patch("src.app.services.ocr.httpx.Client")
def test_ollama_timeout(mock_client_cls, mock_settings):
    mock_settings.ollama_base_url = "http://localhost:11434"
    mock_settings.ollama_model = "gemma4"

    mock_client = MagicMock()
    mock_client_cls.return_value.__enter__ = MagicMock(return_value=mock_client)
    mock_client_cls.return_value.__exit__ = MagicMock(return_value=False)
    mock_client.post.side_effect = httpx.TimeoutException("timed out")

    result = extract_receipt_ollama("base64imagedata")

    assert "error" in result
    assert "timed out" in result["error"]
    assert result["method"] == "ollama"


@patch("src.app.services.ocr.settings")
@patch("src.app.services.ocr.httpx.Client")
def test_ollama_http_error(mock_client_cls, mock_settings):
    mock_settings.ollama_base_url = "http://localhost:11434"
    mock_settings.ollama_model = "gemma4"

    mock_client = MagicMock()
    mock_client_cls.return_value.__enter__ = MagicMock(return_value=mock_client)
    mock_client_cls.return_value.__exit__ = MagicMock(return_value=False)

    mock_response = MagicMock()
    mock_response.status_code = 404
    mock_response.raise_for_status.side_effect = httpx.HTTPStatusError(
        "Not Found", request=MagicMock(), response=mock_response
    )
    mock_client.post.return_value = mock_response

    result = extract_receipt_ollama("base64imagedata")

    assert "error" in result
    assert "404" in result["error"]
    assert result["method"] == "ollama"


@patch("src.app.services.ocr.settings")
@patch("src.app.services.ocr.httpx.Client")
def test_ollama_non_json_response(mock_client_cls, mock_settings):
    mock_settings.ollama_base_url = "http://localhost:11434"
    mock_settings.ollama_model = "gemma4"

    mock_client = MagicMock()
    mock_client_cls.return_value.__enter__ = MagicMock(return_value=mock_client)
    mock_client_cls.return_value.__exit__ = MagicMock(return_value=False)

    mock_response = MagicMock()
    mock_response.json.return_value = {
        "message": {"content": "I cannot read this receipt clearly."}
    }
    mock_client.post.return_value = mock_response

    result = extract_receipt_ollama("base64imagedata")

    assert "error" in result
    assert result["method"] == "ollama"
    assert result["needs_review"] is True


# ---------------------------------------------------------------------------
# Dispatcher — ollama mode
# ---------------------------------------------------------------------------


@patch("src.app.services.ocr.extract_receipt_ollama")
@patch("src.app.services.ocr.settings")
def test_dispatcher_ollama_mode(mock_settings, mock_ollama):
    mock_settings.ocr_mode = "auto"
    mock_ollama.return_value = {**_VALID_OCR_RESPONSE, "method": "ollama"}

    result = extract_receipt(image_base64="base64data", mode="ollama")

    mock_ollama.assert_called_once_with("base64data")
    assert result["method"] == "ollama"


@patch("src.app.services.ocr.extract_receipt_ollama")
@patch("src.app.services.ocr.settings")
def test_dispatcher_ollama_mode_no_image(mock_settings, mock_ollama):
    mock_settings.ocr_mode = "auto"

    result = extract_receipt(image_base64="", mode="ollama")

    mock_ollama.assert_not_called()
    assert "error" in result


# ---------------------------------------------------------------------------
# Dispatcher — auto fallback chain
# ---------------------------------------------------------------------------


@patch("src.app.services.ocr.extract_receipt_tesseract")
@patch("src.app.services.ocr.extract_receipt_ollama")
@patch("src.app.services.ocr.extract_receipt_claude")
@patch("src.app.services.ocr.settings")
def test_auto_claude_succeeds(mock_settings, mock_claude, mock_ollama, mock_tesseract):
    """Auto mode: Claude succeeds, Ollama and Tesseract are not called."""
    mock_settings.ocr_mode = "auto"
    mock_claude.return_value = {**_VALID_OCR_RESPONSE, "method": "claude"}

    result = extract_receipt(image_base64="data", image_path="/tmp/img.jpg")

    mock_claude.assert_called_once()
    mock_ollama.assert_not_called()
    mock_tesseract.assert_not_called()
    assert result["method"] == "claude"


@patch("src.app.services.ocr.extract_receipt_tesseract")
@patch("src.app.services.ocr.extract_receipt_ollama")
@patch("src.app.services.ocr.extract_receipt_claude")
@patch("src.app.services.ocr.settings")
def test_auto_claude_fails_ollama_succeeds(
    mock_settings, mock_claude, mock_ollama, mock_tesseract
):
    """Auto mode: Claude fails, Ollama succeeds, Tesseract not called."""
    mock_settings.ocr_mode = "auto"
    mock_claude.return_value = {"error": "No API key", "method": "claude"}
    mock_ollama.return_value = {**_VALID_OCR_RESPONSE, "method": "ollama"}

    result = extract_receipt(image_base64="data", image_path="/tmp/img.jpg")

    mock_claude.assert_called_once()
    mock_ollama.assert_called_once()
    mock_tesseract.assert_not_called()
    assert result["method"] == "ollama"


@patch("src.app.services.ocr.extract_receipt_tesseract")
@patch("src.app.services.ocr.extract_receipt_ollama")
@patch("src.app.services.ocr.extract_receipt_claude")
@patch("src.app.services.ocr.settings")
def test_auto_claude_and_ollama_fail_tesseract_called(
    mock_settings, mock_claude, mock_ollama, mock_tesseract
):
    """Auto mode: Both Claude and Ollama fail, falls back to Tesseract."""
    mock_settings.ocr_mode = "auto"
    mock_claude.return_value = {"error": "No API key", "method": "claude"}
    mock_ollama.return_value = {"error": "Connection refused", "method": "ollama"}
    mock_tesseract.return_value = {
        "merchant_name": "Store",
        "method": "tesseract",
        "category_suggestion": None,
    }

    result = extract_receipt(image_base64="data", image_path="/tmp/img.jpg")

    mock_claude.assert_called_once()
    mock_ollama.assert_called_once()
    mock_tesseract.assert_called_once()
    assert result["method"] == "tesseract"


# ---------------------------------------------------------------------------
# category_suggestion field presence
# ---------------------------------------------------------------------------


@patch("src.app.services.ocr.settings")
@patch("src.app.services.ocr.httpx.Client")
def test_ollama_includes_category_suggestion(mock_client_cls, mock_settings):
    mock_settings.ollama_base_url = "http://localhost:11434"
    mock_settings.ollama_model = "gemma4"

    mock_client = MagicMock()
    mock_client_cls.return_value.__enter__ = MagicMock(return_value=mock_client)
    mock_client_cls.return_value.__exit__ = MagicMock(return_value=False)

    mock_response = MagicMock()
    mock_response.json.return_value = {
        "message": {"content": json.dumps(_VALID_OCR_RESPONSE)}
    }
    mock_client.post.return_value = mock_response

    result = extract_receipt_ollama("base64imagedata")
    assert "category_suggestion" in result
    assert result["category_suggestion"] == "Groceries"
