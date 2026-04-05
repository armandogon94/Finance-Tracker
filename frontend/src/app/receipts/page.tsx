"use client";

import React, { useState, useEffect, useCallback, useMemo } from "react";
import { useRouter } from "next/navigation";
import {
  FileText,
  Download,
  X,
  Loader2,
  ChevronDown,
  Calendar,
  DollarSign,
  Image as ImageIcon,
} from "lucide-react";
import { api } from "@/lib/api";
import { useAuth } from "@/contexts/AuthContext";
import Navigation from "@/components/Navigation";
import type { Expense } from "@/types";

// ─── Helpers ────────────────────────────────────────────────────────

function fmt(n: number): string {
  return n.toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
  });
}

const API_BASE = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8002";

const MONTHS = [
  { value: "", label: "All Months" },
  { value: "1", label: "January" },
  { value: "2", label: "February" },
  { value: "3", label: "March" },
  { value: "4", label: "April" },
  { value: "5", label: "May" },
  { value: "6", label: "June" },
  { value: "7", label: "July" },
  { value: "8", label: "August" },
  { value: "9", label: "September" },
  { value: "10", label: "October" },
  { value: "11", label: "November" },
  { value: "12", label: "December" },
];

function getYearOptions(): { value: string; label: string }[] {
  const currentYear = new Date().getFullYear();
  const years = [{ value: "", label: "All Years" }];
  for (let y = currentYear; y >= currentYear - 5; y--) {
    years.push({ value: String(y), label: String(y) });
  }
  return years;
}

// ─── Component ──────────────────────────────────────────────────────

export default function ReceiptsPage() {
  const router = useRouter();
  const { isAuthenticated, isLoading: authLoading } = useAuth();

  const [expenses, setExpenses] = useState<Expense[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Filters
  const [yearFilter, setYearFilter] = useState(String(new Date().getFullYear()));
  const [monthFilter, setMonthFilter] = useState("");
  const [taxDeductibleOnly, setTaxDeductibleOnly] = useState(false);

  // Lightbox
  const [selectedExpense, setSelectedExpense] = useState<Expense | null>(null);

  // Export
  const [exporting, setExporting] = useState(false);

  const yearOptions = useMemo(() => getYearOptions(), []);

  // ── Fetch receipts ──────────────────────────────────────────────

  const fetchReceipts = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      const params: Record<string, string> = {
        has_receipt: "true",
        limit: "200",
        sort: "expense_date:desc",
      };

      if (yearFilter) {
        const startMonth = monthFilter || "1";
        const endMonth = monthFilter || "12";
        params.start_date = `${yearFilter}-${startMonth.padStart(2, "0")}-01`;

        // End of month
        const endYear = parseInt(yearFilter);
        const endMo = parseInt(endMonth);
        const lastDay = new Date(endYear, endMo, 0).getDate();
        params.end_date = `${yearFilter}-${String(endMo).padStart(2, "0")}-${lastDay}`;
      }

      if (taxDeductibleOnly) {
        params.is_tax_deductible = "true";
      }

      const res = await api.getExpenses(params);
      const items: Expense[] = Array.isArray(res) ? res : res?.items ?? [];

      // Filter only those with receipt images
      setExpenses(items.filter((e) => e.receipt_image_path));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load receipts");
    } finally {
      setLoading(false);
    }
  }, [yearFilter, monthFilter, taxDeductibleOnly]);

  // ── Auth guard & initial load ───────────────────────────────────

  useEffect(() => {
    if (authLoading) return;
    if (!isAuthenticated) {
      router.replace("/login");
      return;
    }
    fetchReceipts();
  }, [isAuthenticated, authLoading, router, fetchReceipts]);

  // ── Get receipt image URL ───────────────────────────────────────

  const getReceiptUrl = (path: string): string => {
    if (path.startsWith("http")) return path;
    return `${API_BASE}${path.startsWith("/") ? "" : "/"}${path}`;
  };

  // ── Export for tax ──────────────────────────────────────────────

  const handleExportTax = async () => {
    setExporting(true);
    try {
      const token = localStorage.getItem("access_token");
      const year = yearFilter || new Date().getFullYear();
      const res = await fetch(
        `${API_BASE}/api/v1/receipts/export-tax?year=${year}${
          monthFilter ? `&month=${monthFilter}` : ""
        }`,
        {
          headers: {
            ...(token ? { Authorization: `Bearer ${token}` } : {}),
          },
        }
      );
      if (!res.ok) throw new Error("Export failed");

      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `receipts-${year}${monthFilter ? `-${monthFilter}` : ""}.zip`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    } catch {
      setError("Failed to export receipts");
    } finally {
      setExporting(false);
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

  // ── Render ──────────────────────────────────────────────────────

  return (
    <div className="min-h-screen bg-gray-50 pb-24">
      {/* Header */}
      <header className="bg-primary-500 text-white px-4 pt-6 pb-8 rounded-b-3xl">
        <div className="flex items-center gap-2 mb-1">
          <FileText className="h-5 w-5" />
          <h1 className="text-lg font-semibold">Receipts</h1>
        </div>
        <p className="text-primary-50 text-sm">
          {expenses.length} receipt{expenses.length !== 1 ? "s" : ""} found
        </p>
      </header>

      <div className="px-4 -mt-4 space-y-4">
        {/* Filters */}
        <div className="bg-white rounded-2xl shadow-sm p-4">
          <div className="flex gap-2">
            {/* Year dropdown */}
            <div className="flex-1 relative">
              <select
                value={yearFilter}
                onChange={(e) => setYearFilter(e.target.value)}
                className="w-full rounded-lg border border-gray-200 bg-gray-50 px-3 py-2.5
                           text-sm text-gray-700 appearance-none
                           focus:outline-none focus:ring-2 focus:ring-primary-500"
              >
                {yearOptions.map((y) => (
                  <option key={y.value} value={y.value}>
                    {y.label}
                  </option>
                ))}
              </select>
              <ChevronDown className="absolute right-3 top-1/2 -translate-y-1/2 h-3 w-3 text-gray-400 pointer-events-none" />
            </div>

            {/* Month dropdown */}
            <div className="flex-1 relative">
              <select
                value={monthFilter}
                onChange={(e) => setMonthFilter(e.target.value)}
                className="w-full rounded-lg border border-gray-200 bg-gray-50 px-3 py-2.5
                           text-sm text-gray-700 appearance-none
                           focus:outline-none focus:ring-2 focus:ring-primary-500"
              >
                {MONTHS.map((m) => (
                  <option key={m.value} value={m.value}>
                    {m.label}
                  </option>
                ))}
              </select>
              <ChevronDown className="absolute right-3 top-1/2 -translate-y-1/2 h-3 w-3 text-gray-400 pointer-events-none" />
            </div>
          </div>

          {/* Tax deductible toggle */}
          <div className="flex items-center justify-between mt-3 pt-3 border-t border-gray-100">
            <span className="text-sm text-gray-600">Tax Deductible Only</span>
            <button
              onClick={() => setTaxDeductibleOnly(!taxDeductibleOnly)}
              className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors
                         ${
                           taxDeductibleOnly
                             ? "bg-primary-500"
                             : "bg-gray-200"
                         }`}
            >
              <span
                className={`inline-block h-4 w-4 rounded-full bg-white transition-transform
                           shadow-sm ${
                             taxDeductibleOnly
                               ? "translate-x-6"
                               : "translate-x-1"
                           }`}
              />
            </button>
          </div>
        </div>

        {/* Export button */}
        <button
          onClick={handleExportTax}
          disabled={exporting || expenses.length === 0}
          className="w-full flex items-center justify-center gap-2 py-3 bg-white rounded-2xl
                     shadow-sm text-sm font-medium text-primary-500
                     hover:bg-primary-50 transition-colors
                     disabled:opacity-60 disabled:cursor-not-allowed"
        >
          {exporting ? (
            <>
              <Loader2 className="h-4 w-4 animate-spin" />
              Exporting...
            </>
          ) : (
            <>
              <Download className="h-4 w-4" />
              Export for Tax ({expenses.length} receipts)
            </>
          )}
        </button>

        {/* Receipt grid */}
        {loading ? (
          <div className="flex justify-center py-12">
            <Loader2 className="h-6 w-6 animate-spin text-gray-300" />
          </div>
        ) : error ? (
          <div className="bg-white rounded-2xl shadow-sm p-6 text-center">
            <p className="text-sm text-red-500">{error}</p>
            <button
              onClick={fetchReceipts}
              className="mt-3 text-sm text-primary-500 font-medium"
            >
              Try again
            </button>
          </div>
        ) : expenses.length === 0 ? (
          <div className="bg-white rounded-2xl shadow-sm p-8 text-center">
            <ImageIcon className="h-10 w-10 text-gray-300 mx-auto mb-3" />
            <p className="text-sm text-gray-500 font-medium">
              No receipts found
            </p>
            <p className="text-xs text-gray-400 mt-1">
              {taxDeductibleOnly
                ? "No tax deductible receipts for this period"
                : "Scan receipts when adding expenses to see them here"}
            </p>
          </div>
        ) : (
          <div className="grid grid-cols-3 sm:grid-cols-4 gap-2">
            {expenses.map((exp) => (
              <button
                key={exp.id}
                onClick={() => setSelectedExpense(exp)}
                className="relative aspect-[3/4] rounded-xl overflow-hidden bg-gray-100
                           shadow-sm hover:shadow-md transition-shadow group"
              >
                {/* Thumbnail */}
                {exp.receipt_image_path ? (
                  <img
                    src={getReceiptUrl(exp.receipt_image_path)}
                    alt="Receipt"
                    className="w-full h-full object-cover"
                    loading="lazy"
                  />
                ) : (
                  <div className="w-full h-full flex items-center justify-center">
                    <FileText className="h-8 w-8 text-gray-300" />
                  </div>
                )}

                {/* Overlay with date & amount */}
                <div className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/70 to-transparent
                                p-2 pt-6">
                  <p className="text-[10px] text-white/80">
                    {new Date(exp.expense_date).toLocaleDateString("en-US", {
                      month: "short",
                      day: "numeric",
                    })}
                  </p>
                  <p className="text-xs font-bold text-white">
                    {fmt(exp.amount)}
                  </p>
                </div>

                {/* Tax deductible badge */}
                {exp.is_tax_deductible && (
                  <div className="absolute top-1.5 right-1.5 h-5 w-5 rounded-full bg-green-500
                                  flex items-center justify-center">
                    <DollarSign className="h-3 w-3 text-white" />
                  </div>
                )}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Lightbox / detail view */}
      {selectedExpense && (
        <div
          className="fixed inset-0 z-50 bg-black/80 flex items-center justify-center p-4"
          onClick={() => setSelectedExpense(null)}
        >
          <div
            className="bg-white rounded-2xl max-w-lg w-full max-h-[90vh] overflow-y-auto"
            onClick={(e) => e.stopPropagation()}
          >
            {/* Close button */}
            <div className="flex justify-end p-3">
              <button
                onClick={() => setSelectedExpense(null)}
                className="h-8 w-8 rounded-full bg-gray-100 flex items-center justify-center
                           text-gray-500 hover:bg-gray-200 transition-colors"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            {/* Receipt image */}
            {selectedExpense.receipt_image_path && (
              <div className="px-4">
                <img
                  src={getReceiptUrl(selectedExpense.receipt_image_path)}
                  alt="Receipt"
                  className="w-full rounded-xl object-contain max-h-[50vh]"
                />
              </div>
            )}

            {/* Expense details */}
            <div className="p-4 space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-xl font-bold text-gray-800">
                  {fmt(selectedExpense.amount)}
                </span>
                {selectedExpense.is_tax_deductible && (
                  <span className="inline-flex items-center gap-1 text-xs font-medium
                                   text-green-600 bg-green-50 px-2 py-1 rounded-full">
                    <DollarSign className="h-3 w-3" />
                    Tax Deductible
                  </span>
                )}
              </div>

              <div className="space-y-2 text-sm">
                {selectedExpense.merchant_name && (
                  <div className="flex items-center gap-2">
                    <span className="text-gray-400 w-20">Merchant</span>
                    <span className="text-gray-700 font-medium">
                      {selectedExpense.merchant_name}
                    </span>
                  </div>
                )}

                {selectedExpense.description && (
                  <div className="flex items-center gap-2">
                    <span className="text-gray-400 w-20">Note</span>
                    <span className="text-gray-700">
                      {selectedExpense.description}
                    </span>
                  </div>
                )}

                <div className="flex items-center gap-2">
                  <span className="text-gray-400 w-20">Date</span>
                  <span className="text-gray-700">
                    <Calendar className="h-3.5 w-3.5 inline mr-1" />
                    {new Date(selectedExpense.expense_date).toLocaleDateString(
                      "en-US",
                      {
                        weekday: "short",
                        month: "long",
                        day: "numeric",
                        year: "numeric",
                      }
                    )}
                  </span>
                </div>

                {selectedExpense.tax_amount != null && (
                  <div className="flex items-center gap-2">
                    <span className="text-gray-400 w-20">Tax</span>
                    <span className="text-gray-700">
                      {fmt(selectedExpense.tax_amount)}
                    </span>
                  </div>
                )}

                {selectedExpense.ocr_method && (
                  <div className="flex items-center gap-2">
                    <span className="text-gray-400 w-20">OCR</span>
                    <span className="text-xs text-gray-500 bg-gray-100 px-2 py-0.5 rounded">
                      {selectedExpense.ocr_method}
                    </span>
                  </div>
                )}

                {selectedExpense.tags?.length > 0 && (
                  <div className="flex items-start gap-2">
                    <span className="text-gray-400 w-20 mt-0.5">Tags</span>
                    <div className="flex flex-wrap gap-1">
                      {selectedExpense.tags.map((tag) => (
                        <span
                          key={tag}
                          className="text-xs bg-primary-50 text-primary-600 px-2 py-0.5 rounded-full"
                        >
                          {tag}
                        </span>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      <Navigation />
    </div>
  );
}
