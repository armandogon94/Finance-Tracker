"""Tests for the debt calculator service (pure math functions)."""

import math

import pytest

from src.app.services.debt_calculator import (
    calculate_amortization,
    calculate_cc_payoff,
    calculate_loan_payoff,
)


# ---------------------------------------------------------------------------
# Credit card payoff
# ---------------------------------------------------------------------------


async def test_cc_payoff_basic():
    """$5000 balance, 20% APR, $200/month should pay off in a reasonable time."""
    result = calculate_cc_payoff(balance=5000, apr=0.20, monthly_payment=200)

    assert result["warning"] is None
    assert result["payoff_months"] > 0
    # At 20% APR / $200mo, payoff is roughly 30 months
    assert 25 <= result["payoff_months"] <= 35
    # Total interest should be a meaningful fraction of the balance
    assert 0 < result["total_interest"] < 5000
    # Total paid = principal + interest
    assert result["total_paid"] == pytest.approx(
        5000 + result["total_interest"], abs=1.0
    )


async def test_cc_payoff_insufficient_payment():
    """$5000 balance, 20% APR, $50/month (less than monthly interest) should warn."""
    result = calculate_cc_payoff(balance=5000, apr=0.20, monthly_payment=50)

    # Monthly interest = 5000 * 0.20/12 = ~$83.33 => $50 doesn't cover it
    assert result["warning"] is not None
    assert result["payoff_months"] == float("inf")
    assert result["total_interest"] == float("inf")


async def test_cc_payoff_zero_balance():
    """$0 balance should immediately return 0 months, 0 interest."""
    result = calculate_cc_payoff(balance=0, apr=0.20, monthly_payment=200)

    assert result["payoff_months"] == 0
    assert result["total_interest"] == 0.0
    assert result["total_paid"] == 0.0
    assert result["warning"] is None


# ---------------------------------------------------------------------------
# Loan payoff
# ---------------------------------------------------------------------------


async def test_loan_payoff_basic():
    """$20000, 6% APR, $400/month should pay off in roughly 56-58 months."""
    result = calculate_loan_payoff(
        balance=20000, annual_rate=0.06, monthly_payment=400
    )

    assert 50 <= result["total_months"] <= 62
    assert result["total_interest"] > 0
    assert result["total_paid"] == pytest.approx(
        20000 + result["total_interest"], abs=1.0
    )
    assert len(result["schedule"]) == result["total_months"]


# ---------------------------------------------------------------------------
# Amortization schedule
# ---------------------------------------------------------------------------


async def test_amortization_schedule():
    """$10000, 5% APR, 36 months -- verify payment ~$300, interest pattern, length."""
    result = calculate_amortization(
        principal=10000, annual_rate=0.05, term_months=36
    )

    # Monthly payment should be approximately $299.71
    assert 295 <= result["monthly_payment"] <= 305

    schedule = result["schedule"]
    assert len(schedule) == 36

    # First payment has more interest than the last payment
    first_interest = schedule[0]["interest"]
    last_interest = schedule[-1]["interest"]
    assert first_interest > last_interest

    # First payment's interest should be roughly 10000 * 0.05/12 = ~$41.67
    assert 40 <= first_interest <= 44


async def test_amortization_final_balance_zero():
    """The last row of an amortization schedule should have remaining_balance near 0."""
    result = calculate_amortization(
        principal=10000, annual_rate=0.05, term_months=36
    )

    schedule = result["schedule"]
    assert len(schedule) > 0

    final_balance = schedule[-1]["remaining_balance"]
    assert final_balance == pytest.approx(0.0, abs=0.01)

    # Total paid should equal principal + total interest
    assert result["total_paid"] == pytest.approx(
        10000 + result["total_interest"], abs=1.0
    )
