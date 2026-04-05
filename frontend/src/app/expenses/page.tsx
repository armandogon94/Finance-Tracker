"use client";

import React, { useState, useEffect, useCallback, useRef } from "react";
import { useRouter } from "next/navigation";
import {
  Search,
  X,
  ChevronDown,
  Trash2,
  Loader2,
  Receipt,
  Calendar,
  Filter,
} from "lucide-react";
import { api } from "@/lib/api";
import { useAuth } from "@/contexts/AuthContext";
import Navigation from "@/components/Navigation";
import type { Expense, Category } from "@/types";

// ─── Helpers ────────────────────────────────────────────────────────

function fmt(n: number): string {
  return n.toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
  });
}

function startOfDay(d: Date): Date {
  const copy = new Date(d);
  copy.setHours(0, 0, 0, 0);
  return copy;
}

function isSameDay(a: Date, b: Date): boolean {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

function getDateGroup(dateStr: string): string {
  const d = new Date(dateStr);
  const now = new Date();
  const today = startOfDay(now);
  const yesterday = new Date(today);
  yesterday.setDate(yesterday.getDate() - 1);
  const weekAgo = new Date(today);
  weekAgo.setDate(weekAgo.getDate() - 7);

  if (isSameDay(d, today)) return "Today";
  if (isSameDay(d, yesterday)) return "Yesterday";
  if (d >= weekAgo) return "This Week";
  return "Earlier";
}

const DATE_GROUP_ORDER = ["Today", "Yesterday", "This Week", "Earlier"];

// ─── Component ──────────────────────────────────────────────────────

export default function ExpensesPage() {
  const router = useRouter();
  const { isAuthenticated, isLoading: authLoading } = useAuth();

  const [expenses, setExpenses] = useState<Expense[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);
  const [page, setPage] = useState(1);
  const pageSize = 30;

  // Filters
  const [search, setSearch] = useState("");
  const [categoryFilter, setCategoryFilter] = useState("");
  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");
  const [amountMin, setAmountMin] = useState("");
  const [amountMax, setAmountMax] = useState("");
  const [showFilters, setShowFilters] = useState(false);

  // Swipe-to-delete
  const [swipedId, setSwipedId] = useState<string | null>(null);
  const [deleting, setDeleting] = useState<string | null>(null);

  const searchTimeout = useRef<NodeJS.Timeout | null>(null);

  // ── Build query params ──────────────────────────────────────────

  const buildParams = useCallback(
    (pageNum: number): Record<string, string> => {
      const params: Record<string, string> = {
        limit: String(pageSize),
        offset: String((pageNum - 1) * pageSize),
        sort: "expense_date:desc",
      };
      if (search.trim()) params.search = search.trim();
      if (categoryFilter) params.category_id = categoryFilter;
      if (dateFrom) params.start_date = dateFrom;
      if (dateTo) params.end_date = dateTo;
      if (amountMin) params.amount_min = amountMin;
      if (amountMax) params.amount_max = amountMax;
      return params;
    },
    [search, categoryFilter, dateFrom, dateTo, amountMin, amountMax]
  );

  // ── Fetch expenses ──────────────────────────────────────────────

  const fetchExpenses = useCallback(
    async (pageNum: number, append = false) => {
      try {
        if (!append) setLoading(true);
        else setLoadingMore(true);
        setError(null);

        const params = buildParams(pageNum);
        const res = await api.getExpenses(params);
        const items: Expense[] = Array.isArray(res) ? res : res?.items ?? [];

        if (append) {
          setExpenses((prev) => [...prev, ...items]);
        } else {
          setExpenses(items);
        }
        setHasMore(items.length >= pageSize);
      } catch (err) {
        setError(err instanceof Error ? err.message : "Failed to load expenses");
      } finally {
        setLoading(false);
        setLoadingMore(false);
      }
    },
    [buildParams]
  );

  // ── Fetch categories ────────────────────────────────────────────

  const fetchCategories = useCallback(async () => {
    try {
      const res = await api.getCategories();
      setCategories(Array.isArray(res) ? res : []);
    } catch {
      // ignore
    }
  }, []);

  // ── Auth guard & initial load ───────────────────────────────────

  useEffect(() => {
    if (authLoading) return;
    if (!isAuthenticated) {
      router.replace("/login");
      return;
    }
    fetchCategories();
  }, [isAuthenticated, authLoading, router, fetchCategories]);

  useEffect(() => {
    if (authLoading || !isAuthenticated) return;
    setPage(1);
    fetchExpenses(1, false);
  }, [
    isAuthenticated,
    authLoading,
    search,
    categoryFilter,
    dateFrom,
    dateTo,
    amountMin,
    amountMax,
    fetchExpenses,
  ]);

  // ── Debounced search ────────────────────────────────────────────

  const handleSearchChange = (value: string) => {
    if (searchTimeout.current) clearTimeout(searchTimeout.current);
    searchTimeout.current = setTimeout(() => {
      setSearch(value);
    }, 300);
  };

  // ── Load more ───────────────────────────────────────────────────

  const handleLoadMore = () => {
    const nextPage = page + 1;
    setPage(nextPage);
    fetchExpenses(nextPage, true);
  };

  // ── Delete ──────────────────────────────────────────────────────

  const handleDelete = async (id: string) => {
    setDeleting(id);
    try {
      await api.deleteExpense(id);
      setExpenses((prev) => prev.filter((e) => e.id !== id));
      setSwipedId(null);
    } catch {
      // ignore
    } finally {
      setDeleting(null);
    }
  };

  // ── Group expenses by date ──────────────────────────────────────

  const categoryMap = new Map(categories.map((c) => [c.id, c]));

  const grouped = expenses.reduce<Record<string, Expense[]>>((acc, exp) => {
    const group = getDateGroup(exp.expense_date);
    if (!acc[group]) acc[group] = [];
    acc[group].push(exp);
    return acc;
  }, {});

  // ── Clear all filters ──────────────────────────────────────────

  const clearFilters = () => {
    setSearch("");
    setCategoryFilter("");
    setDateFrom("");
    setDateTo("");
    setAmountMin("");
    setAmountMax("");
  };

  const hasActiveFilters =
    search || categoryFilter || dateFrom || dateTo || amountMin || amountMax;

  // ── Auth loading guard ─────────────────────────────────────────

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
          <Receipt className="h-5 w-5" />
          <h1 className="text-lg font-semibold">Expenses</h1>
        </div>
        <p className="text-primary-50 text-sm">
          {expenses.length} expense{expenses.length !== 1 ? "s" : ""} found
        </p>
      </header>

      {/* Search bar */}
      <div className="px-4 -mt-4">
        <div className="bg-white rounded-2xl shadow-sm">
          <div className="flex items-center gap-2 px-4 py-3">
            <Search className="h-4 w-4 text-gray-400 flex-shrink-0" />
            <input
              type="text"
              placeholder="Search expenses..."
              defaultValue={search}
              onChange={(e) => handleSearchChange(e.target.value)}
              className="flex-1 text-sm text-gray-800 placeholder:text-gray-400
                         bg-transparent outline-none"
            />
            <button
              onClick={() => setShowFilters(!showFilters)}
              className={`h-8 w-8 rounded-lg flex items-center justify-center transition-colors
                         ${
                           showFilters || hasActiveFilters
                             ? "bg-primary-50 text-primary-500"
                             : "text-gray-400 hover:bg-gray-50"
                         }`}
            >
              <Filter className="h-4 w-4" />
            </button>
          </div>

          {/* Filter chips / expanded section */}
          {showFilters && (
            <div className="px-4 pb-4 pt-1 border-t border-gray-100 space-y-3">
              {/* Date range */}
              <div className="flex gap-2">
                <div className="flex-1">
                  <label className="block text-[11px] font-medium text-gray-500 mb-1">
                    From
                  </label>
                  <input
                    type="date"
                    value={dateFrom}
                    onChange={(e) => setDateFrom(e.target.value)}
                    className="w-full rounded-lg border border-gray-200 bg-gray-50 px-3 py-2
                               text-xs text-gray-700 focus:outline-none focus:ring-2
                               focus:ring-primary-500"
                  />
                </div>
                <div className="flex-1">
                  <label className="block text-[11px] font-medium text-gray-500 mb-1">
                    To
                  </label>
                  <input
                    type="date"
                    value={dateTo}
                    onChange={(e) => setDateTo(e.target.value)}
                    className="w-full rounded-lg border border-gray-200 bg-gray-50 px-3 py-2
                               text-xs text-gray-700 focus:outline-none focus:ring-2
                               focus:ring-primary-500"
                  />
                </div>
              </div>

              {/* Category dropdown */}
              <div>
                <label className="block text-[11px] font-medium text-gray-500 mb-1">
                  Category
                </label>
                <div className="relative">
                  <select
                    value={categoryFilter}
                    onChange={(e) => setCategoryFilter(e.target.value)}
                    className="w-full rounded-lg border border-gray-200 bg-gray-50 px-3 py-2
                               text-xs text-gray-700 appearance-none
                               focus:outline-none focus:ring-2 focus:ring-primary-500"
                  >
                    <option value="">All Categories</option>
                    {categories
                      .filter((c) => c.is_active && !c.is_hidden)
                      .map((c) => (
                        <option key={c.id} value={c.id}>
                          {c.name}
                        </option>
                      ))}
                  </select>
                  <ChevronDown className="absolute right-3 top-1/2 -translate-y-1/2 h-3 w-3 text-gray-400 pointer-events-none" />
                </div>
              </div>

              {/* Amount range */}
              <div className="flex gap-2">
                <div className="flex-1">
                  <label className="block text-[11px] font-medium text-gray-500 mb-1">
                    Min Amount
                  </label>
                  <input
                    type="number"
                    min="0"
                    step="0.01"
                    value={amountMin}
                    onChange={(e) => setAmountMin(e.target.value)}
                    placeholder="$0"
                    className="w-full rounded-lg border border-gray-200 bg-gray-50 px-3 py-2
                               text-xs text-gray-700 focus:outline-none focus:ring-2
                               focus:ring-primary-500"
                  />
                </div>
                <div className="flex-1">
                  <label className="block text-[11px] font-medium text-gray-500 mb-1">
                    Max Amount
                  </label>
                  <input
                    type="number"
                    min="0"
                    step="0.01"
                    value={amountMax}
                    onChange={(e) => setAmountMax(e.target.value)}
                    placeholder="No limit"
                    className="w-full rounded-lg border border-gray-200 bg-gray-50 px-3 py-2
                               text-xs text-gray-700 focus:outline-none focus:ring-2
                               focus:ring-primary-500"
                  />
                </div>
              </div>

              {/* Clear filters */}
              {hasActiveFilters && (
                <button
                  onClick={clearFilters}
                  className="flex items-center gap-1 text-xs text-red-500 font-medium"
                >
                  <X className="h-3 w-3" />
                  Clear all filters
                </button>
              )}
            </div>
          )}
        </div>
      </div>

      {/* Active filter chips */}
      {hasActiveFilters && !showFilters && (
        <div className="px-4 mt-3 flex flex-wrap gap-2">
          {categoryFilter && (
            <span className="inline-flex items-center gap-1 bg-primary-50 text-primary-600 text-xs font-medium px-2.5 py-1 rounded-full">
              {categoryMap.get(categoryFilter)?.name ?? "Category"}
              <button onClick={() => setCategoryFilter("")}>
                <X className="h-3 w-3" />
              </button>
            </span>
          )}
          {(dateFrom || dateTo) && (
            <span className="inline-flex items-center gap-1 bg-blue-50 text-blue-600 text-xs font-medium px-2.5 py-1 rounded-full">
              <Calendar className="h-3 w-3" />
              {dateFrom || "..."} - {dateTo || "..."}
              <button
                onClick={() => {
                  setDateFrom("");
                  setDateTo("");
                }}
              >
                <X className="h-3 w-3" />
              </button>
            </span>
          )}
          {(amountMin || amountMax) && (
            <span className="inline-flex items-center gap-1 bg-green-50 text-green-600 text-xs font-medium px-2.5 py-1 rounded-full">
              ${amountMin || "0"} - ${amountMax || "..."}
              <button
                onClick={() => {
                  setAmountMin("");
                  setAmountMax("");
                }}
              >
                <X className="h-3 w-3" />
              </button>
            </span>
          )}
        </div>
      )}

      {/* Expense list grouped by date */}
      <div className="px-4 mt-4 space-y-4">
        {loading ? (
          <div className="flex justify-center py-12">
            <Loader2 className="h-6 w-6 animate-spin text-gray-300" />
          </div>
        ) : error ? (
          <div className="bg-white rounded-2xl shadow-sm p-6 text-center">
            <p className="text-sm text-red-500">{error}</p>
            <button
              onClick={() => fetchExpenses(1, false)}
              className="mt-3 text-sm text-primary-500 font-medium"
            >
              Try again
            </button>
          </div>
        ) : expenses.length === 0 ? (
          <div className="bg-white rounded-2xl shadow-sm p-8 text-center">
            <Receipt className="h-10 w-10 text-gray-300 mx-auto mb-3" />
            <p className="text-sm text-gray-500 font-medium">
              No expenses found
            </p>
            <p className="text-xs text-gray-400 mt-1">
              {hasActiveFilters
                ? "Try adjusting your filters"
                : "Start by adding your first expense"}
            </p>
          </div>
        ) : (
          DATE_GROUP_ORDER.filter((group) => grouped[group]?.length).map(
            (group) => (
              <div key={group}>
                <h2 className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">
                  {group}
                </h2>
                <div className="bg-white rounded-2xl shadow-sm divide-y divide-gray-100 overflow-hidden">
                  {grouped[group].map((exp) => {
                    const cat = categoryMap.get(exp.category_id);
                    const isSwiped = swipedId === exp.id;
                    const isDeleting = deleting === exp.id;

                    return (
                      <div
                        key={exp.id}
                        className="relative overflow-hidden"
                        onClick={() =>
                          setSwipedId(isSwiped ? null : exp.id)
                        }
                      >
                        <div
                          className={`flex items-center gap-3 px-4 py-3 transition-transform duration-200 ${
                            isSwiped ? "-translate-x-16" : "translate-x-0"
                          }`}
                        >
                          {/* Category color dot */}
                          <div
                            className="h-3 w-3 rounded-full flex-shrink-0"
                            style={{
                              backgroundColor: cat?.color ?? "#94A3B8",
                            }}
                          />

                          {/* Description / merchant */}
                          <div className="flex-1 min-w-0">
                            <p className="text-sm font-medium text-gray-800 truncate">
                              {exp.merchant_name ||
                                exp.description ||
                                cat?.name ||
                                "Expense"}
                            </p>
                            <p className="text-xs text-gray-400">
                              {cat?.name ?? "Uncategorized"}
                              {" \u00B7 "}
                              {new Date(exp.expense_date).toLocaleDateString(
                                "en-US",
                                { month: "short", day: "numeric" }
                              )}
                            </p>
                          </div>

                          {/* Amount */}
                          <span className="text-sm font-semibold text-gray-800 flex-shrink-0">
                            {fmt(exp.amount)}
                          </span>
                        </div>

                        {/* Delete button (revealed on swipe/tap) */}
                        {isSwiped && (
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              handleDelete(exp.id);
                            }}
                            disabled={isDeleting}
                            className="absolute right-0 top-0 bottom-0 w-16 bg-red-500 text-white
                                       flex items-center justify-center transition-opacity
                                       disabled:opacity-60"
                          >
                            {isDeleting ? (
                              <Loader2 className="h-4 w-4 animate-spin" />
                            ) : (
                              <Trash2 className="h-4 w-4" />
                            )}
                          </button>
                        )}
                      </div>
                    );
                  })}
                </div>
              </div>
            )
          )
        )}

        {/* Load more button */}
        {!loading && hasMore && expenses.length > 0 && (
          <div className="flex justify-center pt-2 pb-4">
            <button
              onClick={handleLoadMore}
              disabled={loadingMore}
              className="flex items-center gap-2 px-6 py-2.5 bg-white rounded-xl shadow-sm
                         text-sm font-medium text-gray-600 hover:bg-gray-50 transition-colors
                         disabled:opacity-60"
            >
              {loadingMore ? (
                <>
                  <Loader2 className="h-4 w-4 animate-spin" />
                  Loading...
                </>
              ) : (
                "Load More"
              )}
            </button>
          </div>
        )}
      </div>

      <Navigation />
    </div>
  );
}
