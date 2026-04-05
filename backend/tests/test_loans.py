"""Tests for loan CRUD endpoints."""

import pytest
from httpx import AsyncClient

from src.app.models.loan import Loan
from src.app.models.user import User


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

SAMPLE_LOAN = {
    "loan_name": "Car Loan",
    "loan_type": "car",
    "original_principal": 25000.00,
    "current_balance": 18000.00,
    "interest_rate": 0.0549,
}


# ---------------------------------------------------------------------------
# Unauthenticated access
# ---------------------------------------------------------------------------


async def test_list_loans_unauthenticated(client: AsyncClient):
    """GET /api/v1/loans/ without auth should return 401."""
    resp = await client.get("/api/v1/loans/")
    assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Create loan
# ---------------------------------------------------------------------------


async def test_create_loan(auth_client: AsyncClient, test_user: User):
    """POST /api/v1/loans/ should create a loan and return 201."""
    resp = await auth_client.post("/api/v1/loans/", json=SAMPLE_LOAN)
    assert resp.status_code == 201

    data = resp.json()
    assert data["loan_name"] == "Car Loan"
    assert data["loan_type"] == "car"
    assert data["original_principal"] == 25000.00
    assert data["current_balance"] == 18000.00
    assert data["interest_rate"] == 0.0549
    assert data["is_active"] is True
    assert "id" in data


# ---------------------------------------------------------------------------
# Progress percent computation
# ---------------------------------------------------------------------------


async def test_progress_percent_computed_correctly(
    auth_client: AsyncClient, test_user: User
):
    """progress_percent should be (original - current) / original * 100."""
    resp = await auth_client.post(
        "/api/v1/loans/",
        json={
            "loan_name": "Student Loan",
            "loan_type": "student",
            "original_principal": 40000.00,
            "current_balance": 30000.00,
            "interest_rate": 0.0450,
        },
    )
    assert resp.status_code == 201

    data = resp.json()
    # (40000 - 30000) / 40000 * 100 = 25.0
    assert data["progress_percent"] == 25.0


async def test_progress_percent_fully_paid(auth_client: AsyncClient, test_user: User):
    """A loan with current_balance=0 should have progress_percent=100."""
    resp = await auth_client.post(
        "/api/v1/loans/",
        json={
            "loan_name": "Paid Off Loan",
            "loan_type": "personal",
            "original_principal": 5000.00,
            "current_balance": 0.00,
            "interest_rate": 0.0800,
        },
    )
    assert resp.status_code == 201
    assert resp.json()["progress_percent"] == 100.0


# ---------------------------------------------------------------------------
# List loans
# ---------------------------------------------------------------------------


async def test_list_loans(auth_client: AsyncClient, test_user: User):
    """GET /api/v1/loans/ should return active loans for the user."""
    await auth_client.post("/api/v1/loans/", json=SAMPLE_LOAN)
    await auth_client.post(
        "/api/v1/loans/",
        json={**SAMPLE_LOAN, "loan_name": "Personal Loan", "loan_type": "personal"},
    )

    resp = await auth_client.get("/api/v1/loans/")
    assert resp.status_code == 200

    data = resp.json()
    assert isinstance(data, list)
    assert len(data) == 2


# ---------------------------------------------------------------------------
# Delete loan (soft delete)
# ---------------------------------------------------------------------------


async def test_delete_loan(auth_client: AsyncClient, test_user: User):
    """DELETE /api/v1/loans/{id} should soft-delete the loan."""
    create_resp = await auth_client.post("/api/v1/loans/", json=SAMPLE_LOAN)
    loan_id = create_resp.json()["id"]

    del_resp = await auth_client.delete(f"/api/v1/loans/{loan_id}")
    assert del_resp.status_code == 204

    # Soft-deleted loan should not appear in list
    list_resp = await auth_client.get("/api/v1/loans/")
    ids = [ln["id"] for ln in list_resp.json()]
    assert loan_id not in ids


# ---------------------------------------------------------------------------
# Loan payment: principal/interest split
# ---------------------------------------------------------------------------


async def test_loan_payment_splits_principal_and_interest(
    auth_client: AsyncClient, test_user: User
):
    """POST /api/v1/loans/{id}/payment should correctly split interest vs principal.

    For a $18,000 balance at 5.49% APR, monthly interest = 18000 * 0.0549/12 = $82.35.
    A $500 payment should yield interest_portion ~$82.35, principal_portion ~$417.65.
    """
    create_resp = await auth_client.post("/api/v1/loans/", json=SAMPLE_LOAN)
    loan_id = create_resp.json()["id"]

    pay_resp = await auth_client.post(
        f"/api/v1/loans/{loan_id}/payment",
        json={"amount": 500.00},
    )
    assert pay_resp.status_code == 201

    data = pay_resp.json()
    # Interest should be ~$82.35 (18000 * 0.0549 / 12)
    assert 80 <= data["interest_portion"] <= 85, f"Expected ~82.35, got {data['interest_portion']}"
    # Principal = payment - interest
    assert 415 <= data["principal_portion"] <= 420, f"Expected ~417.65, got {data['principal_portion']}"
    # New balance = 18000 - principal
    assert data["new_balance"] < 18000
    assert data["new_balance"] > 17500
