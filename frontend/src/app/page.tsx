"use client";

import React, { useState, useEffect, useCallback } from "react";
import { useRouter } from "next/navigation";
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip } from "recharts";
import { DollarSign, TrendingUp, Calendar, Clock } from "lucide-react";
import { api } from "@/lib/api";
import { useAuth } from "@/contexts/AuthContext";
import QuickAddModal from "@/components/QuickAddModal";
import Navigation from "@/components/Navigation";
import type { Expense, Category } from "@/types";

// ─── Helpers ────────────────────────────────────────────────────────

function startOfDay(d: Date): Date {
  const copy = new Date(d);
  copy.setHours(0, 0, 0, 0);
  return copy;
}

function startOfWeek(d: Date): Date {
  const copy = startOfDay(d);
  const day = copy.getDay(); // 0 = Sun
  copy.setDate(copy.getDate() - day);
  return copy;
}

function startOfMonth(d: Date): Date {
  const copy = new Date(d);
  copy.setDate(1);
  copy.setHours(0, 0, 0, 0);
  return copy;
}

function fmt(n: number): string {
  return n.toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
  });
}

const CHART_COLORS = [
  "#3B82F6",
  "#10B981",
  "#F59E0B",
  "#EF4444",
  "#8B5CF6",
  "#EC4899",
];

// ─── Component ──────────────────────────────────────────────────────

export default function DashboardPage() {
  const router = useRouter();
  const { user, isAuthenticated, isLoading: authLoading } = useAuth();

  const [expenses, setExpenses] = useState<Expense[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [loading, setLoading] = useState(true);
  const [fabOpen, setFabOpen] = useState(false);

  // ── Fetch data ──────────────────────────────────────────────────

  const fetchData = useCallback(async () => {
    try {
      setLoading(true);
      const [expRes, catRes] = await Promise.all([
        api.getExpenses({ limit: "100", sort: "expense_date:desc" }),
        api.getCategories(),
      ]);
      // The API may return { items: [...] } or just an array
      const expList: Expense[] = Array.isArray(expRes)
        ? expRes
        : expRes?.items ?? [];
      setExpenses(expList);
      setCategories(Array.isArray(catRes) ? catRes : []);
    } catch {
      // silently handle
    } finally {
      setLoading(false);
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

  // ── Derived data ────────────────────────────────────────────────

  const now = new Date();
  const todayStart = startOfDay(now);
  const weekStart = startOfWeek(now);
  const monthStart = startOfMonth(now);

  const todayTotal = expenses
    .filter((e) => new Date(e.expense_date) >= todayStart)
    .reduce((s, e) => s + e.amount, 0);

  const weekTotal = expenses
    .filter((e) => new Date(e.expense_date) >= weekStart)
    .reduce((s, e) => s + e.amount, 0);

  const monthTotal = expenses
    .filter((e) => new Date(e.expense_date) >= monthStart)
    .reduce((s, e) => s + e.amount, 0);

  // Top 3 categories this month
  const monthExpenses = expenses.filter(
    (e) => new Date(e.expense_date) >= monthStart
  );

  const categoryTotals: Record<string, number> = {};
  monthExpenses.forEach((e) => {
    categoryTotals[e.category_id] =
      (categoryTotals[e.category_id] || 0) + e.amount;
  });

  const categoryMap = new Map(categories.map((c) => [c.id, c]));

  const top3 = Object.entries(categoryTotals)
    .sort(([, a], [, b]) => b - a)
    .slice(0, 3)
    .map(([catId, total]) => ({
      name: categoryMap.get(catId)?.name ?? "Other",
      value: total,
      color: categoryMap.get(catId)?.color ?? "#94A3B8",
    }));

  const recentExpenses = expenses.slice(0, 5);

  // ── Loading / auth guard ────────────────────────────────────────

  if (authLoading || (!isAuthenticated && !loading)) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-500" />
      </div>
    );
  }

  // ── Render ──────────────────────────────────────────────────────

  return (
    <div className="min-h-screen bg-gray-50 pb-24">
      {/* Header */}
      <header className="bg-primary-500 text-white px-4 pt-6 pb-8 rounded-b-3xl">
        <h1 className="text-lg font-semibold">
          Hello, {user?.display_name || user?.email?.split("@")[0] || "there"}
        </h1>
        <p className="text-primary-50 text-sm mt-0.5">
          Track your spending today
        </p>
      </header>

      {/* Summary cards */}
      <div className="px-4 -mt-4">
        <div className="grid grid-cols-3 gap-3">
          <SummaryCard
            icon={<Clock className="h-4 w-4" />}
            label="Today"
            value={fmt(todayTotal)}
            color="bg-blue-50 text-blue-600"
          />
          <SummaryCard
            icon={<Calendar className="h-4 w-4" />}
            label="This Week"
            value={fmt(weekTotal)}
            color="bg-green-50 text-green-600"
          />
          <SummaryCard
            icon={<TrendingUp className="h-4 w-4" />}
            label="This Month"
            value={fmt(monthTotal)}
            color="bg-purple-50 text-purple-600"
          />
        </div>
      </div>

      {/* Mini pie chart */}
      {top3.length > 0 && (
        <div className="px-4 mt-6">
          <h2 className="text-sm font-semibold text-gray-700 mb-3">
            Top Categories This Month
          </h2>
          <div className="bg-white rounded-2xl shadow-sm p-4 flex items-center gap-4">
            <div className="w-28 h-28 flex-shrink-0">
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <Pie
                    data={top3}
                    cx="50%"
                    cy="50%"
                    innerRadius={25}
                    outerRadius={45}
                    dataKey="value"
                    stroke="none"
                  >
                    {top3.map((entry, i) => (
                      <Cell
                        key={entry.name}
                        fill={entry.color || CHART_COLORS[i]}
                      />
                    ))}
                  </Pie>
                  <Tooltip
                    formatter={(value: number) => fmt(value)}
                    contentStyle={{
                      borderRadius: "8px",
                      fontSize: "12px",
                      border: "none",
                      boxShadow: "0 2px 8px rgba(0,0,0,0.1)",
                    }}
                  />
                </PieChart>
              </ResponsiveContainer>
            </div>
            <div className="flex-1 space-y-2">
              {top3.map((cat, i) => (
                <div key={cat.name} className="flex items-center gap-2 text-sm">
                  <span
                    className="h-3 w-3 rounded-full flex-shrink-0"
                    style={{
                      backgroundColor: cat.color || CHART_COLORS[i],
                    }}
                  />
                  <span className="text-gray-600 truncate flex-1">
                    {cat.name}
                  </span>
                  <span className="font-medium text-gray-800">
                    {fmt(cat.value)}
                  </span>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Recent expenses */}
      <div className="px-4 mt-6">
        <h2 className="text-sm font-semibold text-gray-700 mb-3">
          Recent Expenses
        </h2>
        <div className="bg-white rounded-2xl shadow-sm divide-y divide-gray-100">
          {loading ? (
            <div className="p-6 text-center text-gray-400 text-sm">
              Loading...
            </div>
          ) : recentExpenses.length === 0 ? (
            <div className="p-6 text-center text-gray-400 text-sm">
              No expenses yet. Tap + to add one!
            </div>
          ) : (
            recentExpenses.map((exp) => {
              const cat = categoryMap.get(exp.category_id);
              return (
                <div
                  key={exp.id}
                  className="flex items-center gap-3 px-4 py-3"
                >
                  <div
                    className="h-9 w-9 rounded-full flex items-center justify-center text-sm flex-shrink-0"
                    style={{
                      backgroundColor: (cat?.color ?? "#94A3B8") + "20",
                      color: cat?.color ?? "#94A3B8",
                    }}
                  >
                    {cat?.icon ?? <DollarSign className="h-4 w-4" />}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-gray-800 truncate">
                      {exp.merchant_name || exp.description || cat?.name || "Expense"}
                    </p>
                    <p className="text-xs text-gray-400">
                      {new Date(exp.expense_date).toLocaleDateString("en-US", {
                        month: "short",
                        day: "numeric",
                      })}
                    </p>
                  </div>
                  <span className="text-sm font-semibold text-gray-800">
                    {fmt(exp.amount)}
                  </span>
                </div>
              );
            })
          )}
        </div>
      </div>

      {/* FAB */}
      <button
        onClick={() => setFabOpen(true)}
        className="fixed bottom-20 right-4 z-30 h-14 w-14 rounded-full bg-primary-500 text-white shadow-lg
                   flex items-center justify-center text-2xl font-light
                   hover:bg-primary-600 active:scale-95 transition-all
                   sm:bottom-24 sm:right-6"
        aria-label="Add expense"
      >
        +
      </button>

      {/* Quick add modal */}
      <QuickAddModal
        isOpen={fabOpen}
        onClose={() => setFabOpen(false)}
        onSaved={() => {
          setFabOpen(false);
          fetchData();
        }}
      />

      <Navigation />
    </div>
  );
}

// ─── Sub-components ─────────────────────────────────────────────────

function SummaryCard({
  icon,
  label,
  value,
  color,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
  color: string;
}) {
  return (
    <div className="bg-white rounded-2xl shadow-sm p-3 flex flex-col items-start gap-1">
      <div
        className={`h-7 w-7 rounded-lg flex items-center justify-center ${color}`}
      >
        {icon}
      </div>
      <span className="text-[11px] text-gray-400 font-medium">{label}</span>
      <span className="text-sm font-bold text-gray-800 truncate w-full">
        {value}
      </span>
    </div>
  );
}
