"use client";

import React, { useState, useEffect, useCallback } from "react";
import { useRouter } from "next/navigation";
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from "recharts";
import {
  CreditCard as CreditCardIcon,
  Landmark,
  TrendingDown,
  ChevronDown,
  ChevronUp,
  Loader2,
  DollarSign,
  Plus,
  X,
  Trash2,
} from "lucide-react";
import { api } from "@/lib/api";
import { useAuth } from "@/contexts/AuthContext";
import Navigation from "@/components/Navigation";
import type { CreditCard, Loan, StrategyResult } from "@/types";

// ─── Helpers ────────────────────────────────────────────────────────

function fmt(n: number): string {
  return n.toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  });
}

function fmtPct(n: number): string {
  return `${n.toFixed(1)}%`;
}

const STRATEGY_COLORS: Record<string, string> = {
  avalanche: "#3B82F6",
  snowball: "#10B981",
  hybrid: "#F59E0B",
  minimum_only: "#94A3B8",
};

const STRATEGY_LABELS: Record<string, string> = {
  avalanche: "Avalanche (highest APR first)",
  snowball: "Snowball (smallest balance first)",
  hybrid: "Hybrid",
  minimum_only: "Minimum payments only",
};

// ─── Component ──────────────────────────────────────────────────────

export default function DebtDashboardPage() {
  const router = useRouter();
  const { isAuthenticated, isLoading: authLoading } = useAuth();

  const [loading, setLoading] = useState(true);
  const [debtSummary, setDebtSummary] = useState<any>(null);
  const [creditCards, setCreditCards] = useState<CreditCard[]>([]);
  const [loans, setLoans] = useState<Loan[]>([]);
  const [strategies, setStrategies] = useState<StrategyResult[]>([]);
  const [monthlyBudget, setMonthlyBudget] = useState(500);
  const [sliderBudget, setSliderBudget] = useState(500);
  const [strategyOpen, setStrategyOpen] = useState(false);
  const [strategiesLoading, setStrategiesLoading] = useState(false);

  // Add forms
  const [showCardForm, setShowCardForm] = useState(false);
  const [showLoanForm, setShowLoanForm] = useState(false);
  const [formSaving, setFormSaving] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [cardForm, setCardForm] = useState({
    card_name: "", last_four: "", current_balance: "", credit_limit: "", apr: "", minimum_payment: "",
  });
  const [loanForm, setLoanForm] = useState({
    loan_name: "", lender: "", loan_type: "personal", original_principal: "", current_balance: "", interest_rate: "", minimum_payment: "",
  });

  const handleAddCard = async () => {
    if (!cardForm.card_name.trim()) { setFormError("Card name is required"); return; }
    setFormSaving(true);
    setFormError(null);
    try {
      await api.createCreditCard({
        card_name: cardForm.card_name.trim(),
        last_four: cardForm.last_four || null,
        current_balance: parseFloat(cardForm.current_balance) || 0,
        credit_limit: parseFloat(cardForm.credit_limit) || null,
        apr: (parseFloat(cardForm.apr) || 0) / 100,
        minimum_payment: parseFloat(cardForm.minimum_payment) || null,
      });
      setShowCardForm(false);
      setCardForm({ card_name: "", last_four: "", current_balance: "", credit_limit: "", apr: "", minimum_payment: "" });
      fetchData();
    } catch (err: unknown) {
      setFormError(err instanceof Error ? err.message : "Failed to add card");
    } finally { setFormSaving(false); }
  };

  const handleAddLoan = async () => {
    if (!loanForm.loan_name.trim()) { setFormError("Loan name is required"); return; }
    setFormSaving(true);
    setFormError(null);
    try {
      await api.createLoan({
        loan_name: loanForm.loan_name.trim(),
        lender: loanForm.lender || null,
        loan_type: loanForm.loan_type,
        original_principal: parseFloat(loanForm.original_principal) || 0,
        current_balance: parseFloat(loanForm.current_balance) || 0,
        interest_rate: (parseFloat(loanForm.interest_rate) || 0) / 100,
        minimum_payment: parseFloat(loanForm.minimum_payment) || null,
      });
      setShowLoanForm(false);
      setFormError(null);
      setLoanForm({ loan_name: "", lender: "", loan_type: "personal", original_principal: "", current_balance: "", interest_rate: "", minimum_payment: "" });
      fetchData();
    } catch (err: unknown) {
      setFormError(err instanceof Error ? err.message : "Failed to add loan");
    } finally { setFormSaving(false); }
  };

  const handleDeleteCard = async (id: string) => {
    try { await api.deleteCreditCard(id); fetchData(); } catch {}
  };

  const handleDeleteLoan = async (id: string) => {
    try { await api.deleteLoan(id); fetchData(); } catch {}
  };

  // ── Fetch core data ─────────────────────────────────────────────

  const fetchData = useCallback(async () => {
    setLoading(true);
    try {
      const [summary, cards, loanData] = await Promise.all([
        api.getDebtSummary(),
        api.getCreditCards(),
        api.getLoans(),
      ]);
      setDebtSummary(summary);
      setCreditCards(Array.isArray(cards) ? cards : []);
      setLoans(Array.isArray(loanData) ? loanData : []);
    } catch {
      // handle silently
    } finally {
      setLoading(false);
    }
  }, []);

  // ── Fetch strategies ──────────────────────────────────────────────

  const fetchStrategies = useCallback(async (budget: number) => {
    setStrategiesLoading(true);
    try {
      const data = await api.getDebtStrategies(budget);
      setStrategies(Array.isArray(data) ? data : data?.strategies ?? []);
    } catch {
      setStrategies([]);
    } finally {
      setStrategiesLoading(false);
    }
  }, []);

  useEffect(() => {
    if (authLoading) return;
    if (!isAuthenticated) {
      router.replace("/login");
      return;
    }
    fetchData();
  }, [isAuthenticated, authLoading, router, fetchData]);

  // Fetch strategies when section is opened or budget changes
  useEffect(() => {
    if (strategyOpen) {
      fetchStrategies(monthlyBudget);
    }
  }, [strategyOpen, monthlyBudget, fetchStrategies]);

  // Debounce slider -> monthlyBudget
  useEffect(() => {
    const timeout = setTimeout(() => {
      setMonthlyBudget(sliderBudget);
    }, 400);
    return () => clearTimeout(timeout);
  }, [sliderBudget]);

  // ── Auth guard ────────────────────────────────────────────────────

  if (authLoading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <Loader2 className="h-8 w-8 animate-spin text-primary-500" />
      </div>
    );
  }

  // ── Build chart data from strategies ──────────────────────────────

  const maxMonths = Math.max(
    ...strategies.map((s) => s.months_to_freedom),
    12
  );

  const chartData = Array.from({ length: Math.min(maxMonths, 120) }, (_, i) => {
    const month = i + 1;
    const point: Record<string, number> = { month };
    strategies.forEach((s) => {
      // Simple linear interpolation for visualization
      const totalDebt = debtSummary?.total_debt ?? 0;
      const fraction = Math.min(month / s.months_to_freedom, 1);
      point[s.strategy] = Math.max(
        totalDebt * (1 - fraction),
        0
      );
    });
    return point;
  });

  const totalDebt = debtSummary?.total_debt ?? 0;
  const totalMinPayment = debtSummary?.total_minimum_payment ?? 0;

  // ── Render ────────────────────────────────────────────────────────

  return (
    <div className="min-h-screen bg-gray-50 pb-24">
      {/* Header */}
      <header className="bg-gradient-to-br from-red-500 to-rose-600 text-white px-4 pt-6 pb-8 rounded-b-3xl">
        <div className="flex items-center gap-2 mb-1">
          <TrendingDown className="h-5 w-5" />
          <h1 className="text-lg font-semibold">Debt Dashboard</h1>
        </div>
        <p className="text-red-100 text-sm">Manage and pay down your debts</p>
      </header>

      {/* Total debt summary card */}
      <div className="px-4 -mt-4">
        <div className="bg-white rounded-2xl shadow-sm p-5">
          {loading ? (
            <div className="flex justify-center py-4">
              <Loader2 className="h-6 w-6 animate-spin text-gray-300" />
            </div>
          ) : (
            <div className="flex items-center justify-between">
              <div>
                <p className="text-xs text-gray-400 font-medium">
                  Total Debt
                </p>
                <p className="text-2xl font-bold text-gray-800 mt-0.5">
                  {fmt(totalDebt)}
                </p>
              </div>
              <div className="text-right">
                <p className="text-xs text-gray-400 font-medium">
                  Min. Monthly
                </p>
                <p className="text-lg font-semibold text-gray-600 mt-0.5">
                  {fmt(totalMinPayment)}
                </p>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Credit Cards */}
      <div className="px-4 mt-6">
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-2">
            <CreditCardIcon className="h-4 w-4 text-gray-500" />
            <h2 className="text-sm font-semibold text-gray-700">Credit Cards</h2>
          </div>
          <button onClick={() => setShowCardForm(true)} className="flex items-center gap-1 text-xs font-medium text-blue-600 hover:text-blue-700">
            <Plus className="h-3.5 w-3.5" /> Add Card
          </button>
        </div>

        {/* Add card form */}
        {showCardForm && (
          <div className="bg-white rounded-2xl shadow-sm p-4 mb-3 space-y-3">
            <div className="flex items-center justify-between">
              <p className="text-sm font-semibold text-gray-700">New Credit Card</p>
              <button onClick={() => setShowCardForm(false)} className="text-gray-400 hover:text-gray-600"><X className="h-4 w-4" /></button>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="col-span-2">
                <label className="block text-xs font-medium text-gray-500 mb-1">Card Name</label>
                <input type="text" value={cardForm.card_name} onChange={(e) => setCardForm({ ...cardForm, card_name: e.target.value })} placeholder="e.g. Chase Freedom" className="w-full rounded-xl border border-gray-200 bg-gray-50 py-2 px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1">Last 4 Digits</label>
                <input type="text" maxLength={4} value={cardForm.last_four} onChange={(e) => setCardForm({ ...cardForm, last_four: e.target.value.replace(/\D/g, "") })} placeholder="1234" className="w-full rounded-xl border border-gray-200 bg-gray-50 py-2 px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1">APR %</label>
                <input type="number" step="0.01" value={cardForm.apr} onChange={(e) => setCardForm({ ...cardForm, apr: e.target.value })} placeholder="24.99" className="w-full rounded-xl border border-gray-200 bg-gray-50 py-2 px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1">Balance</label>
                <input type="number" step="0.01" value={cardForm.current_balance} onChange={(e) => setCardForm({ ...cardForm, current_balance: e.target.value })} placeholder="3500" className="w-full rounded-xl border border-gray-200 bg-gray-50 py-2 px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1">Credit Limit</label>
                <input type="number" step="0.01" value={cardForm.credit_limit} onChange={(e) => setCardForm({ ...cardForm, credit_limit: e.target.value })} placeholder="10000" className="w-full rounded-xl border border-gray-200 bg-gray-50 py-2 px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div className="col-span-2">
                <label className="block text-xs font-medium text-gray-500 mb-1">Min. Payment</label>
                <input type="number" step="0.01" value={cardForm.minimum_payment} onChange={(e) => setCardForm({ ...cardForm, minimum_payment: e.target.value })} placeholder="75" className="w-full rounded-xl border border-gray-200 bg-gray-50 py-2 px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
            </div>
            {formError && showCardForm && <p className="text-xs text-red-500 bg-red-50 rounded-lg p-2">{formError}</p>}
            <button onClick={handleAddCard} disabled={formSaving} className="w-full h-10 rounded-xl bg-blue-600 text-white text-sm font-medium hover:bg-blue-700 active:scale-[0.98] transition-all disabled:opacity-50 flex items-center justify-center gap-2">
              {formSaving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Plus className="h-4 w-4" />}
              {formSaving ? "Saving..." : "Add Credit Card"}
            </button>
          </div>
        )}

        {creditCards.length === 0 && !showCardForm && (
          <div className="bg-white rounded-2xl shadow-sm p-6 text-center">
            <CreditCardIcon className="h-8 w-8 text-gray-300 mx-auto mb-2" />
            <p className="text-sm text-gray-400">No credit cards yet</p>
          </div>
        )}

        <div className="space-y-3">
          {creditCards.map((card) => {
            const utilPct = card.utilization ?? (card.credit_limit ? (card.current_balance / card.credit_limit) * 100 : 0);
            const utilColor = utilPct > 80 ? "bg-red-500" : utilPct > 50 ? "bg-yellow-500" : "bg-green-500";
            return (
              <div key={card.id} className="bg-white rounded-2xl shadow-sm p-4">
                <div className="flex items-start justify-between mb-3">
                  <div>
                    <p className="text-sm font-semibold text-gray-800">{card.card_name}</p>
                    <p className="text-xs text-gray-400 mt-0.5">****{card.last_four}</p>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-medium text-gray-500 bg-gray-100 px-2 py-0.5 rounded-full">{fmtPct(card.apr * 100)} APR</span>
                    <button onClick={() => handleDeleteCard(card.id)} className="text-gray-300 hover:text-red-500 transition-colors"><Trash2 className="h-3.5 w-3.5" /></button>
                  </div>
                </div>
                <div className="flex items-end justify-between mb-2">
                  <span className="text-lg font-bold text-gray-800">{fmt(card.current_balance)}</span>
                  {card.credit_limit ? <span className="text-xs text-gray-400">of {fmt(card.credit_limit)}</span> : null}
                </div>
                {card.credit_limit ? (
                  <>
                    <div className="h-2 rounded-full bg-gray-100 overflow-hidden">
                      <div className={`h-full rounded-full transition-all ${utilColor}`} style={{ width: `${Math.min(utilPct, 100)}%` }} />
                    </div>
                    <p className="text-[11px] text-gray-400 mt-1">{fmtPct(utilPct)} utilization</p>
                  </>
                ) : null}
              </div>
            );
          })}
        </div>
      </div>

      {/* Loans */}
      <div className="px-4 mt-6">
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-2">
            <Landmark className="h-4 w-4 text-gray-500" />
            <h2 className="text-sm font-semibold text-gray-700">Loans</h2>
          </div>
          <button onClick={() => setShowLoanForm(true)} className="flex items-center gap-1 text-xs font-medium text-blue-600 hover:text-blue-700">
            <Plus className="h-3.5 w-3.5" /> Add Loan
          </button>
        </div>

        {/* Add loan form */}
        {showLoanForm && (
          <div className="bg-white rounded-2xl shadow-sm p-4 mb-3 space-y-3">
            <div className="flex items-center justify-between">
              <p className="text-sm font-semibold text-gray-700">New Loan</p>
              <button onClick={() => setShowLoanForm(false)} className="text-gray-400 hover:text-gray-600"><X className="h-4 w-4" /></button>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="col-span-2">
                <label className="block text-xs font-medium text-gray-500 mb-1">Loan Name</label>
                <input type="text" value={loanForm.loan_name} onChange={(e) => setLoanForm({ ...loanForm, loan_name: e.target.value })} placeholder="e.g. Car Loan" className="w-full rounded-xl border border-gray-200 bg-gray-50 py-2 px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1">Lender</label>
                <input type="text" value={loanForm.lender} onChange={(e) => setLoanForm({ ...loanForm, lender: e.target.value })} placeholder="Bank name" className="w-full rounded-xl border border-gray-200 bg-gray-50 py-2 px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1">Type</label>
                <select value={loanForm.loan_type} onChange={(e) => setLoanForm({ ...loanForm, loan_type: e.target.value })} className="w-full rounded-xl border border-gray-200 bg-gray-50 py-2 px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500">
                  <option value="personal">Personal</option>
                  <option value="car">Car</option>
                  <option value="student">Student</option>
                  <option value="mortgage">Mortgage</option>
                  <option value="other">Other</option>
                </select>
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1">Original Amount</label>
                <input type="number" step="0.01" value={loanForm.original_principal} onChange={(e) => setLoanForm({ ...loanForm, original_principal: e.target.value })} placeholder="25000" className="w-full rounded-xl border border-gray-200 bg-gray-50 py-2 px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1">Current Balance</label>
                <input type="number" step="0.01" value={loanForm.current_balance} onChange={(e) => setLoanForm({ ...loanForm, current_balance: e.target.value })} placeholder="18000" className="w-full rounded-xl border border-gray-200 bg-gray-50 py-2 px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1">Interest Rate %</label>
                <input type="number" step="0.01" value={loanForm.interest_rate} onChange={(e) => setLoanForm({ ...loanForm, interest_rate: e.target.value })} placeholder="6.5" className="w-full rounded-xl border border-gray-200 bg-gray-50 py-2 px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1">Min. Payment</label>
                <input type="number" step="0.01" value={loanForm.minimum_payment} onChange={(e) => setLoanForm({ ...loanForm, minimum_payment: e.target.value })} placeholder="450" className="w-full rounded-xl border border-gray-200 bg-gray-50 py-2 px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
            </div>
            {formError && showLoanForm && <p className="text-xs text-red-500 bg-red-50 rounded-lg p-2">{formError}</p>}
            <button onClick={handleAddLoan} disabled={formSaving} className="w-full h-10 rounded-xl bg-blue-600 text-white text-sm font-medium hover:bg-blue-700 active:scale-[0.98] transition-all disabled:opacity-50 flex items-center justify-center gap-2">
              {formSaving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Plus className="h-4 w-4" />}
              {formSaving ? "Saving..." : "Add Loan"}
            </button>
          </div>
        )}

        {loans.length === 0 && !showLoanForm && (
          <div className="bg-white rounded-2xl shadow-sm p-6 text-center">
            <Landmark className="h-8 w-8 text-gray-300 mx-auto mb-2" />
            <p className="text-sm text-gray-400">No loans yet</p>
          </div>
        )}

        <div className="space-y-3">
          {loans.map((loan) => {
            const progressPct = loan.progress_percent ?? (loan.original_principal > 0 ? ((loan.original_principal - loan.current_balance) / loan.original_principal) * 100 : 0);
            return (
              <div key={loan.id} className="bg-white rounded-2xl shadow-sm p-4">
                <div className="flex items-start justify-between mb-3">
                  <div>
                    <p className="text-sm font-semibold text-gray-800">{loan.loan_name}</p>
                    <p className="text-xs text-gray-400 mt-0.5">{loan.lender}</p>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-medium text-white bg-blue-500 px-2 py-0.5 rounded-full capitalize">{loan.loan_type.replace(/_/g, " ")}</span>
                    <button onClick={() => handleDeleteLoan(loan.id)} className="text-gray-300 hover:text-red-500 transition-colors"><Trash2 className="h-3.5 w-3.5" /></button>
                  </div>
                </div>
                <div className="flex items-end justify-between mb-2">
                  <span className="text-lg font-bold text-gray-800">{fmt(loan.current_balance)}</span>
                  <span className="text-xs text-gray-400">{fmtPct(loan.interest_rate * 100)} rate</span>
                </div>
                <div className="h-2 rounded-full bg-gray-100 overflow-hidden">
                  <div className="h-full rounded-full bg-blue-500 transition-all" style={{ width: `${Math.min(progressPct, 100)}%` }} />
                </div>
                <p className="text-[11px] text-gray-400 mt-1">{fmtPct(progressPct)} paid off</p>
              </div>
            );
          })}
        </div>
      </div>

      {/* Strategy comparison (collapsible) */}
      <div className="px-4 mt-6">
        <button
          onClick={() => setStrategyOpen((o) => !o)}
          className="w-full bg-white rounded-2xl shadow-sm p-4 flex items-center justify-between"
        >
          <div className="flex items-center gap-2">
            <DollarSign className="h-4 w-4 text-primary-500" />
            <span className="text-sm font-semibold text-gray-700">
              Payoff Strategy Comparison
            </span>
          </div>
          {strategyOpen ? (
            <ChevronUp className="h-4 w-4 text-gray-400" />
          ) : (
            <ChevronDown className="h-4 w-4 text-gray-400" />
          )}
        </button>

        {strategyOpen && (
          <div className="bg-white rounded-2xl shadow-sm p-4 mt-2 space-y-4">
            {/* Monthly budget input */}
            <div>
              <label className="block text-xs font-medium text-gray-500 mb-2">
                Monthly Payment Budget: {fmt(sliderBudget)}
              </label>
              <input
                type="range"
                min={totalMinPayment || 100}
                max={Math.max((totalMinPayment || 100) * 5, 3000)}
                step={50}
                value={sliderBudget}
                onChange={(e) => setSliderBudget(parseInt(e.target.value))}
                className="w-full h-2 rounded-full appearance-none cursor-pointer
                           bg-gray-200 accent-primary-500"
              />
              <div className="flex justify-between text-[10px] text-gray-400 mt-1">
                <span>{fmt(totalMinPayment || 100)}</span>
                <span>
                  {fmt(Math.max((totalMinPayment || 100) * 5, 3000))}
                </span>
              </div>
            </div>

            {/* Strategy summary cards */}
            {strategiesLoading ? (
              <div className="flex justify-center py-6">
                <Loader2 className="h-6 w-6 animate-spin text-gray-300" />
              </div>
            ) : strategies.length > 0 ? (
              <>
                <div className="grid grid-cols-2 gap-2">
                  {strategies.map((s) => (
                    <div
                      key={s.strategy}
                      className="rounded-xl border border-gray-100 p-3"
                      style={{
                        borderLeftWidth: "3px",
                        borderLeftColor:
                          STRATEGY_COLORS[s.strategy] ?? "#94A3B8",
                      }}
                    >
                      <p className="text-[11px] font-medium text-gray-500 capitalize">
                        {s.strategy.replace(/_/g, " ")}
                      </p>
                      <p className="text-sm font-bold text-gray-800 mt-0.5">
                        {s.months_to_freedom} months
                      </p>
                      <p className="text-[11px] text-gray-400">
                        {fmt(s.total_interest)} interest
                      </p>
                    </div>
                  ))}
                </div>

                {/* Line chart */}
                <div className="h-56 w-full mt-2">
                  <ResponsiveContainer width="100%" height="100%">
                    <LineChart data={chartData}>
                      <CartesianGrid
                        strokeDasharray="3 3"
                        stroke="#E5E7EB"
                      />
                      <XAxis
                        dataKey="month"
                        tick={{ fontSize: 11 }}
                        label={{
                          value: "Months",
                          position: "insideBottom",
                          offset: -5,
                          style: { fontSize: 11, fill: "#9CA3AF" },
                        }}
                      />
                      <YAxis
                        tick={{ fontSize: 11 }}
                        tickFormatter={(v: number) => `$${(v / 1000).toFixed(0)}k`}
                      />
                      <Tooltip
                        formatter={(value: number, name: string) => [
                          fmt(value),
                          STRATEGY_LABELS[name] ?? name,
                        ]}
                        contentStyle={{
                          borderRadius: "8px",
                          fontSize: "12px",
                          border: "none",
                          boxShadow: "0 2px 8px rgba(0,0,0,0.1)",
                        }}
                      />
                      <Legend
                        formatter={(value: string) =>
                          value.replace(/_/g, " ")
                        }
                        wrapperStyle={{ fontSize: "11px" }}
                      />
                      {strategies.map((s) => (
                        <Line
                          key={s.strategy}
                          type="monotone"
                          dataKey={s.strategy}
                          stroke={
                            STRATEGY_COLORS[s.strategy] ?? "#94A3B8"
                          }
                          strokeWidth={2}
                          dot={false}
                        />
                      ))}
                    </LineChart>
                  </ResponsiveContainer>
                </div>
              </>
            ) : (
              <p className="text-center text-sm text-gray-400 py-4">
                No strategy data available. Add some debts first.
              </p>
            )}
          </div>
        )}
      </div>

      <Navigation />
    </div>
  );
}
