"use client";

import React, { useState, useEffect, useCallback } from "react";
import { useRouter } from "next/navigation";
import {
  Users,
  DollarSign,
  Plus,
  ArrowUpRight,
  ArrowDownLeft,
  Wallet,
  Building2,
  Loader2,
  AlertCircle,
  X,
  Check,
} from "lucide-react";
import { api } from "@/lib/api";
import { useAuth } from "@/contexts/AuthContext";
import { useFeatureFlag } from "@/contexts/FeatureFlagsContext";
import Navigation from "@/components/Navigation";
import type { FriendDebtSummary } from "@/types";

// ─── Helpers ────────────────────────────────────────────────────────

function fmt(n: number): string {
  return n.toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
  });
}

function getStatusColor(status: string): string {
  switch (status) {
    case "ok":
      return "from-green-500 to-emerald-600";
    case "warning":
      return "from-yellow-500 to-amber-600";
    case "critical":
      return "from-red-500 to-rose-600";
    default:
      return "from-gray-500 to-gray-600";
  }
}

function getStatusLabel(status: string): string {
  switch (status) {
    case "ok":
      return "All Clear";
    case "warning":
      return "Covered by External";
    case "critical":
      return "Shortfall";
    default:
      return "Unknown";
  }
}

// ─── Types ──────────────────────────────────────────────────────────

interface Deposit {
  id: string;
  type: "deposit" | "withdrawal";
  amount: number;
  description: string;
  date: string;
}

interface ExternalAccount {
  id: string;
  name: string;
  balance: number;
}

// ─── Component ──────────────────────────────────────────────────────

export default function FriendDebtPage() {
  const router = useRouter();
  const { isAuthenticated, isLoading: authLoading } = useAuth();
  const friendDebtEnabled = useFeatureFlag("friend_debt_calculator");

  const [summary, setSummary] = useState<FriendDebtSummary | null>(null);
  const [deposits, setDeposits] = useState<Deposit[]>([]);
  const [externalAccounts, setExternalAccounts] = useState<ExternalAccount[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Bank balance input
  const [bankBalance, setBankBalance] = useState("");
  const [savingBalance, setSavingBalance] = useState(false);
  const [balanceSaved, setBalanceSaved] = useState(false);

  // Add deposit form
  const [showAddDeposit, setShowAddDeposit] = useState(false);
  const [depositForm, setDepositForm] = useState({
    type: "deposit" as "deposit" | "withdrawal",
    amount: "",
    description: "",
  });
  const [savingDeposit, setSavingDeposit] = useState(false);

  // External account editing
  const [editingAccount, setEditingAccount] = useState<string | null>(null);
  const [editBalance, setEditBalance] = useState("");

  const API_BASE = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8002";

  // ── Fetch data ──────────────────────────────────────────────────

  const getHeaders = useCallback(() => {
    const token = localStorage.getItem("access_token");
    return {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    };
  }, []);

  const fetchData = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      const balance = bankBalance ? `?bank_balance=${bankBalance}` : "";
      const [summaryRes, depositsRes, accountsRes] = await Promise.all([
        fetch(`${API_BASE}/api/v1/friend-debt/summary${balance}`, {
          headers: getHeaders(),
        }),
        fetch(`${API_BASE}/api/v1/friend-debt/deposits`, {
          headers: getHeaders(),
        }),
        fetch(`${API_BASE}/api/v1/friend-debt/external-accounts`, {
          headers: getHeaders(),
        }),
      ]);

      if (summaryRes.ok) {
        const s = await summaryRes.json();
        setSummary(s);
        if (!bankBalance && s.current_bank_balance) {
          setBankBalance(String(s.current_bank_balance));
        }
      }

      if (depositsRes.ok) {
        const d = await depositsRes.json();
        setDeposits(Array.isArray(d) ? d : d?.items ?? []);
      }

      if (accountsRes.ok) {
        const a = await accountsRes.json();
        setExternalAccounts(Array.isArray(a) ? a : a?.items ?? []);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load data");
    } finally {
      setLoading(false);
    }
  }, [bankBalance, API_BASE, getHeaders]);

  useEffect(() => {
    if (authLoading) return;
    if (!isAuthenticated) {
      router.replace("/login");
      return;
    }
    if (friendDebtEnabled) {
      fetchData();
    }
  }, [isAuthenticated, authLoading, router, friendDebtEnabled, fetchData]);

  // ── Update bank balance ─────────────────────────────────────────

  const handleSaveBalance = async () => {
    setSavingBalance(true);
    setBalanceSaved(false);
    try {
      const res = await fetch(`${API_BASE}/api/v1/friend-debt/summary?bank_balance=${bankBalance}`, {
        headers: getHeaders(),
      });
      if (res.ok) {
        const s = await res.json();
        setSummary(s);
        setBalanceSaved(true);
        setTimeout(() => setBalanceSaved(false), 2000);
      }
    } catch {
      // ignore
    } finally {
      setSavingBalance(false);
    }
  };

  // ── Add deposit ─────────────────────────────────────────────────

  const handleAddDeposit = async () => {
    if (!depositForm.amount) return;
    setSavingDeposit(true);
    try {
      const res = await fetch(`${API_BASE}/api/v1/friend-debt/deposits`, {
        method: "POST",
        headers: getHeaders(),
        body: JSON.stringify({
          type: depositForm.type,
          amount: parseFloat(depositForm.amount),
          description: depositForm.description,
        }),
      });
      if (res.ok) {
        setShowAddDeposit(false);
        setDepositForm({ type: "deposit", amount: "", description: "" });
        fetchData();
      }
    } catch {
      // ignore
    } finally {
      setSavingDeposit(false);
    }
  };

  // ── Update external account balance ─────────────────────────────

  const handleUpdateAccountBalance = async (accountId: string) => {
    try {
      await fetch(`${API_BASE}/api/v1/friend-debt/external-accounts/${accountId}`, {
        method: "PATCH",
        headers: getHeaders(),
        body: JSON.stringify({ balance: parseFloat(editBalance) }),
      });
      setEditingAccount(null);
      fetchData();
    } catch {
      // ignore
    }
  };

  // ── Auth guard ────────────────────────────────────────────────────

  if (authLoading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <Loader2 className="h-8 w-8 animate-spin text-primary-500" />
      </div>
    );
  }

  // ── Feature gate ──────────────────────────────────────────────────

  if (!friendDebtEnabled) {
    return (
      <div className="min-h-screen bg-gray-50 pb-24">
        <header className="bg-gray-500 text-white px-4 pt-6 pb-8 rounded-b-3xl">
          <div className="flex items-center gap-2 mb-1">
            <Users className="h-5 w-5" />
            <h1 className="text-lg font-semibold">Friend Debt</h1>
          </div>
        </header>
        <div className="px-4 -mt-4">
          <div className="bg-white rounded-2xl shadow-sm p-8 text-center">
            <AlertCircle className="h-10 w-10 text-gray-300 mx-auto mb-3" />
            <p className="text-sm text-gray-500 font-medium">
              Feature Not Enabled
            </p>
            <p className="text-xs text-gray-400 mt-1">
              The friend debt calculator is not enabled for your account.
              Contact your administrator to enable it.
            </p>
          </div>
        </div>
        <Navigation />
      </div>
    );
  }

  // ── Render ──────────────────────────────────────────────────────

  return (
    <div className="min-h-screen bg-gray-50 pb-24">
      {/* Header */}
      <header className="bg-primary-500 text-white px-4 pt-6 pb-8 rounded-b-3xl">
        <div className="flex items-center gap-2 mb-1">
          <Users className="h-5 w-5" />
          <h1 className="text-lg font-semibold">Friend Debt</h1>
        </div>
        <p className="text-primary-50 text-sm">
          Track shared money with friends
        </p>
      </header>

      <div className="px-4 -mt-4 space-y-4">
        {loading ? (
          <div className="flex justify-center py-12">
            <Loader2 className="h-6 w-6 animate-spin text-gray-300" />
          </div>
        ) : error ? (
          <div className="bg-white rounded-2xl shadow-sm p-6 text-center">
            <p className="text-sm text-red-500">{error}</p>
            <button
              onClick={fetchData}
              className="mt-3 text-sm text-primary-500 font-medium"
            >
              Try again
            </button>
          </div>
        ) : (
          <>
            {/* Debt status card */}
            {summary && (
              <div
                className={`bg-gradient-to-br ${getStatusColor(
                  summary.status
                )} rounded-2xl shadow-sm p-5 text-white`}
              >
                <p className="text-sm font-medium text-white/80">
                  {getStatusLabel(summary.status)}
                </p>
                <p className="text-3xl font-bold mt-1">
                  {fmt(Math.abs(summary.true_shortfall))}
                </p>
                <p className="text-sm text-white/70 mt-2">
                  {summary.status === "ok"
                    ? "You have enough to cover all debts"
                    : summary.status === "warning"
                    ? "Covered using external accounts"
                    : "You need more funds to cover debts"}
                </p>

                <div className="grid grid-cols-2 gap-3 mt-4 pt-4 border-t border-white/20">
                  <div>
                    <p className="text-xs text-white/60">Friend Accumulated</p>
                    <p className="text-sm font-semibold">
                      {fmt(summary.friend_accumulated)}
                    </p>
                  </div>
                  <div>
                    <p className="text-xs text-white/60">Amount Owed</p>
                    <p className="text-sm font-semibold">
                      {fmt(summary.amount_owed)}
                    </p>
                  </div>
                  <div>
                    <p className="text-xs text-white/60">Bank Balance</p>
                    <p className="text-sm font-semibold">
                      {fmt(summary.current_bank_balance)}
                    </p>
                  </div>
                  <div>
                    <p className="text-xs text-white/60">External Safety</p>
                    <p className="text-sm font-semibold">
                      {fmt(summary.external_safety_net)}
                    </p>
                  </div>
                </div>
              </div>
            )}

            {/* Update bank balance */}
            <div className="bg-white rounded-2xl shadow-sm p-4">
              <div className="flex items-center gap-2 text-sm font-semibold text-gray-700 mb-3">
                <Wallet className="h-4 w-4" />
                Update Bank Balance
              </div>
              <div className="flex gap-2">
                <div className="relative flex-1">
                  <DollarSign className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
                  <input
                    type="number"
                    min="0"
                    step="0.01"
                    value={bankBalance}
                    onChange={(e) => setBankBalance(e.target.value)}
                    placeholder="0.00"
                    className="w-full rounded-lg border border-gray-200 bg-gray-50 pl-9 pr-3 py-2.5
                               text-sm text-gray-800 focus:outline-none focus:ring-2
                               focus:ring-primary-500"
                  />
                </div>
                <button
                  onClick={handleSaveBalance}
                  disabled={savingBalance || !bankBalance}
                  className="px-4 rounded-lg bg-primary-500 text-white text-sm font-medium
                             hover:bg-primary-600 transition-colors
                             disabled:opacity-60 disabled:cursor-not-allowed
                             flex items-center gap-1.5"
                >
                  {savingBalance ? (
                    <Loader2 className="h-4 w-4 animate-spin" />
                  ) : balanceSaved ? (
                    <Check className="h-4 w-4" />
                  ) : (
                    "Save"
                  )}
                </button>
              </div>
            </div>

            {/* Deposit/withdrawal log */}
            <div className="bg-white rounded-2xl shadow-sm overflow-hidden">
              <div className="px-4 py-3 border-b border-gray-100 flex items-center justify-between">
                <h2 className="text-sm font-semibold text-gray-700">
                  Deposits & Withdrawals
                </h2>
                <button
                  onClick={() => setShowAddDeposit(!showAddDeposit)}
                  className="h-7 w-7 rounded-lg bg-primary-50 text-primary-500 flex items-center
                             justify-center hover:bg-primary-100 transition-colors"
                >
                  {showAddDeposit ? (
                    <X className="h-3.5 w-3.5" />
                  ) : (
                    <Plus className="h-3.5 w-3.5" />
                  )}
                </button>
              </div>

              {/* Inline add form */}
              {showAddDeposit && (
                <div className="px-4 py-3 border-b border-gray-100 space-y-2 bg-gray-50">
                  <div className="flex gap-2">
                    <select
                      value={depositForm.type}
                      onChange={(e) =>
                        setDepositForm({
                          ...depositForm,
                          type: e.target.value as "deposit" | "withdrawal",
                        })
                      }
                      className="rounded-lg border border-gray-200 bg-white px-2 py-2
                                 text-xs text-gray-700 focus:outline-none focus:ring-1
                                 focus:ring-primary-500"
                    >
                      <option value="deposit">Deposit</option>
                      <option value="withdrawal">Withdrawal</option>
                    </select>
                    <input
                      type="number"
                      min="0"
                      step="0.01"
                      value={depositForm.amount}
                      onChange={(e) =>
                        setDepositForm({ ...depositForm, amount: e.target.value })
                      }
                      placeholder="Amount"
                      className="flex-1 rounded-lg border border-gray-200 bg-white px-3 py-2
                                 text-xs text-gray-700 focus:outline-none focus:ring-1
                                 focus:ring-primary-500"
                    />
                  </div>
                  <input
                    type="text"
                    value={depositForm.description}
                    onChange={(e) =>
                      setDepositForm({
                        ...depositForm,
                        description: e.target.value,
                      })
                    }
                    placeholder="Description (optional)"
                    className="w-full rounded-lg border border-gray-200 bg-white px-3 py-2
                               text-xs text-gray-700 focus:outline-none focus:ring-1
                               focus:ring-primary-500"
                  />
                  <button
                    onClick={handleAddDeposit}
                    disabled={savingDeposit || !depositForm.amount}
                    className="w-full flex items-center justify-center gap-1.5 py-2 bg-primary-500
                               text-white text-xs font-semibold rounded-lg
                               hover:bg-primary-600 transition-colors
                               disabled:opacity-60"
                  >
                    {savingDeposit ? (
                      <Loader2 className="h-3.5 w-3.5 animate-spin" />
                    ) : (
                      <Plus className="h-3.5 w-3.5" />
                    )}
                    Add
                  </button>
                </div>
              )}

              {/* Log list */}
              {deposits.length === 0 ? (
                <div className="py-8 text-center">
                  <p className="text-xs text-gray-400">No entries yet</p>
                </div>
              ) : (
                <div className="divide-y divide-gray-50">
                  {deposits.map((d) => (
                    <div
                      key={d.id}
                      className="px-4 py-3 flex items-center gap-3"
                    >
                      <div
                        className={`h-8 w-8 rounded-full flex items-center justify-center flex-shrink-0 ${
                          d.type === "deposit"
                            ? "bg-green-50 text-green-500"
                            : "bg-red-50 text-red-500"
                        }`}
                      >
                        {d.type === "deposit" ? (
                          <ArrowDownLeft className="h-4 w-4" />
                        ) : (
                          <ArrowUpRight className="h-4 w-4" />
                        )}
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <span
                            className={`text-[10px] font-semibold uppercase px-1.5 py-0.5 rounded ${
                              d.type === "deposit"
                                ? "bg-green-50 text-green-600"
                                : "bg-red-50 text-red-600"
                            }`}
                          >
                            {d.type}
                          </span>
                          <span className="text-xs text-gray-400">
                            {d.date
                              ? new Date(d.date).toLocaleDateString("en-US", {
                                  month: "short",
                                  day: "numeric",
                                })
                              : ""}
                          </span>
                        </div>
                        {d.description && (
                          <p className="text-xs text-gray-500 mt-0.5 truncate">
                            {d.description}
                          </p>
                        )}
                      </div>
                      <span
                        className={`text-sm font-semibold flex-shrink-0 ${
                          d.type === "deposit"
                            ? "text-green-600"
                            : "text-red-600"
                        }`}
                      >
                        {d.type === "deposit" ? "+" : "-"}
                        {fmt(d.amount)}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* External accounts */}
            <div className="bg-white rounded-2xl shadow-sm overflow-hidden">
              <div className="px-4 py-3 border-b border-gray-100">
                <div className="flex items-center gap-2 text-sm font-semibold text-gray-700">
                  <Building2 className="h-4 w-4" />
                  External Accounts
                </div>
              </div>

              {externalAccounts.length === 0 ? (
                <div className="py-8 text-center">
                  <p className="text-xs text-gray-400">
                    No external accounts configured
                  </p>
                </div>
              ) : (
                <div className="divide-y divide-gray-50">
                  {externalAccounts.map((acc) => (
                    <div
                      key={acc.id}
                      className="px-4 py-3 flex items-center gap-3"
                    >
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium text-gray-700">
                          {acc.name}
                        </p>
                      </div>
                      {editingAccount === acc.id ? (
                        <div className="flex items-center gap-1.5">
                          <input
                            type="number"
                            min="0"
                            step="0.01"
                            value={editBalance}
                            onChange={(e) => setEditBalance(e.target.value)}
                            className="w-24 rounded-lg border border-gray-200 bg-gray-50 px-2 py-1.5
                                       text-xs text-gray-700 focus:outline-none focus:ring-1
                                       focus:ring-primary-500"
                          />
                          <button
                            onClick={() => handleUpdateAccountBalance(acc.id)}
                            className="h-7 w-7 rounded-lg bg-primary-50 text-primary-500
                                       flex items-center justify-center"
                          >
                            <Check className="h-3.5 w-3.5" />
                          </button>
                          <button
                            onClick={() => setEditingAccount(null)}
                            className="h-7 w-7 rounded-lg bg-gray-50 text-gray-400
                                       flex items-center justify-center"
                          >
                            <X className="h-3.5 w-3.5" />
                          </button>
                        </div>
                      ) : (
                        <button
                          onClick={() => {
                            setEditingAccount(acc.id);
                            setEditBalance(String(acc.balance));
                          }}
                          className="text-sm font-semibold text-gray-700 hover:text-primary-500
                                     transition-colors"
                        >
                          {fmt(acc.balance)}
                        </button>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>
          </>
        )}
      </div>

      <Navigation />
    </div>
  );
}
