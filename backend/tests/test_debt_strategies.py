"""Tests for the debt payoff strategy engine."""

import pytest

from src.app.services.debt_strategies import compare_strategies


def _make_debt(name: str, balance: float, apr: float, min_payment: float) -> dict:
    return {
        "name": name,
        "balance": balance,
        "apr": apr,
        "min_payment": min_payment,
    }


# ---------------------------------------------------------------------------
# Strategy ordering
# ---------------------------------------------------------------------------


async def test_avalanche_targets_highest_apr():
    """Avalanche should pay off the high-APR debt first."""
    debts = [
        _make_debt("Low APR", 3000, 0.05, 50),
        _make_debt("High APR", 3000, 0.25, 50),
    ]
    result = compare_strategies(debts, monthly_budget=500)

    assert result["error"] is None
    avalanche_order = [
        entry["name"] for entry in result["avalanche"]["payoff_order"]
    ]
    # High APR should be eliminated first
    assert avalanche_order[0] == "High APR"


async def test_snowball_targets_smallest_balance():
    """Snowball should pay off the smallest balance first."""
    debts = [
        _make_debt("Big Balance", 10000, 0.15, 100),
        _make_debt("Small Balance", 1000, 0.15, 50),
    ]
    result = compare_strategies(debts, monthly_budget=500)

    assert result["error"] is None
    snowball_order = [
        entry["name"] for entry in result["snowball"]["payoff_order"]
    ]
    assert snowball_order[0] == "Small Balance"


# ---------------------------------------------------------------------------
# Comparison across strategies
# ---------------------------------------------------------------------------


async def test_compare_strategies():
    """With 3 debts and $800 budget, avalanche should have lowest total_interest."""
    debts = [
        _make_debt("Card A", 5000, 0.24, 100),
        _make_debt("Card B", 3000, 0.18, 75),
        _make_debt("Car Loan", 8000, 0.06, 200),
    ]
    result = compare_strategies(debts, monthly_budget=800)

    assert result["error"] is None

    avalanche_interest = result["avalanche"]["total_interest"]
    snowball_interest = result["snowball"]["total_interest"]

    # Avalanche minimizes interest (or ties with snowball in rare cases)
    assert avalanche_interest <= snowball_interest

    # Minimum-only should be the worst
    minimum_interest = result["minimum_only"]["total_interest"]
    assert minimum_interest >= avalanche_interest

    # All strategies should eventually pay off all debts
    for strategy_name in ("avalanche", "snowball", "hybrid", "minimum_only"):
        assert result[strategy_name]["months_to_freedom"] > 0
        assert result[strategy_name]["total_paid"] > 0

    # Recommendation should be present
    assert "recommendation" in result
    assert result["recommendation"]["strategy"] in (
        "avalanche",
        "snowball",
        "hybrid",
    )


# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------


async def test_budget_insufficient():
    """Budget less than sum of minimums should return an error."""
    debts = [
        _make_debt("Card A", 5000, 0.20, 200),
        _make_debt("Card B", 3000, 0.18, 150),
    ]
    # Total minimums = 350, budget = 300 → shortfall
    result = compare_strategies(debts, monthly_budget=300)

    assert result["error"] is not None
    assert "minimum" in result["error"].lower() or "budget" in result["error"].lower()


async def test_single_debt():
    """With only 1 debt, all strategies should produce the same result."""
    debts = [_make_debt("Only Card", 5000, 0.20, 100)]
    result = compare_strategies(debts, monthly_budget=300)

    assert result["error"] is None

    # With a single debt, all strategies should have identical outcomes
    avalanche = result["avalanche"]
    snowball = result["snowball"]
    hybrid = result["hybrid"]

    assert avalanche["months_to_freedom"] == snowball["months_to_freedom"]
    assert avalanche["total_interest"] == snowball["total_interest"]
    assert avalanche["months_to_freedom"] == hybrid["months_to_freedom"]
    assert avalanche["total_interest"] == hybrid["total_interest"]
