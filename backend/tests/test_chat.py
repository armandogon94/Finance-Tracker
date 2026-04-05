"""Tests for AI Finance Chat: conversations, messages, intent classification, and financial data retrieval."""

import uuid
from unittest.mock import AsyncMock, patch

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from src.app.models.chat import ChatConversation, ChatMessage
from src.app.models.expense import Expense
from src.app.models.category import Category
from src.app.models.user import User
from src.app.services.chat import classify_intent, get_financial_context


# ─── Intent Classification ──────────────────────────────────────────────────


class TestIntentClassification:
    def test_spending_intent(self):
        assert "spending" in classify_intent("How much did I spend on groceries?")

    def test_budget_intent(self):
        assert "budget" in classify_intent("Am I on track with my budget?")

    def test_debt_intent(self):
        assert "debt" in classify_intent("What's the fastest way to pay off my credit card?")

    def test_category_intent(self):
        assert "category" in classify_intent("Show me my groceries spending")

    def test_trend_intent(self):
        assert "trend" in classify_intent("Compare my spending month over month")

    def test_multiple_intents(self):
        intents = classify_intent("How much did I spend on food and am I on track with my budget?")
        assert "spending" in intents
        assert "budget" in intents

    def test_general_fallback(self):
        assert classify_intent("Hello there") == ["general"]

    def test_spanish_spending(self):
        assert "spending" in classify_intent("Cuánto gasté este mes?")

    def test_spanish_debt(self):
        assert "debt" in classify_intent("Cuánta deuda tengo en mi tarjeta?")


# ─── Financial Data Retrieval ────────────────────────────────────────────────


class TestFinancialDataRetrieval:
    @pytest.fixture
    async def user_with_data(self, db_session: AsyncSession, test_user: User):
        """Create test user with expenses and categories."""
        from datetime import date

        cat = Category(
            id=uuid.uuid4(),
            user_id=test_user.id,
            name="Food",
            monthly_budget=300.0,
        )
        db_session.add(cat)

        expenses = [
            Expense(
                id=uuid.uuid4(),
                user_id=test_user.id,
                category_id=cat.id,
                amount=25.50,
                description="Lunch",
                merchant_name="Chipotle",
                expense_date=date.today(),
            ),
            Expense(
                id=uuid.uuid4(),
                user_id=test_user.id,
                category_id=cat.id,
                amount=85.20,
                description="Groceries",
                merchant_name="Whole Foods",
                expense_date=date.today(),
            ),
        ]
        for e in expenses:
            db_session.add(e)
        await db_session.commit()

        return test_user

    async def test_spending_context(self, db_session: AsyncSession, user_with_data: User):
        context = await get_financial_context(user_with_data.id, ["spending"], db_session)
        assert "current_month_spending" in context
        assert context["current_month_spending"]["total"] > 0
        assert context["current_month_spending"]["transaction_count"] == 2

    async def test_category_context(self, db_session: AsyncSession, user_with_data: User):
        context = await get_financial_context(user_with_data.id, ["category"], db_session)
        assert "category_breakdown" in context
        assert len(context["category_breakdown"]) > 0
        assert context["category_breakdown"][0]["category"] == "Food"

    async def test_budget_context(self, db_session: AsyncSession, user_with_data: User):
        context = await get_financial_context(user_with_data.id, ["budget"], db_session)
        assert "budget_status" in context

    async def test_recent_expenses_always_included(
        self, db_session: AsyncSession, user_with_data: User
    ):
        context = await get_financial_context(user_with_data.id, ["general"], db_session)
        assert "recent_expenses" in context
        assert len(context["recent_expenses"]) == 2


# ─── Conversation API ───────────────────────────────────────────────────────


class TestConversationAPI:
    async def test_create_conversation(self, auth_client: AsyncClient):
        resp = await auth_client.post(
            "/api/v1/chat/conversations",
            json={"title": "March Budget Review"},
        )
        assert resp.status_code == 201
        data = resp.json()
        assert data["title"] == "March Budget Review"
        assert "id" in data

    async def test_list_conversations(self, auth_client: AsyncClient):
        # Create two conversations
        await auth_client.post("/api/v1/chat/conversations", json={"title": "Chat 1"})
        await auth_client.post("/api/v1/chat/conversations", json={"title": "Chat 2"})

        resp = await auth_client.get("/api/v1/chat/conversations")
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) >= 2

    async def test_update_conversation_title(self, auth_client: AsyncClient):
        create_resp = await auth_client.post(
            "/api/v1/chat/conversations", json={"title": "Old Title"}
        )
        conv_id = create_resp.json()["id"]

        resp = await auth_client.put(
            f"/api/v1/chat/conversations/{conv_id}",
            json={"title": "New Title"},
        )
        assert resp.status_code == 200
        assert resp.json()["title"] == "New Title"

    async def test_delete_conversation(self, auth_client: AsyncClient):
        create_resp = await auth_client.post(
            "/api/v1/chat/conversations", json={"title": "To Delete"}
        )
        conv_id = create_resp.json()["id"]

        resp = await auth_client.delete(f"/api/v1/chat/conversations/{conv_id}")
        assert resp.status_code == 204

    async def test_conversation_not_found(self, auth_client: AsyncClient):
        fake_id = str(uuid.uuid4())
        resp = await auth_client.put(
            f"/api/v1/chat/conversations/{fake_id}",
            json={"title": "Nope"},
        )
        assert resp.status_code == 404


# ─── Messages API ────────────────────────────────────────────────────────────


class TestMessagesAPI:
    async def test_list_messages_empty(self, auth_client: AsyncClient):
        create_resp = await auth_client.post(
            "/api/v1/chat/conversations", json={"title": "Empty"}
        )
        conv_id = create_resp.json()["id"]

        resp = await auth_client.get(f"/api/v1/chat/conversations/{conv_id}/messages")
        assert resp.status_code == 200
        data = resp.json()
        assert data["total"] == 0
        assert data["items"] == []

    async def test_messages_not_found_for_wrong_conversation(self, auth_client: AsyncClient):
        fake_id = str(uuid.uuid4())
        resp = await auth_client.get(f"/api/v1/chat/conversations/{fake_id}/messages")
        assert resp.status_code == 404

    async def test_send_message_requires_auth(self, client: AsyncClient):
        fake_id = str(uuid.uuid4())
        resp = await client.post(
            f"/api/v1/chat/conversations/{fake_id}/messages",
            json={"content": "Hello", "model": "haiku"},
        )
        assert resp.status_code == 401
