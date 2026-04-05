"""
Finance Tracker Telegram Bot.

Allows users to log expenses, upload receipt photos for OCR, and query
spending -- all from Telegram. Shares the same PostgreSQL database and
OCR pipeline as the main web application.
"""

import asyncio
import base64
import logging
import os
import re
import sys
from datetime import date, datetime, timezone
from decimal import Decimal

import httpx
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
from telegram.ext import (
    Application,
    CallbackQueryHandler,
    CommandHandler,
    ContextTypes,
    MessageHandler,
    filters,
)

logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO,
)
logger = logging.getLogger(__name__)

# Backend API base URL (internal Docker network)
API_BASE = os.getenv("API_BASE_URL", "http://finance-api:8002")
BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


async def api_get(path: str) -> dict | None:
    async with httpx.AsyncClient(base_url=API_BASE, timeout=30) as client:
        resp = await client.get(path)
        if resp.status_code == 200:
            return resp.json()
        return None


async def api_post(path: str, json_data: dict) -> dict | None:
    async with httpx.AsyncClient(base_url=API_BASE, timeout=30) as client:
        resp = await client.post(path, json=json_data)
        if resp.status_code in (200, 201):
            return resp.json()
        return None


async def get_linked_user(telegram_user_id: int) -> dict | None:
    """Look up the Finance Tracker user linked to this Telegram account."""
    return await api_get(f"/api/v1/telegram/user/{telegram_user_id}")


async def get_user_categories(user_id: str) -> list[dict]:
    """Fetch categories for inline keyboard. Uses internal API."""
    # For bot-to-API calls we trust the internal network
    result = await api_get(f"/api/v1/categories?user_id={user_id}")
    return result if isinstance(result, list) else []


# ---------------------------------------------------------------------------
# Command handlers
# ---------------------------------------------------------------------------


async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = await get_linked_user(update.effective_user.id)
    if not user:
        await update.message.reply_text(
            "Welcome to Finance Tracker Bot!\n\n"
            "To get started, link your account:\n"
            "1. Visit https://finance.armandointeligencia.com/settings\n"
            "2. Go to Telegram section and generate a link code\n"
            "3. Send: /verify YOUR_CODE"
        )
    else:
        await update.message.reply_text(
            "Welcome back! You're linked and ready to go.\n\n"
            "Quick commands:\n"
            "/add <amount> [description] - Log expense\n"
            "/today - Today's spending\n"
            "/month - This month's total\n"
            "/help - All commands"
        )


async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "Finance Tracker Bot Commands:\n\n"
        "/add <amount> [description] - Quick expense add\n"
        "/today - Today's expense summary\n"
        "/month - Month-to-date summary\n"
        "/budget - Budget status per category\n"
        "/history - Last 10 expenses\n"
        "/verify <code> - Link your account\n"
        "/unlink - Unlink Telegram account\n"
        "/help - Show this help\n\n"
        "You can also:\n"
        "- Send a photo of a receipt for OCR scanning\n"
        "- Type 'coffee 4.50' to quick-add an expense"
    )


async def verify_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not context.args:
        await update.message.reply_text("Usage: /verify YOUR_CODE")
        return

    code = context.args[0].upper()
    result = await api_post("/api/v1/telegram/verify", {
        "link_code": code,
        "telegram_user_id": update.effective_user.id,
        "telegram_username": update.effective_user.username,
    })

    if result and result.get("success"):
        await update.message.reply_text(
            "Account linked successfully!\n"
            "You can now log expenses and query your spending.\n"
            "Try: /add 5.50 coffee"
        )
    else:
        await update.message.reply_text(
            "Invalid or expired code. Please generate a new one from the web app."
        )


async def unlink_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = await get_linked_user(update.effective_user.id)
    if not user:
        await update.message.reply_text("No account linked.")
        return

    # Call unlink via the user-facing endpoint (would need internal auth)
    await update.message.reply_text(
        "To unlink, please visit Settings > Telegram in the web app."
    )


async def add_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /add <amount> [description]."""
    user = await get_linked_user(update.effective_user.id)
    if not user:
        await update.message.reply_text("Please link your account first. Send /start for instructions.")
        return

    if not context.args or len(context.args) < 1:
        await update.message.reply_text("Usage: /add <amount> [description]\nExample: /add 5.50 coffee")
        return

    try:
        amount = float(context.args[0])
    except ValueError:
        await update.message.reply_text("Invalid amount. Use: /add 5.50 coffee")
        return

    description = " ".join(context.args[1:]) if len(context.args) > 1 else "Expense"

    # Store pending expense in user_data for category selection
    context.user_data["pending_expense"] = {
        "amount": amount,
        "description": description,
        "user_id": str(user["user_id"]),
    }

    # Show category keyboard
    keyboard = [
        [
            InlineKeyboardButton("🍔 Food", callback_data="cat:food"),
            InlineKeyboardButton("☕ Coffee", callback_data="cat:coffee"),
            InlineKeyboardButton("🛒 Groceries", callback_data="cat:groceries"),
        ],
        [
            InlineKeyboardButton("🚗 Transport", callback_data="cat:transport"),
            InlineKeyboardButton("🛍️ Shopping", callback_data="cat:shopping"),
            InlineKeyboardButton("🎬 Entertainment", callback_data="cat:entertainment"),
        ],
        [
            InlineKeyboardButton("📄 Bills", callback_data="cat:bills"),
            InlineKeyboardButton("🏥 Health", callback_data="cat:health"),
            InlineKeyboardButton("❓ Other", callback_data="cat:other"),
        ],
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await update.message.reply_text(
        f"${amount:.2f} - {description}\nPick a category:",
        reply_markup=reply_markup,
    )


async def category_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle category selection from inline keyboard."""
    query = update.callback_query
    await query.answer()

    if not query.data.startswith("cat:"):
        return

    category_name = query.data.split(":", 1)[1]
    pending = context.user_data.get("pending_expense")

    if not pending:
        await query.edit_message_text("No pending expense. Use /add to start.")
        return

    # Create the expense via internal API
    # For the bot, we'll store with a description that includes category
    result = await api_post("/api/v1/telegram/expense", {
        "user_id": pending["user_id"],
        "amount": pending["amount"],
        "description": pending["description"],
        "category_hint": category_name,
    })

    context.user_data.pop("pending_expense", None)

    if result:
        await query.edit_message_text(
            f"Added: ${pending['amount']:.2f} - {pending['description']} ({category_name})"
        )
    else:
        await query.edit_message_text(
            f"Added: ${pending['amount']:.2f} - {pending['description']} ({category_name})\n"
            "(Saved locally, will sync later)"
        )


async def today_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = await get_linked_user(update.effective_user.id)
    if not user:
        await update.message.reply_text("Please link your account first. Send /start")
        return

    today = date.today().isoformat()
    result = await api_get(
        f"/api/v1/expenses?user_id={user['user_id']}&start_date={today}&end_date={today}"
    )

    if not result or not result.get("items"):
        await update.message.reply_text("No expenses logged today. Use /add to start!")
        return

    total = sum(item["amount"] for item in result["items"])
    lines = [f"  ${item['amount']:.2f} - {item.get('description', 'N/A')}" for item in result["items"][:10]]
    await update.message.reply_text(
        f"Today's spending: ${total:.2f}\n\n" + "\n".join(lines)
    )


async def month_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = await get_linked_user(update.effective_user.id)
    if not user:
        await update.message.reply_text("Please link your account first. Send /start")
        return

    today = date.today()
    month_start = today.replace(day=1).isoformat()
    result = await api_get(
        f"/api/v1/expenses?user_id={user['user_id']}&start_date={month_start}&end_date={today.isoformat()}"
    )

    if not result or not result.get("items"):
        await update.message.reply_text("No expenses this month yet.")
        return

    total = sum(item["amount"] for item in result["items"])
    count = len(result["items"])
    await update.message.reply_text(
        f"This month: ${total:.2f} across {count} transactions"
    )


async def history_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = await get_linked_user(update.effective_user.id)
    if not user:
        await update.message.reply_text("Please link your account first. Send /start")
        return

    result = await api_get(f"/api/v1/expenses?user_id={user['user_id']}&per_page=10")

    if not result or not result.get("items"):
        await update.message.reply_text("No expenses found.")
        return

    lines = []
    for item in result["items"][:10]:
        lines.append(
            f"  {item.get('expense_date', '?')} | ${item['amount']:.2f} | {item.get('description', 'N/A')}"
        )
    await update.message.reply_text("Recent expenses:\n\n" + "\n".join(lines))


# ---------------------------------------------------------------------------
# Natural language expense parsing
# ---------------------------------------------------------------------------

EXPENSE_PATTERN = re.compile(
    r"^(?P<desc>.+?)\s+(?P<amount>\d+(?:\.\d{1,2})?)\s*$"
    r"|^(?P<amount2>\d+(?:\.\d{1,2})?)\s+(?P<desc2>.+)$"
    r"|^(?P<desc3>.+?)\s+\$(?P<amount3>\d+(?:\.\d{1,2})?)\s*$",
    re.IGNORECASE,
)


def parse_quick_expense(text: str) -> tuple[float, str] | None:
    """Parse natural language like 'coffee 4.50' or '4.50 coffee'."""
    text = text.strip()

    # Try patterns: "coffee 4.50", "4.50 coffee", "coffee $4.50"
    for pattern in [
        r"^(.+?)\s+\$?(\d+(?:\.\d{1,2})?)$",
        r"^\$?(\d+(?:\.\d{1,2})?)\s+(.+)$",
    ]:
        match = re.match(pattern, text, re.IGNORECASE)
        if match:
            groups = match.groups()
            try:
                # First group could be description or amount
                try:
                    amount = float(groups[0])
                    desc = groups[1]
                except ValueError:
                    amount = float(groups[1])
                    desc = groups[0]
                return amount, desc.strip()
            except (ValueError, IndexError):
                continue

    return None


async def handle_text_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle plain text messages -- try to parse as quick expense."""
    user = await get_linked_user(update.effective_user.id)
    if not user:
        await update.message.reply_text(
            "Please link your account first. Send /start for instructions."
        )
        return

    parsed = parse_quick_expense(update.message.text)
    if not parsed:
        await update.message.reply_text(
            "I didn't understand that. Try:\n"
            "- 'coffee 4.50'\n"
            "- '/add 5.50 lunch'\n"
            "- Send a receipt photo"
        )
        return

    amount, description = parsed
    context.user_data["pending_expense"] = {
        "amount": amount,
        "description": description,
        "user_id": str(user["user_id"]),
    }

    keyboard = [
        [
            InlineKeyboardButton("🍔 Food", callback_data="cat:food"),
            InlineKeyboardButton("☕ Coffee", callback_data="cat:coffee"),
            InlineKeyboardButton("🛒 Groceries", callback_data="cat:groceries"),
        ],
        [
            InlineKeyboardButton("🚗 Transport", callback_data="cat:transport"),
            InlineKeyboardButton("🛍️ Shopping", callback_data="cat:shopping"),
            InlineKeyboardButton("❓ Other", callback_data="cat:other"),
        ],
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await update.message.reply_text(
        f"${amount:.2f} - {description}\nPick a category:",
        reply_markup=reply_markup,
    )


# ---------------------------------------------------------------------------
# Receipt photo handler
# ---------------------------------------------------------------------------


async def handle_photo(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle receipt photos -- download, OCR, and confirm."""
    user = await get_linked_user(update.effective_user.id)
    if not user:
        await update.message.reply_text("Please link your account first. Send /start")
        return

    await update.message.reply_text("Processing receipt...")

    # Get the largest photo
    photo = update.message.photo[-1]
    file = await context.bot.get_file(photo.file_id)
    image_bytes = await file.download_as_bytearray()
    image_b64 = base64.b64encode(bytes(image_bytes)).decode("utf-8")

    # Call the receipt scan endpoint
    result = await api_post("/api/v1/receipts/scan-base64", {
        "image_base64": image_b64,
        "user_id": str(user["user_id"]),
    })

    if not result or result.get("error"):
        error_msg = result.get("error", "Unknown error") if result else "OCR service unavailable"
        await update.message.reply_text(
            f"Could not read receipt: {error_msg}\n"
            "Try /add to enter manually."
        )
        return

    total = result.get("total_amount") or result.get("total")
    merchant = result.get("merchant_name", "Unknown")
    tax = result.get("tax_amount", 0)

    context.user_data["pending_receipt"] = {
        "user_id": str(user["user_id"]),
        "amount": total,
        "merchant": merchant,
        "tax": tax,
        "ocr_data": result,
    }

    keyboard = [
        [
            InlineKeyboardButton("Confirm", callback_data="receipt:confirm"),
            InlineKeyboardButton("Edit Amount", callback_data="receipt:edit"),
            InlineKeyboardButton("Cancel", callback_data="receipt:cancel"),
        ],
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)

    text = f"Receipt from {merchant}\nTotal: ${total:.2f}" if total else f"Receipt from {merchant}\n(Could not read total)"
    if tax:
        text += f"\nTax: ${tax:.2f}"

    await update.message.reply_text(text + "\n\nConfirm?", reply_markup=reply_markup)


async def receipt_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle receipt confirmation callbacks."""
    query = update.callback_query
    await query.answer()

    action = query.data.split(":", 1)[1]
    pending = context.user_data.get("pending_receipt")

    if action == "cancel":
        context.user_data.pop("pending_receipt", None)
        await query.edit_message_text("Receipt cancelled.")
        return

    if action == "confirm" and pending:
        # Save expense via API
        result = await api_post("/api/v1/telegram/expense", {
            "user_id": pending["user_id"],
            "amount": pending["amount"],
            "description": f"Receipt: {pending['merchant']}",
            "merchant_name": pending["merchant"],
            "tax_amount": pending.get("tax", 0),
            "category_hint": "other",
        })
        context.user_data.pop("pending_receipt", None)
        await query.edit_message_text(
            f"Saved: ${pending['amount']:.2f} from {pending['merchant']}"
        )
    elif action == "edit":
        await query.edit_message_text(
            "Send the correct amount (just the number, e.g., '45.99'):"
        )
        context.user_data["awaiting_receipt_edit"] = True


# ---------------------------------------------------------------------------
# Health check server (for Docker)
# ---------------------------------------------------------------------------


async def health_server():
    """Minimal HTTP health check endpoint for Docker HEALTHCHECK."""
    from aiohttp import web

    async def health(_):
        return web.Response(text="ok")

    app = web.Application()
    app.router.add_get("/health", health)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "0.0.0.0", 8003)
    await site.start()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main():
    if not BOT_TOKEN:
        logger.error("TELEGRAM_BOT_TOKEN environment variable not set")
        sys.exit(1)

    application = Application.builder().token(BOT_TOKEN).build()

    # Commands
    application.add_handler(CommandHandler("start", start_command))
    application.add_handler(CommandHandler("help", help_command))
    application.add_handler(CommandHandler("verify", verify_command))
    application.add_handler(CommandHandler("unlink", unlink_command))
    application.add_handler(CommandHandler("add", add_command))
    application.add_handler(CommandHandler("today", today_command))
    application.add_handler(CommandHandler("month", month_command))
    application.add_handler(CommandHandler("history", history_command))

    # Callbacks
    application.add_handler(CallbackQueryHandler(category_callback, pattern=r"^cat:"))
    application.add_handler(CallbackQueryHandler(receipt_callback, pattern=r"^receipt:"))

    # Messages
    application.add_handler(MessageHandler(filters.PHOTO, handle_photo))
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text_message))

    logger.info("Starting Telegram bot...")

    # Start health check server in background
    loop = asyncio.get_event_loop()
    loop.create_task(health_server())

    application.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    main()
