"""
Debt math service.

Provides credit card payoff projections, loan amortization schedules with
optional extra payments, and standard amortization table generation.
All calculations use monthly compounding.

Pure functions -- no database access.  Used by the credit_cards and loans
routers to project payoff timelines and generate amortization schedules.
"""

from __future__ import annotations

import math
from datetime import datetime, timedelta

from src.app.schemas.debt import PayoffProjection


# ---------------------------------------------------------------------------
# Credit card payoff
# ---------------------------------------------------------------------------

def calculate_cc_payoff(
    balance: float,
    apr: float,
    monthly_payment: float,
) -> dict:
    """Calculate credit card payoff timeline at a fixed monthly payment.

    Uses the standard credit card payoff formula:
        months = -log(1 - (balance * r / payment)) / log(1 + r)
    where r = APR / 12.

    Falls back to month-by-month simulation for accurate total interest
    (handles rounding at the tail end).

    Args:
        balance:         Current outstanding balance.
        apr:             Annual percentage rate as a decimal (e.g. 0.2499 for 24.99%).
        monthly_payment: Fixed monthly payment amount.

    Returns:
        dict with:
            payoff_months   - Number of months to pay off (int or inf)
            total_interest  - Total interest paid over the payoff period
            total_paid      - Total amount paid (principal + interest)
            payoff_date     - Estimated payoff month/year string
            monthly_rate    - The monthly interest rate used
            warning         - Warning message if payment is too low (or None)
    """
    if balance <= 0:
        return {
            "payoff_months": 0,
            "total_interest": 0.0,
            "total_paid": 0.0,
            "payoff_date": datetime.now().strftime("%B %Y"),
            "monthly_rate": 0.0,
            "warning": None,
        }

    monthly_rate = apr / 12.0

    if monthly_payment <= 0:
        return {
            "payoff_months": float("inf"),
            "total_interest": float("inf"),
            "total_paid": float("inf"),
            "payoff_date": "Never",
            "monthly_rate": round(monthly_rate, 6),
            "warning": "Payment amount must be greater than zero.",
        }

    # Edge case: 0% APR
    if monthly_rate == 0:
        months = math.ceil(balance / monthly_payment)
        return {
            "payoff_months": months,
            "total_interest": 0.0,
            "total_paid": round(balance, 2),
            "payoff_date": (datetime.now() + timedelta(days=months * 30)).strftime("%B %Y"),
            "monthly_rate": 0.0,
            "warning": None,
        }

    # Check if payment covers at least the first month's interest
    first_month_interest = balance * monthly_rate
    if monthly_payment <= first_month_interest:
        return {
            "payoff_months": float("inf"),
            "total_interest": float("inf"),
            "total_paid": float("inf"),
            "payoff_date": "Never",
            "monthly_rate": round(monthly_rate, 6),
            "warning": (
                f"Payment of ${monthly_payment:.2f} does not cover monthly interest "
                f"of ${first_month_interest:.2f}. Balance will grow!"
            ),
        }

    # Closed-form formula for exact month count (informational)
    try:
        months_exact = -(
            math.log(1 - (balance * monthly_rate / monthly_payment))
            / math.log(1 + monthly_rate)
        )
    except (ValueError, ZeroDivisionError):
        months_exact = None

    # Month-by-month simulation for accurate totals
    remaining = balance
    total_interest = 0.0
    total_paid = 0.0
    sim_months = 0
    max_months = 1200  # 100-year safety cap

    while remaining > 0.005 and sim_months < max_months:
        sim_months += 1
        interest = round(remaining * monthly_rate, 2)
        total_interest += interest
        remaining += interest
        payment = min(monthly_payment, remaining)
        total_paid += payment
        remaining = round(remaining - payment, 2)

    if remaining > 0.005:
        return {
            "payoff_months": float("inf"),
            "total_interest": float("inf"),
            "total_paid": float("inf"),
            "payoff_date": "Never",
            "monthly_rate": round(monthly_rate, 6),
            "warning": "Payoff exceeds 100 years -- payment is too low.",
        }

    payoff_date = (datetime.now() + timedelta(days=sim_months * 30)).strftime("%B %Y")

    return {
        "payoff_months": sim_months,
        "total_interest": round(total_interest, 2),
        "total_paid": round(total_paid, 2),
        "payoff_date": payoff_date,
        "monthly_rate": round(monthly_rate, 6),
        "warning": None,
    }


def calculate_cc_payoff_projection(
    balance: float,
    apr: float,
    monthly_payment: float,
) -> PayoffProjection:
    """Wrapper that returns a PayoffProjection Pydantic model.

    Convenience for routers that expect the schema object.
    """
    result = calculate_cc_payoff(balance, apr, monthly_payment)
    return PayoffProjection(
        payoff_months=result["payoff_months"],
        total_interest=result["total_interest"],
        payoff_date=result["payoff_date"],
        warning=result.get("warning"),
    )


# ---------------------------------------------------------------------------
# Loan payoff with optional extra payments
# ---------------------------------------------------------------------------

def calculate_loan_payoff(
    balance: float,
    annual_rate: float,
    monthly_payment: float,
    extra_payment: float = 0,
) -> dict:
    """Calculate loan payoff with month-by-month amortization schedule.

    Simulates each month: interest accrues, then the payment (minimum +
    extra) is applied. Extra payments go entirely to principal, reducing
    future interest.

    Args:
        balance:         Current outstanding loan balance.
        annual_rate:     Annual interest rate as a decimal (e.g. 0.065 for 6.5%).
        monthly_payment: Regular monthly payment amount.
        extra_payment:   Additional monthly payment toward principal (default 0).

    Returns:
        dict with:
            total_months   - Months until payoff
            total_interest - Total interest paid
            total_paid     - Total amount paid
            payoff_date    - Estimated payoff month/year string
            schedule       - List of month-by-month amortization dicts
    """
    if balance <= 0:
        return {
            "total_months": 0,
            "total_interest": 0.0,
            "total_paid": 0.0,
            "payoff_date": datetime.now().strftime("%B %Y"),
            "schedule": [],
        }

    monthly_rate = annual_rate / 12.0
    schedule = []
    remaining = balance
    month = 0
    total_interest = 0.0
    total_paid = 0.0
    max_months = 1200  # safety cap

    # Check if payment covers interest (for non-zero rates)
    if monthly_rate > 0 and (monthly_payment + extra_payment) <= balance * monthly_rate:
        return {
            "total_months": float("inf"),
            "total_interest": float("inf"),
            "total_paid": float("inf"),
            "payoff_date": "Never",
            "schedule": [],
            "warning": (
                f"Combined payment of ${monthly_payment + extra_payment:.2f} does not "
                f"cover monthly interest of ${balance * monthly_rate:.2f}."
            ),
        }

    while remaining > 0.005 and month < max_months:
        month += 1
        interest = round(remaining * monthly_rate, 2)
        total_interest += interest

        # Payment is the lesser of (regular + extra) or (remaining balance + interest)
        payment = min(monthly_payment + extra_payment, remaining + interest)
        total_paid += payment
        principal = payment - interest
        remaining = round(remaining - principal, 2)

        schedule.append({
            "month": month,
            "payment": round(payment, 2),
            "principal": round(principal, 2),
            "interest": round(interest, 2),
            "extra_applied": round(min(extra_payment, max(payment - monthly_payment, 0)), 2),
            "remaining_balance": round(max(remaining, 0), 2),
        })

    payoff_date = (datetime.now() + timedelta(days=month * 30)).strftime("%B %Y")

    return {
        "total_months": month,
        "total_interest": round(total_interest, 2),
        "total_paid": round(total_paid, 2),
        "payoff_date": payoff_date,
        "schedule": schedule,
    }


def calculate_loan_payoff_projection(
    balance: float,
    annual_rate: float,
    monthly_payment: float,
) -> PayoffProjection:
    """Wrapper that returns a PayoffProjection Pydantic model for loan payoff.

    Convenience for routers that expect the schema object.
    """
    result = calculate_loan_payoff(balance, annual_rate, monthly_payment)
    return PayoffProjection(
        payoff_months=result["total_months"],
        total_interest=result["total_interest"],
        payoff_date=result.get("payoff_date"),
        warning=result.get("warning"),
    )


# ---------------------------------------------------------------------------
# Standard amortization table
# ---------------------------------------------------------------------------

def calculate_amortization(
    principal: float,
    annual_rate: float,
    term_months: int,
) -> dict:
    """Generate a standard fixed-payment amortization schedule.

    Uses the standard formula:
        M = P * [r(1+r)^n] / [(1+r)^n - 1]
    where P = principal, r = monthly rate, n = term in months.

    Args:
        principal:    Loan principal amount.
        annual_rate:  Annual interest rate as a decimal.
        term_months:  Total loan term in months.

    Returns:
        dict with:
            monthly_payment - Fixed monthly payment amount
            total_interest  - Total interest over the life of the loan
            total_paid      - Total amount paid (principal + interest)
            schedule        - Full month-by-month amortization table
    """
    if principal <= 0 or term_months <= 0:
        return {
            "monthly_payment": 0.0,
            "total_interest": 0.0,
            "total_paid": 0.0,
            "schedule": [],
        }

    monthly_rate = annual_rate / 12.0

    # Calculate fixed monthly payment
    if monthly_rate == 0:
        # 0% interest loan
        monthly_payment = principal / term_months
    else:
        # Standard amortization formula: M = P * [r(1+r)^n] / [(1+r)^n - 1]
        factor = (1 + monthly_rate) ** term_months
        monthly_payment = principal * (monthly_rate * factor) / (factor - 1)

    monthly_payment = round(monthly_payment, 2)

    # Generate schedule
    schedule = []
    remaining = principal
    total_interest = 0.0
    total_paid = 0.0

    for month in range(1, term_months + 1):
        interest = round(remaining * monthly_rate, 2)
        total_interest += interest

        # Last month: adjust payment to exactly zero out the balance
        if month == term_months:
            payment = round(remaining + interest, 2)
            p = remaining
        else:
            payment = monthly_payment
            p = round(payment - interest, 2)

        # Edge case: payment doesn't cover interest (shouldn't happen
        # with correct formula, but guard defensively)
        if p < 0:
            p = 0.0
            payment = interest

        total_paid += payment
        remaining = round(remaining - p, 2)
        if remaining < 0:
            remaining = 0.0

        schedule.append({
            "month": month,
            "payment": round(payment, 2),
            "principal": round(p, 2),
            "interest": round(interest, 2),
            "remaining_balance": round(max(remaining, 0), 2),
        })

    return {
        "monthly_payment": monthly_payment,
        "total_interest": round(total_interest, 2),
        "total_paid": round(total_paid, 2),
        "schedule": schedule,
    }
