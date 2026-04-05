"use client";

import React, { useState, useEffect, useCallback } from "react";
import { useRouter } from "next/navigation";
import { useDropzone } from "react-dropzone";
import {
  Upload,
  FileText,
  AlertTriangle,
  Check,
  ChevronDown,
  Loader2,
  Tag,
  X,
} from "lucide-react";
import { api } from "@/lib/api";
import { useAuth } from "@/contexts/AuthContext";
import Navigation from "@/components/Navigation";
import type { ParsedTransaction, Category } from "@/types";

// ─── Helpers ────────────────────────────────────────────────────────

function fmt(n: number): string {
  return n.toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
  });
}

const BANK_PRESETS = [
  { value: "auto", label: "Auto-detect" },
  { value: "chase", label: "Chase" },
  { value: "bofa", label: "Bank of America" },
  { value: "wells_fargo", label: "Wells Fargo" },
  { value: "citi", label: "Citi" },
  { value: "discover", label: "Discover" },
  { value: "generic", label: "Generic CSV" },
];

// ─── Component ──────────────────────────────────────────────────────

export default function ImportPage() {
  const router = useRouter();
  const { isAuthenticated, isLoading: authLoading } = useAuth();

  const [categories, setCategories] = useState<Category[]>([]);
  const [bankPreset, setBankPreset] = useState("auto");

  // Upload state
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [fileName, setFileName] = useState<string | null>(null);

  // Parsed transactions
  const [transactions, setTransactions] = useState<
    (ParsedTransaction & { id: number; selectedCategoryId: string })[]
  >([]);
  const [importId, setImportId] = useState<string | null>(null);

  // Import confirmation
  const [importing, setImporting] = useState(false);
  const [importSuccess, setImportSuccess] = useState(false);

  // Import history
  const [history, setHistory] = useState<any[]>([]);
  const [historyLoading, setHistoryLoading] = useState(false);

  // ── Fetch categories ────────────────────────────────────────────

  const fetchCategories = useCallback(async () => {
    try {
      const res = await api.getCategories();
      setCategories(Array.isArray(res) ? res : []);
    } catch {
      // ignore
    }
  }, []);

  // ── Fetch import history ────────────────────────────────────────

  const fetchHistory = useCallback(async () => {
    setHistoryLoading(true);
    try {
      const token = localStorage.getItem("access_token");
      const res = await fetch(
        `${process.env.NEXT_PUBLIC_API_URL || "http://localhost:8002"}/api/v1/import/history`,
        {
          headers: {
            "Content-Type": "application/json",
            ...(token ? { Authorization: `Bearer ${token}` } : {}),
          },
        }
      );
      if (res.ok) {
        const data = await res.json();
        setHistory(Array.isArray(data) ? data : data?.items ?? []);
      }
    } catch {
      // ignore
    } finally {
      setHistoryLoading(false);
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
    fetchHistory();
  }, [isAuthenticated, authLoading, router, fetchCategories, fetchHistory]);

  // ── File upload via dropzone ────────────────────────────────────

  const onDrop = useCallback(
    async (acceptedFiles: File[]) => {
      if (acceptedFiles.length === 0) return;

      const file = acceptedFiles[0];
      setFileName(file.name);
      setUploading(true);
      setUploadError(null);
      setTransactions([]);
      setImportSuccess(false);

      try {
        const res = await api.uploadStatement(file);
        const parsed: ParsedTransaction[] = Array.isArray(res)
          ? res
          : res?.transactions ?? res?.items ?? [];

        setImportId(res?.import_id ?? null);
        setTransactions(
          parsed.map((t, i) => ({
            ...t,
            id: i,
            include: t.include !== false,
            selectedCategoryId: t.suggested_category_id ?? "",
          }))
        );
      } catch (err) {
        setUploadError(
          err instanceof Error ? err.message : "Upload failed"
        );
      } finally {
        setUploading(false);
      }
    },
    []
  );

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: {
      "text/csv": [".csv"],
      "application/pdf": [".pdf"],
    },
    maxFiles: 1,
    disabled: uploading,
  });

  // ── Toggle include ──────────────────────────────────────────────

  const toggleInclude = (id: number) => {
    setTransactions((prev) =>
      prev.map((t) => (t.id === id ? { ...t, include: !t.include } : t))
    );
  };

  // ── Update category ─────────────────────────────────────────────

  const updateCategory = (id: number, categoryId: string) => {
    setTransactions((prev) =>
      prev.map((t) =>
        t.id === id ? { ...t, selectedCategoryId: categoryId } : t
      )
    );
  };

  // ── Confirm import ──────────────────────────────────────────────

  const selectedCount = transactions.filter((t) => t.include).length;

  const handleImport = async () => {
    setImporting(true);
    try {
      const items = transactions
        .filter((t) => t.include)
        .map((t) => ({
          date: t.date,
          description: t.description,
          amount: t.amount,
          category_id: t.selectedCategoryId || null,
        }));

      await api.confirmImport({
        import_id: importId,
        bank_preset: bankPreset,
        transactions: items,
      });

      setImportSuccess(true);
      setTransactions([]);
      fetchHistory();
    } catch (err) {
      setUploadError(
        err instanceof Error ? err.message : "Import failed"
      );
    } finally {
      setImporting(false);
    }
  };

  // ── Reset ───────────────────────────────────────────────────────

  const handleReset = () => {
    setTransactions([]);
    setFileName(null);
    setImportId(null);
    setUploadError(null);
    setImportSuccess(false);
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
          <Upload className="h-5 w-5" />
          <h1 className="text-lg font-semibold">Import</h1>
        </div>
        <p className="text-primary-50 text-sm">
          Upload bank statements to import transactions
        </p>
      </header>

      <div className="px-4 -mt-4 space-y-4">
        {/* Bank preset selector */}
        <div className="bg-white rounded-2xl shadow-sm p-4">
          <label className="block text-[11px] font-medium text-gray-500 mb-1.5">
            Bank / Format
          </label>
          <div className="relative">
            <select
              value={bankPreset}
              onChange={(e) => setBankPreset(e.target.value)}
              className="w-full rounded-lg border border-gray-200 bg-gray-50 px-3 py-2.5
                         text-sm text-gray-700 appearance-none
                         focus:outline-none focus:ring-2 focus:ring-primary-500"
            >
              {BANK_PRESETS.map((b) => (
                <option key={b.value} value={b.value}>
                  {b.label}
                </option>
              ))}
            </select>
            <ChevronDown className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400 pointer-events-none" />
          </div>
        </div>

        {/* Dropzone */}
        {transactions.length === 0 && !importSuccess && (
          <div
            {...getRootProps()}
            className={`bg-white rounded-2xl shadow-sm p-8 text-center cursor-pointer
                       border-2 border-dashed transition-colors
                       ${
                         isDragActive
                           ? "border-primary-400 bg-primary-50"
                           : "border-gray-200 hover:border-primary-300"
                       }
                       ${uploading ? "opacity-60 pointer-events-none" : ""}`}
          >
            <input {...getInputProps()} />
            {uploading ? (
              <>
                <Loader2 className="h-10 w-10 text-primary-400 mx-auto mb-3 animate-spin" />
                <p className="text-sm text-gray-600 font-medium">
                  Parsing {fileName}...
                </p>
              </>
            ) : isDragActive ? (
              <>
                <Upload className="h-10 w-10 text-primary-400 mx-auto mb-3" />
                <p className="text-sm text-primary-600 font-medium">
                  Drop your file here
                </p>
              </>
            ) : (
              <>
                <FileText className="h-10 w-10 text-gray-300 mx-auto mb-3" />
                <p className="text-sm text-gray-600 font-medium">
                  Drag & drop a bank statement
                </p>
                <p className="text-xs text-gray-400 mt-1">
                  PDF or CSV files supported
                </p>
              </>
            )}
          </div>
        )}

        {/* Upload error */}
        {uploadError && (
          <div className="bg-red-50 rounded-2xl p-4 flex items-start gap-3">
            <AlertTriangle className="h-5 w-5 text-red-500 flex-shrink-0 mt-0.5" />
            <div className="flex-1">
              <p className="text-sm text-red-700 font-medium">Error</p>
              <p className="text-xs text-red-600 mt-0.5">{uploadError}</p>
            </div>
            <button onClick={() => setUploadError(null)}>
              <X className="h-4 w-4 text-red-400" />
            </button>
          </div>
        )}

        {/* Import success */}
        {importSuccess && (
          <div className="bg-green-50 rounded-2xl p-6 text-center">
            <Check className="h-10 w-10 text-green-500 mx-auto mb-2" />
            <p className="text-sm text-green-700 font-medium">
              Import Successful
            </p>
            <p className="text-xs text-green-600 mt-1">
              Your transactions have been imported
            </p>
            <button
              onClick={handleReset}
              className="mt-4 px-4 py-2 bg-green-500 text-white text-sm font-medium
                         rounded-xl hover:bg-green-600 transition-colors"
            >
              Import Another
            </button>
          </div>
        )}

        {/* Preview table */}
        {transactions.length > 0 && (
          <div className="bg-white rounded-2xl shadow-sm overflow-hidden">
            <div className="px-4 py-3 border-b border-gray-100 flex items-center justify-between">
              <h2 className="text-sm font-semibold text-gray-700">
                Preview ({transactions.length} transactions)
              </h2>
              <button
                onClick={handleReset}
                className="text-xs text-gray-400 hover:text-gray-600"
              >
                Clear
              </button>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full text-left">
                <thead>
                  <tr className="border-b border-gray-100">
                    <th className="px-4 py-2 text-[11px] font-medium text-gray-500 w-10">
                      <Check className="h-3 w-3" />
                    </th>
                    <th className="px-2 py-2 text-[11px] font-medium text-gray-500">
                      Date
                    </th>
                    <th className="px-2 py-2 text-[11px] font-medium text-gray-500">
                      Description
                    </th>
                    <th className="px-2 py-2 text-[11px] font-medium text-gray-500 text-right">
                      Amount
                    </th>
                    <th className="px-2 py-2 text-[11px] font-medium text-gray-500">
                      Category
                    </th>
                    <th className="px-2 py-2 text-[11px] font-medium text-gray-500 w-8" />
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-50">
                  {transactions.map((t) => (
                    <tr
                      key={t.id}
                      className={`${
                        !t.include ? "opacity-40" : ""
                      } transition-opacity`}
                    >
                      {/* Include checkbox */}
                      <td className="px-4 py-2.5">
                        <input
                          type="checkbox"
                          checked={t.include}
                          onChange={() => toggleInclude(t.id)}
                          className="h-4 w-4 rounded border-gray-300 text-primary-500
                                     focus:ring-primary-500"
                        />
                      </td>

                      {/* Date */}
                      <td className="px-2 py-2.5 text-xs text-gray-600 whitespace-nowrap">
                        {t.date
                          ? new Date(t.date).toLocaleDateString("en-US", {
                              month: "short",
                              day: "numeric",
                            })
                          : "-"}
                      </td>

                      {/* Description */}
                      <td className="px-2 py-2.5">
                        <p className="text-xs text-gray-800 truncate max-w-[140px]">
                          {t.description || "-"}
                        </p>
                        {t.auto_labeled && (
                          <span className="inline-flex items-center gap-0.5 mt-0.5 px-1.5 py-0.5
                                           bg-purple-50 text-purple-600 text-[10px] font-medium rounded">
                            <Tag className="h-2.5 w-2.5" />
                            Auto-labeled
                          </span>
                        )}
                      </td>

                      {/* Amount */}
                      <td className="px-2 py-2.5 text-xs font-semibold text-gray-800 text-right whitespace-nowrap">
                        {fmt(t.amount)}
                      </td>

                      {/* Category dropdown */}
                      <td className="px-2 py-2.5">
                        <select
                          value={t.selectedCategoryId}
                          onChange={(e) =>
                            updateCategory(t.id, e.target.value)
                          }
                          className="w-full text-xs rounded border border-gray-200 bg-gray-50
                                     px-1.5 py-1 text-gray-700
                                     focus:outline-none focus:ring-1 focus:ring-primary-500"
                        >
                          <option value="">Uncategorized</option>
                          {categories
                            .filter((c) => c.is_active)
                            .map((c) => (
                              <option key={c.id} value={c.id}>
                                {c.name}
                              </option>
                            ))}
                        </select>
                      </td>

                      {/* Duplicate warning */}
                      <td className="px-2 py-2.5">
                        {t.possible_duplicate && (
                          <span title="Possible duplicate">
                            <AlertTriangle className="h-4 w-4 text-yellow-500" />
                          </span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {/* Import button */}
            <div className="px-4 py-3 border-t border-gray-100">
              <button
                onClick={handleImport}
                disabled={importing || selectedCount === 0}
                className="w-full flex items-center justify-center gap-2 py-2.5
                           bg-primary-500 text-white text-sm font-semibold rounded-xl
                           hover:bg-primary-600 transition-colors
                           disabled:opacity-60 disabled:cursor-not-allowed"
              >
                {importing ? (
                  <>
                    <Loader2 className="h-4 w-4 animate-spin" />
                    Importing...
                  </>
                ) : (
                  <>
                    <Check className="h-4 w-4" />
                    Import Selected ({selectedCount})
                  </>
                )}
              </button>
            </div>
          </div>
        )}

        {/* Import history */}
        <div className="bg-white rounded-2xl shadow-sm overflow-hidden">
          <div className="px-4 py-3 border-b border-gray-100">
            <h2 className="text-sm font-semibold text-gray-700">
              Import History
            </h2>
          </div>

          {historyLoading ? (
            <div className="flex justify-center py-8">
              <Loader2 className="h-5 w-5 animate-spin text-gray-300" />
            </div>
          ) : history.length === 0 ? (
            <div className="py-8 text-center">
              <FileText className="h-8 w-8 text-gray-300 mx-auto mb-2" />
              <p className="text-xs text-gray-400">No imports yet</p>
            </div>
          ) : (
            <div className="divide-y divide-gray-50">
              {history.map((h: any, i: number) => (
                <div
                  key={h.id ?? i}
                  className="px-4 py-3 flex items-center justify-between"
                >
                  <div>
                    <p className="text-sm text-gray-700 font-medium">
                      {h.file_name ?? h.filename ?? "Statement"}
                    </p>
                    <p className="text-xs text-gray-400 mt-0.5">
                      {h.created_at
                        ? new Date(h.created_at).toLocaleDateString("en-US", {
                            month: "short",
                            day: "numeric",
                            year: "numeric",
                          })
                        : ""}{" "}
                      &middot; {h.transaction_count ?? h.count ?? 0} transactions
                    </p>
                  </div>
                  <span
                    className={`text-xs font-medium px-2 py-0.5 rounded-full ${
                      h.status === "completed"
                        ? "bg-green-50 text-green-600"
                        : h.status === "failed"
                        ? "bg-red-50 text-red-600"
                        : "bg-gray-50 text-gray-500"
                    }`}
                  >
                    {h.status ?? "done"}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      <Navigation />
    </div>
  );
}
