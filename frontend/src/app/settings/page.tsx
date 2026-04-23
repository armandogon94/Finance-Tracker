"use client";

import React, { useState, useEffect, useCallback } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import {
  Settings,
  User,
  Globe,
  Sun,
  Moon,
  Monitor,
  Camera,
  Download,
  Lock,
  LogOut,
  ChevronRight,
  Loader2,
  Tag,
  Check,
  Send,
  Unlink,
} from "lucide-react";
import { api } from "@/lib/api";
import { useAuth } from "@/contexts/AuthContext";
import Navigation from "@/components/Navigation";

// ─── Helpers ────────────────────────────────────────────────────────

type Theme = "light" | "dark" | "system";
type OcrPreference = "auto" | "cloud" | "offline" | "manual";

const CURRENCIES = [
  { value: "USD", label: "USD ($)" },
  { value: "EUR", label: "EUR (\u20AC)" },
  { value: "GBP", label: "GBP (\u00A3)" },
  { value: "CAD", label: "CAD (C$)" },
  { value: "AUD", label: "AUD (A$)" },
  { value: "JPY", label: "JPY (\u00A5)" },
  { value: "MXN", label: "MXN (Mex$)" },
];

const TIMEZONES = [
  "America/New_York",
  "America/Chicago",
  "America/Denver",
  "America/Los_Angeles",
  "America/Anchorage",
  "Pacific/Honolulu",
  "Europe/London",
  "Europe/Paris",
  "Europe/Berlin",
  "Asia/Tokyo",
  "Asia/Shanghai",
  "Australia/Sydney",
];

// ─── Component ──────────────────────────────────────────────────────

export default function SettingsPage() {
  const router = useRouter();
  const { user, isAuthenticated, isLoading: authLoading, logout } = useAuth();

  const [displayName, setDisplayName] = useState("");
  const [currency, setCurrency] = useState("USD");
  const [timezone, setTimezone] = useState("America/New_York");
  const [ocrPreference, setOcrPreference] = useState<OcrPreference>("auto");
  const [theme, setTheme] = useState<Theme>("system");

  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Telegram state
  const [telegramLinked, setTelegramLinked] = useState(false);
  const [telegramUsername, setTelegramUsername] = useState<string | null>(null);
  const [telegramLoading, setTelegramLoading] = useState(false);

  // ── Initialize from user ────────────────────────────────────────

  useEffect(() => {
    if (user) {
      setDisplayName(user.display_name ?? "");
      setCurrency(user.currency ?? "USD");
      setTimezone(user.timezone ?? "America/New_York");
      // Load Telegram status
      api.getTelegramStatus().then((status) => {
        setTelegramLinked(status.linked);
        setTelegramUsername(status.telegram_username);
      }).catch(() => {});
    }
  }, [user]);

  // ── Load theme from localStorage ────────────────────────────────

  useEffect(() => {
    const stored = localStorage.getItem("theme") as Theme | null;
    if (stored) setTheme(stored);
  }, []);

  // ── Apply theme ─────────────────────────────────────────────────

  useEffect(() => {
    localStorage.setItem("theme", theme);
    const root = document.documentElement;

    if (theme === "dark") {
      root.classList.add("dark");
    } else if (theme === "light") {
      root.classList.remove("dark");
    } else {
      // system
      if (window.matchMedia("(prefers-color-scheme: dark)").matches) {
        root.classList.add("dark");
      } else {
        root.classList.remove("dark");
      }
    }
  }, [theme]);

  // ── Auth guard ────────────────────────────────────────────────────

  useEffect(() => {
    if (authLoading) return;
    if (!isAuthenticated) {
      router.replace("/login");
    }
  }, [isAuthenticated, authLoading, router]);

  // ── Save profile ────────────────────────────────────────────────

  const handleSave = useCallback(async () => {
    setSaving(true);
    setSaved(false);
    setError(null);

    try {
      const token = localStorage.getItem("access_token");
      const res = await fetch(
        `${process.env.NEXT_PUBLIC_API_URL || "http://localhost:8002"}/api/v1/auth/me`,
        {
          method: "PATCH",
          headers: {
            "Content-Type": "application/json",
            ...(token ? { Authorization: `Bearer ${token}` } : {}),
          },
          body: JSON.stringify({
            display_name: displayName.trim() || null,
            currency,
            timezone,
            ocr_preference: ocrPreference,
          }),
        }
      );
      if (!res.ok) throw new Error("Failed to save settings");
      setSaved(true);
      setTimeout(() => setSaved(false), 2000);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Save failed");
    } finally {
      setSaving(false);
    }
  }, [displayName, currency, timezone, ocrPreference]);

  // ── Export CSV ──────────────────────────────────────────────────

  const handleExport = async () => {
    setExporting(true);
    try {
      const token = localStorage.getItem("access_token");
      const year = new Date().getFullYear();
      const res = await fetch(
        `${process.env.NEXT_PUBLIC_API_URL || "http://localhost:8002"}/api/v1/expenses/export?year=${year}`,
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
      a.download = `expenses-${year}.csv`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    } catch {
      setError("Failed to export data");
    } finally {
      setExporting(false);
    }
  };

  // ── Logout ──────────────────────────────────────────────────────

  const handleLogout = () => {
    logout();
    router.replace("/login");
  };

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
          <Settings className="h-5 w-5" />
          <h1 className="text-lg font-semibold">Settings</h1>
        </div>
        <p className="text-primary-50 text-sm">
          Manage your account and preferences
        </p>
      </header>

      <div className="px-4 -mt-4 space-y-4">
        {/* Error */}
        {error && (
          <div className="bg-red-50 rounded-2xl p-3 text-sm text-red-600">
            {error}
          </div>
        )}

        {/* Profile section */}
        <div className="bg-white rounded-2xl shadow-sm p-4 space-y-4">
          <div className="flex items-center gap-2 text-sm font-semibold text-gray-700">
            <User className="h-4 w-4" />
            Profile
          </div>

          {/* Display name */}
          <div>
            <label className="block text-[11px] font-medium text-gray-500 mb-1">
              Display Name
            </label>
            <input
              type="text"
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              placeholder="Your name"
              className="w-full rounded-lg border border-gray-200 bg-gray-50 px-3 py-2.5
                         text-sm text-gray-800 focus:outline-none focus:ring-2
                         focus:ring-primary-500"
            />
          </div>

          {/* Email (read-only) */}
          <div>
            <label className="block text-[11px] font-medium text-gray-500 mb-1">
              Email
            </label>
            <input
              type="email"
              value={user?.email ?? ""}
              disabled
              className="w-full rounded-lg border border-gray-200 bg-gray-100 px-3 py-2.5
                         text-sm text-gray-500 cursor-not-allowed"
            />
          </div>

          {/* Currency */}
          <div>
            <label className="block text-[11px] font-medium text-gray-500 mb-1">
              Currency
            </label>
            <select
              value={currency}
              onChange={(e) => setCurrency(e.target.value)}
              className="w-full rounded-lg border border-gray-200 bg-gray-50 px-3 py-2.5
                         text-sm text-gray-700 appearance-none
                         focus:outline-none focus:ring-2 focus:ring-primary-500"
            >
              {CURRENCIES.map((c) => (
                <option key={c.value} value={c.value}>
                  {c.label}
                </option>
              ))}
            </select>
          </div>

          {/* Timezone */}
          <div>
            <label className="block text-[11px] font-medium text-gray-500 mb-1">
              Timezone
            </label>
            <select
              value={timezone}
              onChange={(e) => setTimezone(e.target.value)}
              className="w-full rounded-lg border border-gray-200 bg-gray-50 px-3 py-2.5
                         text-sm text-gray-700 appearance-none
                         focus:outline-none focus:ring-2 focus:ring-primary-500"
            >
              {TIMEZONES.map((tz) => (
                <option key={tz} value={tz}>
                  {tz.replace(/_/g, " ")}
                </option>
              ))}
            </select>
          </div>
        </div>

        {/* OCR Preference */}
        <div className="bg-white rounded-2xl shadow-sm p-4 space-y-3">
          <div className="flex items-center gap-2 text-sm font-semibold text-gray-700">
            <Camera className="h-4 w-4" />
            OCR Preference
          </div>
          <div className="space-y-2">
            {(
              [
                { value: "auto", label: "Auto", desc: "Claude, then Ollama, then Tesseract" },
                { value: "cloud", label: "Cloud Only", desc: "Claude Vision (Haiku 4.5)" },
                { value: "offline", label: "Offline Only", desc: "On-device Tesseract" },
                { value: "manual", label: "Manual", desc: "Type amounts manually" },
              ] as { value: OcrPreference; label: string; desc: string }[]
            ).map((opt) => (
              <label
                key={opt.value}
                className={`flex items-center gap-3 p-3 rounded-xl border cursor-pointer transition-colors
                           ${
                             ocrPreference === opt.value
                               ? "border-primary-500 bg-primary-50"
                               : "border-gray-100 hover:bg-gray-50"
                           }`}
              >
                <input
                  type="radio"
                  name="ocr"
                  value={opt.value}
                  checked={ocrPreference === opt.value}
                  onChange={() => setOcrPreference(opt.value)}
                  className="h-4 w-4 text-primary-500 focus:ring-primary-500"
                />
                <div>
                  <p className="text-sm font-medium text-gray-700">
                    {opt.label}
                  </p>
                  <p className="text-xs text-gray-400">{opt.desc}</p>
                </div>
              </label>
            ))}
          </div>
        </div>

        {/* Theme */}
        <div className="bg-white rounded-2xl shadow-sm p-4 space-y-3">
          <div className="flex items-center gap-2 text-sm font-semibold text-gray-700">
            <Sun className="h-4 w-4" />
            Theme
          </div>
          <div className="grid grid-cols-3 gap-2">
            {(
              [
                { value: "light", label: "Light", icon: <Sun className="h-4 w-4" /> },
                { value: "dark", label: "Dark", icon: <Moon className="h-4 w-4" /> },
                { value: "system", label: "System", icon: <Monitor className="h-4 w-4" /> },
              ] as { value: Theme; label: string; icon: React.ReactNode }[]
            ).map((opt) => (
              <button
                key={opt.value}
                onClick={() => setTheme(opt.value)}
                className={`flex flex-col items-center gap-1.5 py-3 rounded-xl border transition-colors
                           ${
                             theme === opt.value
                               ? "border-primary-500 bg-primary-50 text-primary-500"
                               : "border-gray-100 text-gray-500 hover:bg-gray-50"
                           }`}
              >
                {opt.icon}
                <span className="text-xs font-medium">{opt.label}</span>
              </button>
            ))}
          </div>
        </div>

        {/* Save button */}
        <button
          onClick={handleSave}
          disabled={saving}
          className="w-full flex items-center justify-center gap-2 py-3 bg-primary-500 text-white
                     text-sm font-semibold rounded-2xl hover:bg-primary-600 transition-colors
                     disabled:opacity-60 disabled:cursor-not-allowed"
        >
          {saving ? (
            <>
              <Loader2 className="h-4 w-4 animate-spin" />
              Saving...
            </>
          ) : saved ? (
            <>
              <Check className="h-4 w-4" />
              Saved!
            </>
          ) : (
            "Save Changes"
          )}
        </button>

        {/* Auto-label rules link */}
        <Link
          href="/settings/rules"
          className="flex items-center justify-between bg-white rounded-2xl shadow-sm px-4 py-3.5
                     hover:bg-gray-50 transition-colors"
        >
          <div className="flex items-center gap-3">
            <Tag className="h-4 w-4 text-gray-500" />
            <div>
              <p className="text-sm font-medium text-gray-700">
                Auto-Label Rules
              </p>
              <p className="text-xs text-gray-400">
                Manage category matching rules
              </p>
            </div>
          </div>
          <ChevronRight className="h-4 w-4 text-gray-400" />
        </Link>

        {/* Telegram section */}
        <div className="bg-white rounded-2xl shadow-sm p-4 space-y-3">
          <div className="flex items-center gap-2 text-sm font-semibold text-gray-700">
            <Send className="h-4 w-4" />
            Telegram Bot
          </div>
          {telegramLinked ? (
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-gray-700">
                  Linked to <span className="font-medium">@{telegramUsername}</span>
                </p>
                <p className="text-xs text-green-600">Connected</p>
              </div>
              <button
                onClick={async () => {
                  setTelegramLoading(true);
                  try {
                    await api.unlinkTelegram();
                    setTelegramLinked(false);
                    setTelegramUsername(null);
                  } catch {} finally {
                    setTelegramLoading(false);
                  }
                }}
                disabled={telegramLoading}
                className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-red-500 border
                           border-red-200 rounded-lg hover:bg-red-50 transition-colors"
              >
                <Unlink className="h-3.5 w-3.5" />
                Unlink
              </button>
            </div>
          ) : (
            <Link
              href="/telegram-link"
              className="flex items-center justify-between px-3 py-2.5 bg-gray-50 rounded-xl
                         hover:bg-gray-100 transition-colors"
            >
              <div>
                <p className="text-sm font-medium text-gray-700">Link Telegram Account</p>
                <p className="text-xs text-gray-400">Log expenses via Telegram bot</p>
              </div>
              <ChevronRight className="h-4 w-4 text-gray-400" />
            </Link>
          )}
        </div>

        {/* Data export */}
        <div className="bg-white rounded-2xl shadow-sm p-4">
          <div className="flex items-center gap-2 text-sm font-semibold text-gray-700 mb-3">
            <Download className="h-4 w-4" />
            Data Export
          </div>
          <button
            onClick={handleExport}
            disabled={exporting}
            className="w-full flex items-center justify-center gap-2 py-2.5 bg-gray-100 text-gray-700
                       text-sm font-medium rounded-xl hover:bg-gray-200 transition-colors
                       disabled:opacity-60"
          >
            {exporting ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" />
                Exporting...
              </>
            ) : (
              <>
                <Download className="h-4 w-4" />
                Download CSV ({new Date().getFullYear()})
              </>
            )}
          </button>
        </div>

        {/* Account actions */}
        <div className="bg-white rounded-2xl shadow-sm overflow-hidden">
          <Link
            href="/settings/password"
            className="flex items-center justify-between px-4 py-3.5
                       border-b border-gray-100 hover:bg-gray-50 transition-colors"
          >
            <div className="flex items-center gap-3">
              <Lock className="h-4 w-4 text-gray-500" />
              <span className="text-sm font-medium text-gray-700">
                Change Password
              </span>
            </div>
            <ChevronRight className="h-4 w-4 text-gray-400" />
          </Link>
          <button
            onClick={handleLogout}
            className="w-full flex items-center gap-3 px-4 py-3.5
                       text-left hover:bg-red-50 transition-colors"
          >
            <LogOut className="h-4 w-4 text-red-500" />
            <span className="text-sm font-medium text-red-500">Logout</span>
          </button>
        </div>
      </div>

      <Navigation />
    </div>
  );
}
