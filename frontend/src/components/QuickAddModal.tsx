"use client";

import React, { useState, useEffect, useCallback } from "react";
import { Delete, X, Check, Loader2 } from "lucide-react";
import { api } from "@/lib/api";
import type { Category } from "@/types";

// ─── Props ──────────────────────────────────────────────────────────

interface QuickAddModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSaved: () => void;
}

// ─── Component ──────────────────────────────────────────────────────

export default function QuickAddModal({
  isOpen,
  onClose,
  onSaved,
}: QuickAddModalProps) {
  const [amount, setAmount] = useState("0");
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);
  const [categories, setCategories] = useState<Category[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Fetch categories
  useEffect(() => {
    if (!isOpen) return;
    api
      .getCategories()
      .then((cats) => {
        const list = Array.isArray(cats) ? cats : [];
        setCategories(list.filter((c) => c.is_active && !c.is_hidden));
      })
      .catch(() => {});
  }, [isOpen]);

  // Reset state when opened
  useEffect(() => {
    if (isOpen) {
      setAmount("0");
      setSelectedCategory(null);
      setError(null);
    }
  }, [isOpen]);

  // ── Number pad handler ────────────────────────────────────────────

  const handleDigit = useCallback((digit: string) => {
    setAmount((prev) => {
      if (digit === ".") {
        if (prev.includes(".")) return prev;
        return prev + ".";
      }
      // Limit to 2 decimal places
      const parts = prev.split(".");
      if (parts.length === 2 && parts[1].length >= 2) return prev;
      // Replace leading "0" with the digit unless it's "0."
      if (prev === "0" && digit !== ".") return digit;
      return prev + digit;
    });
  }, []);

  const handleBackspace = useCallback(() => {
    setAmount((prev) => {
      if (prev.length <= 1) return "0";
      return prev.slice(0, -1);
    });
  }, []);

  // ── Save ──────────────────────────────────────────────────────────

  const handleSave = async () => {
    const numAmount = parseFloat(amount);
    if (!numAmount || numAmount <= 0) {
      setError("Enter an amount");
      return;
    }
    if (!selectedCategory) {
      setError("Select a category");
      return;
    }

    setSaving(true);
    setError(null);
    try {
      await api.quickAddExpense(numAmount, selectedCategory);
      onSaved();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Failed to save");
    } finally {
      setSaving(false);
    }
  };

  // ── Backdrop click ────────────────────────────────────────────────

  const handleBackdropClick = (e: React.MouseEvent<HTMLDivElement>) => {
    if (e.target === e.currentTarget) onClose();
  };

  if (!isOpen) return null;

  const numPadKeys = [
    "1", "2", "3",
    "4", "5", "6",
    "7", "8", "9",
    ".", "0", "backspace",
  ];

  const DEFAULT_COLORS = [
    "#3B82F6", "#10B981", "#F59E0B", "#EF4444",
    "#8B5CF6", "#EC4899", "#06B6D4", "#F97316",
    "#14B8A6", "#6366F1", "#D946EF", "#84CC16",
  ];

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-black/40 backdrop-blur-sm"
      onClick={handleBackdropClick}
    >
      <div
        className="w-full max-w-lg bg-white rounded-t-3xl shadow-xl animate-slide-up
                    max-h-[90vh] flex flex-col"
        style={{
          animation: "slideUp 0.3s ease-out",
        }}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-5 pt-5 pb-2">
          <h2 className="text-lg font-semibold text-gray-800">Quick Add</h2>
          <button
            onClick={onClose}
            className="h-8 w-8 rounded-full bg-gray-100 flex items-center justify-center text-gray-500
                       hover:bg-gray-200 transition-colors"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Amount display */}
        <div className="px-5 py-4">
          <div className="text-center">
            <span className="text-4xl font-bold text-gray-800 tabular-nums">
              ${amount}
            </span>
          </div>
        </div>

        {error && (
          <div className="mx-5 mb-2 rounded-lg bg-red-50 text-red-600 text-xs p-2 text-center">
            {error}
          </div>
        )}

        {/* Category grid (scrollable) */}
        <div className="px-5 pb-3 overflow-x-auto">
          <div className="flex gap-2 pb-1" style={{ minWidth: "max-content" }}>
            {categories.map((cat, i) => {
              const color = cat.color || DEFAULT_COLORS[i % DEFAULT_COLORS.length];
              const isSelected = selectedCategory === cat.id;
              return (
                <button
                  key={cat.id}
                  onClick={() => setSelectedCategory(cat.id)}
                  className={`flex flex-col items-center gap-1 px-3 py-2 rounded-xl
                             transition-all flex-shrink-0
                             ${isSelected
                               ? "ring-2 ring-offset-1 scale-105"
                               : "hover:bg-gray-50"
                             }`}
                  style={{
                    outlineColor: isSelected ? color : undefined,
                    borderColor: isSelected ? color : "transparent",
                  }}
                >
                  <div
                    className="h-10 w-10 rounded-full flex items-center justify-center text-white text-sm font-medium"
                    style={{ backgroundColor: color }}
                  >
                    {cat.icon || cat.name.charAt(0).toUpperCase()}
                  </div>
                  <span className="text-[11px] text-gray-600 font-medium max-w-[56px] truncate">
                    {cat.name}
                  </span>
                </button>
              );
            })}
            {categories.length === 0 && (
              <span className="text-sm text-gray-400 py-4">
                No categories found
              </span>
            )}
          </div>
        </div>

        {/* Number pad */}
        <div className="px-5 pb-3">
          <div className="grid grid-cols-3 gap-2">
            {numPadKeys.map((key) => {
              if (key === "backspace") {
                return (
                  <button
                    key={key}
                    onClick={handleBackspace}
                    className="h-12 rounded-xl bg-gray-100 flex items-center justify-center
                               text-gray-600 active:bg-gray-200 transition-colors"
                  >
                    <Delete className="h-5 w-5" />
                  </button>
                );
              }
              return (
                <button
                  key={key}
                  onClick={() => handleDigit(key)}
                  className="h-12 rounded-xl bg-gray-50 text-lg font-medium text-gray-800
                             active:bg-gray-200 transition-colors"
                >
                  {key}
                </button>
              );
            })}
          </div>
        </div>

        {/* Save button */}
        <div className="px-5 pb-5 pt-1">
          <button
            onClick={handleSave}
            disabled={saving}
            className="w-full h-12 rounded-xl bg-primary-500 text-white font-semibold
                       flex items-center justify-center gap-2
                       hover:bg-primary-600 active:scale-[0.98] transition-all
                       disabled:opacity-60 disabled:cursor-not-allowed"
          >
            {saving ? (
              <Loader2 className="h-5 w-5 animate-spin" />
            ) : (
              <Check className="h-5 w-5" />
            )}
            {saving ? "Saving..." : "Save Expense"}
          </button>
        </div>
      </div>

      {/* Slide-up animation */}
      <style jsx>{`
        @keyframes slideUp {
          from {
            transform: translateY(100%);
          }
          to {
            transform: translateY(0);
          }
        }
      `}</style>
    </div>
  );
}
