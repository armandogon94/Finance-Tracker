"use client";

import React, { useState, useRef } from "react";
import { Camera, Loader2, Check, X, ReceiptText } from "lucide-react";
import { api } from "@/lib/api";
import { compressImage } from "@/lib/image-compress";

// ─── Props ──────────────────────────────────────────────────────────

interface ReceiptScannerProps {
  onSaved: () => void;
}

// ─── OCR Result shape ───────────────────────────────────────────────

interface OcrResult {
  merchant: string;
  date: string;
  total: number;
  tax: number;
  items: { description: string; amount: number }[];
}

// ─── Component ──────────────────────────────────────────────────────

export default function ReceiptScanner({ onSaved }: ReceiptScannerProps) {
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [status, setStatus] = useState<
    "idle" | "analyzing" | "review" | "saving" | "done"
  >("idle");
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<OcrResult | null>(null);

  // ── Trigger file picker ───────────────────────────────────────────

  const handleTrigger = () => {
    fileInputRef.current?.click();
  };

  // ── File selected ─────────────────────────────────────────────────

  const handleFileChange = async (
    e: React.ChangeEvent<HTMLInputElement>
  ) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setError(null);
    setStatus("analyzing");

    try {
      // Compress image before upload
      const compressedBlob = await compressImage(file);
      const compressedFile = new File([compressedBlob], file.name, {
        type: "image/jpeg",
        lastModified: Date.now(),
      });

      // Upload for OCR
      const data = await api.scanReceipt(compressedFile);

      setResult({
        merchant: data.merchant || "",
        date: data.date || new Date().toISOString().split("T")[0],
        total: data.total ?? 0,
        tax: data.tax ?? 0,
        items: Array.isArray(data.items) ? data.items : [],
      });
      setStatus("review");
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Failed to analyze receipt");
      setStatus("idle");
    }

    // Reset file input so the same file can be re-selected
    if (fileInputRef.current) fileInputRef.current.value = "";
  };

  // ── Field update helpers ──────────────────────────────────────────

  const updateField = <K extends keyof OcrResult>(
    field: K,
    value: OcrResult[K]
  ) => {
    if (!result) return;
    setResult({ ...result, [field]: value });
  };

  const updateItem = (
    index: number,
    field: "description" | "amount",
    value: string | number
  ) => {
    if (!result) return;
    const items = [...result.items];
    items[index] = { ...items[index], [field]: value };
    setResult({ ...result, items });
  };

  // ── Confirm & Save ────────────────────────────────────────────────

  const handleSave = async () => {
    if (!result) return;
    setStatus("saving");
    setError(null);

    try {
      await api.createExpense({
        amount: result.total,
        tax_amount: result.tax || undefined,
        merchant_name: result.merchant || undefined,
        expense_date: result.date,
        description: result.items.map((i) => i.description).join(", ") || undefined,
        ocr_method: "receipt_scan",
      });
      setStatus("done");
      setTimeout(() => {
        setStatus("idle");
        setResult(null);
        onSaved();
      }, 1200);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Failed to save");
      setStatus("review");
    }
  };

  // ── Cancel ────────────────────────────────────────────────────────

  const handleCancel = () => {
    setStatus("idle");
    setResult(null);
    setError(null);
  };

  // ── Render ────────────────────────────────────────────────────────

  return (
    <div className="w-full">
      {/* Hidden file input */}
      <input
        ref={fileInputRef}
        type="file"
        accept="image/*"
        capture="environment"
        onChange={handleFileChange}
        className="hidden"
      />

      {/* Idle state - scan button */}
      {status === "idle" && (
        <button
          onClick={handleTrigger}
          className="w-full flex items-center justify-center gap-3 py-4 px-6
                     bg-gradient-to-r from-primary-500 to-primary-600 text-white
                     rounded-2xl shadow-sm font-semibold
                     hover:from-primary-600 hover:to-primary-700
                     active:scale-[0.98] transition-all"
        >
          <Camera className="h-5 w-5" />
          Scan Receipt
        </button>
      )}

      {/* Analyzing state */}
      {status === "analyzing" && (
        <div className="flex flex-col items-center gap-3 py-8">
          <Loader2 className="h-10 w-10 animate-spin text-primary-500" />
          <p className="text-sm font-medium text-gray-600">
            Analyzing receipt...
          </p>
          <p className="text-xs text-gray-400">
            This may take a few seconds
          </p>
        </div>
      )}

      {/* Done state */}
      {status === "done" && (
        <div className="flex flex-col items-center gap-2 py-8">
          <div className="h-12 w-12 rounded-full bg-green-100 flex items-center justify-center">
            <Check className="h-6 w-6 text-green-600" />
          </div>
          <p className="text-sm font-medium text-green-700">Saved!</p>
        </div>
      )}

      {/* Error */}
      {error && (
        <div className="mt-3 rounded-lg bg-red-50 text-red-600 text-sm p-3">
          {error}
        </div>
      )}

      {/* Review state - editable fields */}
      {(status === "review" || status === "saving") && result && (
        <div className="mt-2 space-y-4">
          <div className="flex items-center gap-2 mb-1">
            <ReceiptText className="h-5 w-5 text-gray-500" />
            <h3 className="text-sm font-semibold text-gray-700">
              Review Receipt
            </h3>
          </div>

          {/* Merchant */}
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1">
              Merchant
            </label>
            <input
              type="text"
              value={result.merchant}
              onChange={(e) => updateField("merchant", e.target.value)}
              className="w-full rounded-xl border border-gray-200 bg-gray-50 py-2 px-3
                         text-sm text-gray-800 focus:outline-none focus:ring-2
                         focus:ring-primary-500 focus:border-transparent"
              placeholder="Store name"
            />
          </div>

          {/* Date */}
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1">
              Date
            </label>
            <input
              type="date"
              value={result.date}
              onChange={(e) => updateField("date", e.target.value)}
              className="w-full rounded-xl border border-gray-200 bg-gray-50 py-2 px-3
                         text-sm text-gray-800 focus:outline-none focus:ring-2
                         focus:ring-primary-500 focus:border-transparent"
            />
          </div>

          {/* Total & Tax side by side */}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-gray-500 mb-1">
                Total
              </label>
              <input
                type="number"
                step="0.01"
                min="0"
                value={result.total}
                onChange={(e) =>
                  updateField("total", parseFloat(e.target.value) || 0)
                }
                className="w-full rounded-xl border border-gray-200 bg-gray-50 py-2 px-3
                           text-sm text-gray-800 focus:outline-none focus:ring-2
                           focus:ring-primary-500 focus:border-transparent"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-500 mb-1">
                Tax
              </label>
              <input
                type="number"
                step="0.01"
                min="0"
                value={result.tax}
                onChange={(e) =>
                  updateField("tax", parseFloat(e.target.value) || 0)
                }
                className="w-full rounded-xl border border-gray-200 bg-gray-50 py-2 px-3
                           text-sm text-gray-800 focus:outline-none focus:ring-2
                           focus:ring-primary-500 focus:border-transparent"
              />
            </div>
          </div>

          {/* Line items */}
          {result.items.length > 0 && (
            <div>
              <label className="block text-xs font-medium text-gray-500 mb-2">
                Items
              </label>
              <div className="space-y-2 max-h-40 overflow-y-auto">
                {result.items.map((item, i) => (
                  <div key={i} className="flex gap-2">
                    <input
                      type="text"
                      value={item.description}
                      onChange={(e) =>
                        updateItem(i, "description", e.target.value)
                      }
                      className="flex-1 rounded-lg border border-gray-200 bg-gray-50 py-1.5 px-2.5
                                 text-sm text-gray-800 focus:outline-none focus:ring-2
                                 focus:ring-primary-500 focus:border-transparent"
                      placeholder="Item description"
                    />
                    <input
                      type="number"
                      step="0.01"
                      min="0"
                      value={item.amount}
                      onChange={(e) =>
                        updateItem(
                          i,
                          "amount",
                          parseFloat(e.target.value) || 0
                        )
                      }
                      className="w-20 rounded-lg border border-gray-200 bg-gray-50 py-1.5 px-2.5
                                 text-sm text-gray-800 text-right focus:outline-none focus:ring-2
                                 focus:ring-primary-500 focus:border-transparent"
                    />
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Action buttons */}
          <div className="flex gap-3 pt-1">
            <button
              onClick={handleCancel}
              disabled={status === "saving"}
              className="flex-1 h-11 rounded-xl border border-gray-200 text-gray-600 font-medium
                         text-sm flex items-center justify-center gap-1.5
                         hover:bg-gray-50 active:scale-[0.98] transition-all
                         disabled:opacity-50"
            >
              <X className="h-4 w-4" />
              Cancel
            </button>
            <button
              onClick={handleSave}
              disabled={status === "saving"}
              className="flex-1 h-11 rounded-xl bg-primary-500 text-white font-medium
                         text-sm flex items-center justify-center gap-1.5
                         hover:bg-primary-600 active:scale-[0.98] transition-all
                         disabled:opacity-60"
            >
              {status === "saving" ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <Check className="h-4 w-4" />
              )}
              {status === "saving" ? "Saving..." : "Confirm & Save"}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
