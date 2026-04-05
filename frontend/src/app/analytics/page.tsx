"use client";

import React, { useState, useEffect, useCallback, useMemo } from "react";
import { useRouter } from "next/navigation";
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
} from "recharts";
import {
  BarChart3,
  TrendingUp,
  TrendingDown,
  Loader2,
} from "lucide-react";
import { api } from "@/lib/api";
import { useAuth } from "@/contexts/AuthContext";
import Navigation from "@/components/Navigation";

// ─── Helpers ────────────────────────────────────────────────────────

function fmt(n: number): string {
  return n.toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

function fmtShort(n: number): string {
  if (n >= 1000) return `$${(n / 1000).toFixed(1)}k`;
  return `$${n.toFixed(0)}`;
}

const CHART_COLORS = [
  "#3B82F6", "#10B981", "#F59E0B", "#EF4444", "#8B5CF6",
  "#EC4899", "#14B8A6", "#F97316", "#6366F1", "#84CC16",
];

type Period = "day" | "week" | "month" | "year";

function getDateRange(period: Period): { start: string; end: string } {
  const now = new Date();
  const end = now.toISOString().split("T")[0];
  const start = new Date(now);

  switch (period) {
    case "day":
      start.setDate(start.getDate() - 1);
      break;
    case "week":
      start.setDate(start.getDate() - 7);
      break;
    case "month":
      start.setMonth(start.getMonth() - 1);
      break;
    case "year":
      start.setFullYear(start.getFullYear() - 1);
      break;
  }

  return { start: start.toISOString().split("T")[0], end };
}

function getPreviousDateRange(period: Period): { start: string; end: string } {
  const now = new Date();

  switch (period) {
    case "day": {
      const end = new Date(now);
      end.setDate(end.getDate() - 1);
      const start = new Date(end);
      start.setDate(start.getDate() - 1);
      return { start: start.toISOString().split("T")[0], end: end.toISOString().split("T")[0] };
    }
    case "week": {
      const end = new Date(now);
      end.setDate(end.getDate() - 7);
      const start = new Date(end);
      start.setDate(start.getDate() - 7);
      return { start: start.toISOString().split("T")[0], end: end.toISOString().split("T")[0] };
    }
    case "month": {
      const end = new Date(now);
      end.setMonth(end.getMonth() - 1);
      const start = new Date(end);
      start.setMonth(start.getMonth() - 1);
      return { start: start.toISOString().split("T")[0], end: end.toISOString().split("T")[0] };
    }
    case "year": {
      const end = new Date(now);
      end.setFullYear(end.getFullYear() - 1);
      const start = new Date(end);
      start.setFullYear(start.getFullYear() - 1);
      return { start: start.toISOString().split("T")[0], end: end.toISOString().split("T")[0] };
    }
  }
}

const PERIOD_LABELS: Record<Period, string> = {
  day: "Day",
  week: "Week",
  month: "Month",
  year: "Year",
};

const PERIOD_COMPARE_LABELS: Record<Period, string> = {
  day: "vs yesterday",
  week: "vs last week",
  month: "vs last month",
  year: "vs last year",
};

// ─── Component ──────────────────────────────────────────────────────

export default function AnalyticsPage() {
  const router = useRouter();
  const { isAuthenticated, isLoading: authLoading } = useAuth();

  const [period, setPeriod] = useState<Period>("month");
  const [dailyData, setDailyData] = useState<any[]>([]);
  const [categoryData, setCategoryData] = useState<any[]>([]);
  const [budgetStatus, setBudgetStatus] = useState<any[]>([]);
  const [previousTotal, setPreviousTotal] = useState<number>(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // ── Fetch data ──────────────────────────────────────────────────

  const fetchAnalytics = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      const { start, end } = getDateRange(period);
      const prev = getPreviousDateRange(period);

      const [daily, byCategory, budget, prevDaily] = await Promise.all([
        api.getAnalyticsDaily(start, end),
        api.getAnalyticsByCategory(start, end),
        api.getBudgetStatus(),
        api.getAnalyticsDaily(prev.start, prev.end),
      ]);

      setDailyData(Array.isArray(daily) ? daily : daily?.data ?? []);
      setCategoryData(Array.isArray(byCategory) ? byCategory : byCategory?.data ?? []);
      setBudgetStatus(Array.isArray(budget) ? budget : budget?.categories ?? []);

      const prevArr = Array.isArray(prevDaily) ? prevDaily : prevDaily?.data ?? [];
      const prevTotal = prevArr.reduce(
        (s: number, d: any) => s + (d.total ?? d.amount ?? 0),
        0
      );
      setPreviousTotal(prevTotal);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load analytics");
    } finally {
      setLoading(false);
    }
  }, [period]);

  useEffect(() => {
    if (authLoading) return;
    if (!isAuthenticated) {
      router.replace("/login");
      return;
    }
    fetchAnalytics();
  }, [isAuthenticated, authLoading, router, fetchAnalytics]);

  // ── Derived values ──────────────────────────────────────────────

  const currentTotal = useMemo(
    () => dailyData.reduce((s, d) => s + (d.total ?? d.amount ?? 0), 0),
    [dailyData]
  );

  const percentChange = useMemo(() => {
    if (previousTotal === 0) return null;
    return ((currentTotal - previousTotal) / previousTotal) * 100;
  }, [currentTotal, previousTotal]);

  const chartData = useMemo(
    () =>
      dailyData.map((d) => ({
        date: d.date
          ? new Date(d.date).toLocaleDateString("en-US", {
              month: "short",
              day: "numeric",
            })
          : "",
        amount: d.total ?? d.amount ?? 0,
      })),
    [dailyData]
  );

  const donutData = useMemo(
    () =>
      categoryData.map((d: any, i: number) => ({
        name: d.category_name ?? d.name ?? "Other",
        value: d.total ?? d.amount ?? 0,
        color: d.color ?? CHART_COLORS[i % CHART_COLORS.length],
      })),
    [categoryData]
  );

  // ── Auth guard ────────────────────────────────────────────────────

  if (authLoading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <Loader2 className="h-8 w-8 animate-spin text-primary-500" />
      </div>
    );
  }

  // ── Render ──────────────────────────────────────────────────────

  return (
    <div className="min-h-screen bg-gray-50 pb-24">
      {/* Header */}
      <header className="bg-primary-500 text-white px-4 pt-6 pb-8 rounded-b-3xl">
        <div className="flex items-center gap-2 mb-1">
          <BarChart3 className="h-5 w-5" />
          <h1 className="text-lg font-semibold">Analytics</h1>
        </div>
        <p className="text-primary-50 text-sm">Understand your spending</p>
      </header>

      {/* Period tabs */}
      <div className="px-4 -mt-4">
        <div className="bg-white rounded-2xl shadow-sm p-1.5 flex gap-1">
          {(["day", "week", "month", "year"] as Period[]).map((p) => (
            <button
              key={p}
              onClick={() => setPeriod(p)}
              className={`flex-1 py-2 rounded-xl text-xs font-semibold transition-colors
                         ${
                           period === p
                             ? "bg-primary-500 text-white"
                             : "text-gray-500 hover:bg-gray-50"
                         }`}
            >
              {PERIOD_LABELS[p]}
            </button>
          ))}
        </div>
      </div>

      {loading ? (
        <div className="flex justify-center py-16">
          <Loader2 className="h-6 w-6 animate-spin text-gray-300" />
        </div>
      ) : error ? (
        <div className="px-4 mt-6">
          <div className="bg-white rounded-2xl shadow-sm p-6 text-center">
            <p className="text-sm text-red-500">{error}</p>
            <button
              onClick={fetchAnalytics}
              className="mt-3 text-sm text-primary-500 font-medium"
            >
              Try again
            </button>
          </div>
        </div>
      ) : (
        <>
          {/* Total spending card with comparison */}
          <div className="px-4 mt-4">
            <div className="bg-white rounded-2xl shadow-sm p-5">
              <p className="text-xs text-gray-400 font-medium">
                Total Spending
              </p>
              <div className="flex items-end gap-3 mt-1">
                <span className="text-2xl font-bold text-gray-800">
                  {fmt(currentTotal)}
                </span>
                {percentChange !== null && (
                  <span
                    className={`flex items-center gap-0.5 text-xs font-semibold pb-0.5 ${
                      percentChange > 0
                        ? "text-red-500"
                        : percentChange < 0
                        ? "text-green-500"
                        : "text-gray-400"
                    }`}
                  >
                    {percentChange > 0 ? (
                      <TrendingUp className="h-3 w-3" />
                    ) : percentChange < 0 ? (
                      <TrendingDown className="h-3 w-3" />
                    ) : null}
                    {percentChange > 0 ? "+" : ""}
                    {percentChange.toFixed(0)}%{" "}
                    <span className="font-normal text-gray-400">
                      {PERIOD_COMPARE_LABELS[period]}
                    </span>
                  </span>
                )}
              </div>
            </div>
          </div>

          {/* Spending over time bar chart */}
          {chartData.length > 0 && (
            <div className="px-4 mt-4">
              <div className="bg-white rounded-2xl shadow-sm p-4">
                <h2 className="text-sm font-semibold text-gray-700 mb-3">
                  Spending Over Time
                </h2>
                <div className="h-48 w-full">
                  <ResponsiveContainer width="100%" height="100%">
                    <BarChart data={chartData}>
                      <CartesianGrid strokeDasharray="3 3" stroke="#F3F4F6" />
                      <XAxis
                        dataKey="date"
                        tick={{ fontSize: 10 }}
                        tickLine={false}
                        axisLine={{ stroke: "#E5E7EB" }}
                      />
                      <YAxis
                        tick={{ fontSize: 10 }}
                        tickFormatter={fmtShort}
                        tickLine={false}
                        axisLine={false}
                        width={45}
                      />
                      <Tooltip
                        formatter={(value: number) => [fmt(value), "Spent"]}
                        contentStyle={{
                          borderRadius: "8px",
                          fontSize: "12px",
                          border: "none",
                          boxShadow: "0 2px 8px rgba(0,0,0,0.1)",
                        }}
                      />
                      <Bar
                        dataKey="amount"
                        fill="#3B82F6"
                        radius={[4, 4, 0, 0]}
                        maxBarSize={32}
                      />
                    </BarChart>
                  </ResponsiveContainer>
                </div>
              </div>
            </div>
          )}

          {/* Category breakdown donut chart */}
          {donutData.length > 0 && (
            <div className="px-4 mt-4">
              <div className="bg-white rounded-2xl shadow-sm p-4">
                <h2 className="text-sm font-semibold text-gray-700 mb-3">
                  By Category
                </h2>
                <div className="flex items-center gap-4">
                  <div className="w-32 h-32 flex-shrink-0">
                    <ResponsiveContainer width="100%" height="100%">
                      <PieChart>
                        <Pie
                          data={donutData}
                          cx="50%"
                          cy="50%"
                          innerRadius={30}
                          outerRadius={55}
                          dataKey="value"
                          stroke="none"
                        >
                          {donutData.map((entry, i) => (
                            <Cell
                              key={entry.name}
                              fill={entry.color || CHART_COLORS[i % CHART_COLORS.length]}
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
                  <div className="flex-1 space-y-2 overflow-hidden">
                    {donutData.slice(0, 6).map((cat, i) => (
                      <div key={cat.name} className="flex items-center gap-2 text-sm">
                        <span
                          className="h-3 w-3 rounded-full flex-shrink-0"
                          style={{
                            backgroundColor:
                              cat.color || CHART_COLORS[i % CHART_COLORS.length],
                          }}
                        />
                        <span className="text-gray-600 truncate flex-1">
                          {cat.name}
                        </span>
                        <span className="font-medium text-gray-800 flex-shrink-0">
                          {fmt(cat.value)}
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* Budget progress bars */}
          {budgetStatus.length > 0 && (
            <div className="px-4 mt-4">
              <div className="bg-white rounded-2xl shadow-sm p-4">
                <h2 className="text-sm font-semibold text-gray-700 mb-3">
                  Budget Progress
                </h2>
                <div className="space-y-4">
                  {budgetStatus.map((b: any, i: number) => {
                    const spent = b.spent ?? b.amount ?? 0;
                    const budget = b.budget ?? b.monthly_budget ?? 0;
                    const pct = budget > 0 ? (spent / budget) * 100 : 0;
                    const barColor =
                      pct >= 100
                        ? "bg-red-500"
                        : pct >= 75
                        ? "bg-yellow-500"
                        : "bg-green-500";

                    return (
                      <div key={b.category_id ?? i}>
                        <div className="flex items-center justify-between mb-1">
                          <span className="text-sm text-gray-700 font-medium truncate">
                            {b.category_name ?? b.name ?? "Category"}
                          </span>
                          <span className="text-xs text-gray-500 flex-shrink-0">
                            {fmt(spent)} / {fmt(budget)}
                          </span>
                        </div>
                        <div className="h-2.5 rounded-full bg-gray-100 overflow-hidden">
                          <div
                            className={`h-full rounded-full transition-all ${barColor}`}
                            style={{ width: `${Math.min(pct, 100)}%` }}
                          />
                        </div>
                        <p className="text-[11px] text-gray-400 mt-0.5">
                          {pct.toFixed(0)}% used
                          {pct >= 100 && (
                            <span className="text-red-500 font-medium">
                              {" "}
                              &mdash; Over budget by {fmt(spent - budget)}
                            </span>
                          )}
                        </p>
                      </div>
                    );
                  })}
                </div>
              </div>
            </div>
          )}

          {/* Empty state */}
          {dailyData.length === 0 && categoryData.length === 0 && (
            <div className="px-4 mt-6">
              <div className="bg-white rounded-2xl shadow-sm p-8 text-center">
                <BarChart3 className="h-10 w-10 text-gray-300 mx-auto mb-3" />
                <p className="text-sm text-gray-500 font-medium">
                  No data for this period
                </p>
                <p className="text-xs text-gray-400 mt-1">
                  Add some expenses to see your analytics
                </p>
              </div>
            </div>
          )}
        </>
      )}

      <Navigation />
    </div>
  );
}
