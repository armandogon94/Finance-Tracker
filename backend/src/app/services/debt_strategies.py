"""
Debt payoff strategy engine.

Simulates multi-debt payoff using four strategies (Avalanche, Snowball,
Hybrid, Minimum-Only) and produces a side-by-side comparison with a
recommendation.

Each debt dict is expected to have:
    name:        str   - Display name (e.g. "Chase Sapphire", "Car Loan")
    balance:     float - Current outstanding balance
    apr:         float - Annual percentage rate as decimal (e.g. 0.2499)
    min_payment: float - Required minimum monthly payment

For backward compatibility with routers that pass "rate" instead of "apr"
and "minimum_payment" instead of "min_payment", the functions normalize
keys internally.

Pure functions -- no database access.
"""

from __future__ import annotations

import copy
import logging
from datetime import datetime, timedelta
from typing import Any, Callable

from src.app.schemas.debt import StrategyComparison, StrategyResult

logger = logging.getLogger(__name__)

# Safety cap: 50 years
_MAX_MONTHS = 600


# ---------------------------------------------------------------------------
# Key normalization
# ---------------------------------------------------------------------------

def _normalize_debt(debt: dict[str, Any]) -> dict[str, Any]:
    """Normalize debt dict keys so both naming conventions work.

    Accepts either:
        - apr / min_payment  (new convention from PLAN.md)
        - rate / minimum_payment  (old convention from schema)
    Outputs a dict with both sets of keys present.
    """
    d = dict(debt)
    # APR normalization
    if "apr" not in d and "rate" in d:
        d["apr"] = d["rate"]
    elif "rate" not in d and "apr" in d:
        d["rate"] = d["apr"]
    # Minimum payment normalization
    if "min_payment" not in d and "minimum_payment" in d:
        d["min_payment"] = d["minimum_payment"]
    elif "minimum_payment" not in d and "min_payment" in d:
        d["minimum_payment"] = d["min_payment"]
    return d


# ---------------------------------------------------------------------------
# Core simulation engine
# ---------------------------------------------------------------------------

def simulate_payoff(
    debts: list[dict[str, Any]],
    extra: float,
    sort_key: Callable[[dict], Any] | None = None,
) -> dict[str, Any]:
    """Simulate paying off multiple debts with a given strategy ordering.

    Each month:
        1. Accrue interest on every debt.
        2. Pay the minimum on every debt.
        3. Apply all remaining extra money to the top-priority debt
           (first in list after sorting).
        4. When a debt is fully paid, its freed-up minimum payment is
           added to the extra pool (the "cascade" / "snowball" effect).

    Args:
        debts:    List of debt dicts. Will be deep-copied internally.
        extra:    Monthly budget surplus after all minimums are covered.
        sort_key: Optional callable to sort debts for priority ordering.
                  If None, debts are processed in the order given.

    Returns:
        dict with:
            months_to_freedom - Total months until all debts are paid off
            total_interest    - Total interest paid across all debts
            total_paid        - Total amount paid (principal + interest)
            payoff_order      - List of {name, month_paid_off} in elimination order
            timeline          - Monthly snapshot list with per-debt balances
    """
    # Deep copy and normalize to avoid mutating caller's data
    active_debts = [_normalize_debt(d) for d in copy.deepcopy(debts)]

    if sort_key is not None:
        active_debts.sort(key=sort_key)

    total_interest = 0.0
    total_paid = 0.0
    month = 0
    payoff_order: list[dict[str, Any]] = []
    timeline: list[dict[str, Any]] = []
    cascaded_extra = extra  # grows as debts are eliminated

    while any(d["balance"] > 0.005 for d in active_debts) and month < _MAX_MONTHS:
        month += 1
        month_interest = 0.0
        month_paid = 0.0

        # Step 1: Accrue interest on all debts
        for debt in active_debts:
            if debt["balance"] <= 0.005:
                continue
            interest = round(debt["balance"] * (debt["apr"] / 12.0), 2)
            debt["balance"] = round(debt["balance"] + interest, 2)
            month_interest += interest

        total_interest += month_interest

        # Step 2: Pay minimums on all debts
        for debt in active_debts:
            if debt["balance"] <= 0.005:
                continue
            payment = min(debt["min_payment"], debt["balance"])
            debt["balance"] = round(debt["balance"] - payment, 2)
            month_paid += payment

        # Step 3: Apply extra to the highest-priority debt with remaining balance
        remaining_extra = cascaded_extra
        for debt in active_debts:
            if debt["balance"] <= 0.005 or remaining_extra <= 0:
                continue
            extra_applied = min(remaining_extra, debt["balance"])
            debt["balance"] = round(debt["balance"] - extra_applied, 2)
            month_paid += extra_applied
            remaining_extra = round(remaining_extra - extra_applied, 2)
            # Only the first eligible debt gets the extra (unless it's fully paid)
            if debt["balance"] > 0.005:
                break  # Stop applying extra after the target debt

        total_paid += month_paid

        # Step 4: Check for newly paid-off debts and cascade their minimums
        for debt in active_debts:
            if debt["balance"] <= 0.005 and not debt.get("_paid_off"):
                debt["_paid_off"] = True
                debt["balance"] = 0.0
                payoff_order.append({
                    "name": debt["name"],
                    "month_paid_off": month,
                })
                # Cascade: freed minimum payment joins the extra pool
                cascaded_extra += debt["min_payment"]

        # Timeline snapshot
        timeline.append({
            "month": month,
            "date": (datetime.now() + timedelta(days=month * 30)).strftime("%Y-%m"),
            "total_remaining": round(
                sum(max(d["balance"], 0) for d in active_debts), 2
            ),
            "interest_this_month": round(month_interest, 2),
            "paid_this_month": round(month_paid, 2),
            "balances": {
                d["name"]: round(max(d["balance"], 0), 2) for d in active_debts
            },
        })

    return {
        "months_to_freedom": month,
        "total_interest": round(total_interest, 2),
        "total_paid": round(total_paid, 2),
        "payoff_order": payoff_order,
        "timeline": timeline,
    }


# ---------------------------------------------------------------------------
# Hybrid sort helper
# ---------------------------------------------------------------------------

def _hybrid_sort(debts: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Hybrid sort: pick the 1-2 smallest balances first for quick wins,
    then sort the rest by highest APR (avalanche).

    This balances the psychological benefit of quick wins with the
    mathematical efficiency of attacking high-interest debt.
    """
    normalized = [_normalize_debt(d) for d in debts]

    if len(normalized) <= 2:
        return sorted(normalized, key=lambda d: d["balance"])

    by_balance = sorted(normalized, key=lambda d: d["balance"])

    # Take the 1-2 smallest-balance debts first
    num_quick_wins = min(2, len(by_balance))
    quick_wins = by_balance[:num_quick_wins]
    remaining = by_balance[num_quick_wins:]

    # Sort remaining by highest APR
    remaining.sort(key=lambda d: -d["apr"])

    return quick_wins + remaining


# ---------------------------------------------------------------------------
# Strategy comparison -- dict-based return
# ---------------------------------------------------------------------------

def compare_strategies(
    debts: list[dict[str, Any]],
    monthly_budget: float,
) -> dict[str, Any]:
    """Run all payoff strategies and produce a side-by-side comparison.

    Strategies:
        1. Avalanche  - Target highest APR first (mathematically optimal)
        2. Snowball   - Target smallest balance first (psychological wins)
        3. Hybrid     - 1-2 smallest first, then highest APR
        4. Minimum    - Pay only minimums, no extra (baseline)

    Args:
        debts:          List of debt dicts with name, balance, apr, min_payment.
        monthly_budget: Total monthly amount available for all debt payments.

    Returns:
        dict with:
            avalanche      - Simulation results for avalanche strategy
            snowball       - Simulation results for snowball strategy
            hybrid         - Simulation results for hybrid strategy
            minimum_only   - Simulation results for minimum-only baseline
            extra_available - Monthly surplus after minimums
            total_debt     - Sum of all current balances
            total_minimums - Sum of all minimum payments
            recommendation - dict with strategy name, reason, and savings info
            error          - Error message if budget is insufficient (or None)
    """
    if not debts:
        return {"error": "No debts provided"}

    # Normalize all debts
    normalized = [_normalize_debt(d) for d in debts]
    # Filter out zero-balance debts
    active_debts = [d for d in normalized if d["balance"] > 0]

    if not active_debts:
        return {"error": None, "message": "All debts are already paid off."}

    total_minimums = sum(d["min_payment"] for d in active_debts)
    total_debt = sum(d["balance"] for d in active_debts)
    extra = monthly_budget - total_minimums

    if extra < 0:
        return {
            "error": "Budget doesn't cover minimum payments",
            "shortfall": round(total_minimums - monthly_budget, 2),
            "total_minimums": round(total_minimums, 2),
            "monthly_budget": round(monthly_budget, 2),
            "total_debt": round(total_debt, 2),
        }

    # Run all four strategies
    avalanche = simulate_payoff(
        active_debts, extra, sort_key=lambda d: -d["apr"]
    )
    snowball = simulate_payoff(
        active_debts, extra, sort_key=lambda d: d["balance"]
    )
    hybrid = simulate_payoff(
        _hybrid_sort(active_debts), extra, sort_key=None  # already sorted
    )
    minimum_only = simulate_payoff(
        active_debts, extra=0.0, sort_key=None
    )

    # Determine recommendation
    strategies = {
        "avalanche": avalanche,
        "snowball": snowball,
        "hybrid": hybrid,
    }

    best_cost = min(strategies.items(), key=lambda s: s[1]["total_interest"])
    best_speed = min(strategies.items(), key=lambda s: s[1]["months_to_freedom"])

    if best_cost[0] == best_speed[0]:
        rec_name = best_cost[0]
        reason = (
            f"{rec_name.title()} is both the fastest ({best_cost[1]['months_to_freedom']} months) "
            f"and cheapest (${best_cost[1]['total_interest']:,.2f} total interest)."
        )
    elif best_cost[0] == "avalanche":
        interest_saved = snowball["total_interest"] - avalanche["total_interest"]
        reason = (
            f"Avalanche saves ${interest_saved:,.2f} in interest vs. Snowball, "
            f"finishing in {avalanche['months_to_freedom']} months. "
            f"Snowball is {snowball['months_to_freedom']} months but offers quicker "
            f"psychological wins by eliminating smaller debts first."
        )
        rec_name = "avalanche"
    else:
        rec_name = best_cost[0]
        reason = (
            f"{rec_name.title()} minimizes total interest at "
            f"${best_cost[1]['total_interest']:,.2f}."
        )

    savings_vs_minimum = minimum_only["total_interest"] - avalanche["total_interest"]

    return {
        "avalanche": avalanche,
        "snowball": snowball,
        "hybrid": hybrid,
        "minimum_only": minimum_only,
        "extra_available": round(extra, 2),
        "total_debt": round(total_debt, 2),
        "total_minimums": round(total_minimums, 2),
        "recommendation": {
            "strategy": rec_name,
            "reason": reason,
            "interest_saved_vs_minimum": round(savings_vs_minimum, 2),
            "months_saved_vs_minimum": (
                minimum_only["months_to_freedom"] - avalanche["months_to_freedom"]
            ),
        },
        "error": None,
    }


# ---------------------------------------------------------------------------
# Pydantic-schema-compatible wrappers (for routers using the old API)
# ---------------------------------------------------------------------------

def compare_strategies_schema(
    debts: list[dict[str, Any]],
    monthly_budget: float,
) -> StrategyComparison:
    """Run all strategies and return a StrategyComparison Pydantic model.

    This wraps compare_strategies() for routers that expect the typed schema.
    The debt dicts can use either key convention (apr/min_payment or
    rate/minimum_payment).
    """
    normalized = [_normalize_debt(d) for d in debts]
    active_debts = [d for d in normalized if d["balance"] > 0]

    if not active_debts:
        empty = StrategyResult(
            strategy="", months_to_freedom=0, total_interest=0.0, payoff_order=[]
        )
        return StrategyComparison(
            avalanche=StrategyResult(strategy="avalanche", months_to_freedom=0, total_interest=0.0, payoff_order=[]),
            snowball=StrategyResult(strategy="snowball", months_to_freedom=0, total_interest=0.0, payoff_order=[]),
            hybrid=StrategyResult(strategy="hybrid", months_to_freedom=0, total_interest=0.0, payoff_order=[]),
            minimum_only=StrategyResult(strategy="minimum_only", months_to_freedom=0, total_interest=0.0, payoff_order=[]),
            recommendation="You're debt-free! No strategy needed.",
        )

    result = compare_strategies(debts, monthly_budget)

    if "error" in result and result["error"] is not None:
        # Budget shortfall -- return comparison with warning
        empty = StrategyResult(strategy="", months_to_freedom=0, total_interest=0.0, payoff_order=[])
        return StrategyComparison(
            avalanche=StrategyResult(strategy="avalanche", months_to_freedom=0, total_interest=0.0, payoff_order=[]),
            snowball=StrategyResult(strategy="snowball", months_to_freedom=0, total_interest=0.0, payoff_order=[]),
            hybrid=StrategyResult(strategy="hybrid", months_to_freedom=0, total_interest=0.0, payoff_order=[]),
            minimum_only=StrategyResult(strategy="minimum_only", months_to_freedom=0, total_interest=0.0, payoff_order=[]),
            recommendation=result["error"],
        )

    def _to_strategy_result(name: str, data: dict) -> StrategyResult:
        order = [
            entry["name"] if isinstance(entry, dict) else entry
            for entry in data.get("payoff_order", [])
        ]
        return StrategyResult(
            strategy=name,
            months_to_freedom=data["months_to_freedom"],
            total_interest=data["total_interest"],
            payoff_order=order,
        )

    rec = result["recommendation"]
    recommendation_str = rec["reason"] if isinstance(rec, dict) else str(rec)

    return StrategyComparison(
        avalanche=_to_strategy_result("avalanche", result["avalanche"]),
        snowball=_to_strategy_result("snowball", result["snowball"]),
        hybrid=_to_strategy_result("hybrid", result["hybrid"]),
        minimum_only=_to_strategy_result("minimum_only", result["minimum_only"]),
        recommendation=recommendation_str,
    )
