"""
Friend debt calculator service.

Specialized calculator for the scenario where a friend uses the user's
bank account as a "piggy bank" (depositing salary, occasionally withdrawing).
Calculates how much the user owes the friend and whether external accounts
cover the shortfall.

Provides both a pure-function interface (taking raw floats) and an
ORM-aware interface (taking model objects from the database).

Pure function -- no database access (the ORM wrapper just reads attributes).
"""

from __future__ import annotations

from typing import Any

from src.app.schemas.friend_debt import FriendDebtSummary


# ---------------------------------------------------------------------------
# Core calculation (pure function with scalar inputs)
# ---------------------------------------------------------------------------

def calculate_friend_debt(
    total_deposits: float,
    total_withdrawals: float,
    bank_balance: float,
    external_accounts: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Calculate the friend debt position.

    The friend's accumulated balance is the total deposited minus total
    withdrawn. If that exceeds the current bank balance, the user owes
    the difference. External accounts (savings, secondary checking, etc.)
    can cover part or all of the shortfall.

    Args:
        total_deposits:     Sum of all salary deposits the friend has made.
        total_withdrawals:  Sum of all money the friend has taken back out.
        bank_balance:       Current balance in the shared bank account.
        external_accounts:  List of dicts with {name: str, balance: float}
                            representing other accounts the user could pull
                            from to repay the friend.

    Returns:
        dict with:
            friend_accumulated    - Friend's net balance (deposits - withdrawals)
            current_bank_balance  - Echo of the bank balance input
            amount_owed           - How much the user owes (0 if in the clear)
            external_safety_net   - Total available in external accounts
            true_shortfall        - Amount still short after external accounts
            status                - "clear" | "covered" | "shortfall"
            breakdown             - Human-readable summary lines
    """
    if external_accounts is None:
        external_accounts = []

    # Friend's accumulated balance in the account
    friend_accumulated = total_deposits - total_withdrawals

    # How much the user owes: friend's money minus what's actually in the bank
    raw_owed = friend_accumulated - bank_balance

    # If the bank has more than the friend's total, user is in the clear
    amount_owed = max(raw_owed, 0.0)

    # External accounts the user could tap to cover the debt
    external_safety_net = sum(
        acct.get("balance", 0.0) for acct in external_accounts
    )

    # True shortfall: what's left after tapping all external accounts
    true_shortfall = max(amount_owed - external_safety_net, 0.0)

    # Determine status
    if amount_owed <= 0:
        status = "clear"
    elif amount_owed <= external_safety_net:
        status = "covered"
    else:
        status = "shortfall"

    # Build human-readable breakdown
    breakdown = _build_breakdown(
        friend_accumulated=friend_accumulated,
        bank_balance=bank_balance,
        amount_owed=amount_owed,
        external_safety_net=external_safety_net,
        true_shortfall=true_shortfall,
        status=status,
        external_accounts=external_accounts,
    )

    return {
        "friend_accumulated": round(friend_accumulated, 2),
        "current_bank_balance": round(bank_balance, 2),
        "amount_owed": round(amount_owed, 2),
        "external_safety_net": round(external_safety_net, 2),
        "true_shortfall": round(true_shortfall, 2),
        "status": status,
        "breakdown": breakdown,
    }


# ---------------------------------------------------------------------------
# ORM-aware wrapper (takes model objects, returns Pydantic schema)
# ---------------------------------------------------------------------------

def calculate_friend_debt_from_models(
    deposits: list,
    external_accounts: list,
    bank_balance: float,
) -> FriendDebtSummary:
    """Calculate friend debt from ORM model objects.

    This is the backward-compatible interface for routers that pass
    FriendDeposit and ExternalAccount ORM instances.

    Args:
        deposits: List of FriendDeposit ORM objects (with .amount and
                  .transaction_type attributes).
        external_accounts: List of ExternalAccount ORM objects (with
                           .current_balance attribute).
        bank_balance: User's current bank account balance.

    Returns:
        FriendDebtSummary Pydantic model.
    """
    # Sum deposits and withdrawals from ORM objects
    total_deposits = 0.0
    total_withdrawals = 0.0
    for dep in deposits:
        amount = float(dep.amount)
        if dep.transaction_type == "deposit":
            total_deposits += amount
        elif dep.transaction_type == "withdrawal":
            total_withdrawals += amount

    # Convert external accounts to dicts
    ext_dicts = [
        {"name": getattr(acc, "account_name", "Unknown"), "balance": float(acc.current_balance)}
        for acc in external_accounts
    ]

    result = calculate_friend_debt(
        total_deposits=total_deposits,
        total_withdrawals=total_withdrawals,
        bank_balance=bank_balance,
        external_accounts=ext_dicts,
    )

    return FriendDebtSummary(
        friend_accumulated=result["friend_accumulated"],
        current_bank_balance=result["current_bank_balance"],
        amount_owed=result["amount_owed"],
        external_safety_net=result["external_safety_net"],
        true_shortfall=result["true_shortfall"],
        status=result["status"],
    )


# ---------------------------------------------------------------------------
# Breakdown helper
# ---------------------------------------------------------------------------

def _build_breakdown(
    friend_accumulated: float,
    bank_balance: float,
    amount_owed: float,
    external_safety_net: float,
    true_shortfall: float,
    status: str,
    external_accounts: list[dict[str, Any]],
) -> list[str]:
    """Build human-readable summary lines for the friend debt calculation."""
    lines = [
        f"Friend's accumulated balance: ${friend_accumulated:,.2f}",
        f"Current bank balance: ${bank_balance:,.2f}",
    ]

    if status == "clear":
        surplus = bank_balance - friend_accumulated
        lines.append(f"Status: IN THE CLEAR (surplus of ${surplus:,.2f})")
    else:
        lines.append(f"Amount owed to friend: ${amount_owed:,.2f}")

        if external_accounts:
            lines.append(f"External safety net: ${external_safety_net:,.2f}")
            for acct in external_accounts:
                name = acct.get("name", "Unknown")
                bal = acct.get("balance", 0.0)
                lines.append(f"  - {name}: ${bal:,.2f}")

        if status == "covered":
            buffer = external_safety_net - amount_owed
            lines.append(
                f"Status: COVERED by external accounts "
                f"(${buffer:,.2f} buffer remaining)"
            )
        else:
            lines.append(
                f"Status: SHORTFALL of ${true_shortfall:,.2f} "
                f"(even after using all external accounts)"
            )

    return lines
