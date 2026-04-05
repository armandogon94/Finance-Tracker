"""Tests for the friend debt calculator service."""

import pytest

from src.app.services.friend_debt_calc import calculate_friend_debt


async def test_clear_status():
    """When bank balance >= friend's accumulated balance, status is 'clear'."""
    result = calculate_friend_debt(
        total_deposits=5000,
        total_withdrawals=1000,
        bank_balance=5000,
    )

    # Friend accumulated = 5000 - 1000 = 4000
    # Bank has 5000 >= 4000 => clear
    assert result["status"] == "clear"
    assert result["amount_owed"] == 0
    assert result["friend_accumulated"] == 4000.0
    assert result["current_bank_balance"] == 5000.0


async def test_shortfall_status():
    """When bank balance < accumulated and no external accounts, status is 'shortfall'."""
    result = calculate_friend_debt(
        total_deposits=5000,
        total_withdrawals=0,
        bank_balance=2000,
    )

    # Friend accumulated = 5000 - 0 = 5000
    # Bank has 2000 < 5000 => owed = 3000
    # No external accounts => shortfall
    assert result["status"] == "shortfall"
    assert result["amount_owed"] == 3000.0
    assert result["true_shortfall"] == 3000.0


async def test_covered_by_external():
    """When external accounts cover the shortfall, status is 'covered'."""
    result = calculate_friend_debt(
        total_deposits=5000,
        total_withdrawals=0,
        bank_balance=2000,
        external_accounts=[{"name": "Savings", "balance": 4000}],
    )

    # Owed = 5000 - 2000 = 3000
    # External = 4000 >= 3000 => covered
    assert result["status"] == "covered"
    assert result["amount_owed"] == 3000.0
    assert result["external_safety_net"] == 4000.0
    assert result["true_shortfall"] == 0.0


async def test_zero_deposits():
    """When everything is zero, friend has accumulated nothing => clear."""
    result = calculate_friend_debt(
        total_deposits=0,
        total_withdrawals=0,
        bank_balance=0,
    )

    assert result["status"] == "clear"
    assert result["amount_owed"] == 0.0
    assert result["friend_accumulated"] == 0.0
    assert result["true_shortfall"] == 0.0
