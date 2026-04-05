"use client";

import React, { useState, useEffect, useCallback } from "react";
import { useRouter } from "next/navigation";
import {
  Shield,
  Users,
  Flag,
  BarChart3,
  Loader2,
  CheckCircle2,
  XCircle,
} from "lucide-react";
import { api } from "@/lib/api";
import { useAuth } from "@/contexts/AuthContext";
import Navigation from "@/components/Navigation";

// ─── Types ──────────────────────────────────────────────────────────

interface AdminUser {
  id: string;
  email: string;
  display_name: string | null;
  is_active: boolean;
  is_superuser: boolean;
  created_at: string;
}

interface AdminStats {
  total_users: number;
  total_expenses: number;
  total_categories: number;
  total_credit_cards: number;
  total_loans: number;
  [key: string]: number;
}

type TabId = "users" | "flags" | "stats";

const FEATURE_FLAGS = [
  { key: "friend_debt_calculator", label: "Friend Debt Calculator" },
  { key: "hidden_categories", label: "Hidden Categories" },
];

// ─── Component ──────────────────────────────────────────────────────

export default function AdminPage() {
  const router = useRouter();
  const { user, isAuthenticated, isLoading: authLoading } = useAuth();

  const [activeTab, setActiveTab] = useState<TabId>("users");
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [stats, setStats] = useState<AdminStats | null>(null);
  const [loading, setLoading] = useState(true);

  // Feature flags tab state
  const [selectedUserId, setSelectedUserId] = useState<string | null>(null);
  const [userFlags, setUserFlags] = useState<Record<string, boolean>>({});
  const [flagsLoading, setFlagsLoading] = useState(false);
  const [togglingFlag, setTogglingFlag] = useState<string | null>(null);

  // ── Auth guard (superuser only) ───────────────────────────────────

  useEffect(() => {
    if (authLoading) return;
    if (!isAuthenticated) {
      router.replace("/login");
      return;
    }
    if (user && !user.is_superuser) {
      router.replace("/");
      return;
    }
  }, [isAuthenticated, authLoading, user, router]);

  // ── Fetch data ────────────────────────────────────────────────────

  const fetchUsers = useCallback(async () => {
    try {
      const data = await api.getAdminUsers();
      setUsers(Array.isArray(data) ? data : []);
    } catch {
      setUsers([]);
    }
  }, []);

  const fetchStats = useCallback(async () => {
    try {
      const data = await api.getAdminStats();
      setStats(data);
    } catch {
      setStats(null);
    }
  }, []);

  useEffect(() => {
    if (!user?.is_superuser) return;

    setLoading(true);
    Promise.all([fetchUsers(), fetchStats()]).finally(() =>
      setLoading(false)
    );
  }, [user, fetchUsers, fetchStats]);

  // ── Fetch flags for selected user ─────────────────────────────────

  useEffect(() => {
    if (!selectedUserId) {
      setUserFlags({});
      return;
    }
    setFlagsLoading(true);

    api
      .getAdminUsers()
      .then((allUsers) => {
        // Try to get feature flags from admin users endpoint or separate endpoint
        // For now we'll fetch the user's features directly
        return fetch(
          `${process.env.NEXT_PUBLIC_API_URL || "http://localhost:8002"}/api/v1/admin/users/${selectedUserId}/features`,
          {
            headers: {
              Authorization: `Bearer ${localStorage.getItem("access_token")}`,
            },
          }
        ).then((r) => (r.ok ? r.json() : {}));
      })
      .then((flags) => setUserFlags(flags))
      .catch(() => setUserFlags({}))
      .finally(() => setFlagsLoading(false));
  }, [selectedUserId]);

  // ── Toggle feature flag ───────────────────────────────────────────

  const handleToggleFlag = async (featureKey: string) => {
    if (!selectedUserId) return;

    const currentValue = userFlags[featureKey] ?? false;
    setTogglingFlag(featureKey);

    try {
      await api.toggleFeatureFlag(
        selectedUserId,
        featureKey,
        !currentValue
      );
      setUserFlags((prev) => ({ ...prev, [featureKey]: !currentValue }));
    } catch {
      // Revert on error - no change
    } finally {
      setTogglingFlag(null);
    }
  };

  // ── Loading / guard ───────────────────────────────────────────────

  if (authLoading || !user?.is_superuser) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <Loader2 className="h-8 w-8 animate-spin text-primary-500" />
      </div>
    );
  }

  // ── Tab definitions ───────────────────────────────────────────────

  const tabs: { id: TabId; label: string; icon: React.ReactNode }[] = [
    { id: "users", label: "Users", icon: <Users className="h-4 w-4" /> },
    { id: "flags", label: "Flags", icon: <Flag className="h-4 w-4" /> },
    { id: "stats", label: "Stats", icon: <BarChart3 className="h-4 w-4" /> },
  ];

  return (
    <div className="min-h-screen bg-gray-50 pb-24">
      {/* Header */}
      <header className="bg-gradient-to-br from-gray-800 to-gray-900 text-white px-4 pt-6 pb-8 rounded-b-3xl">
        <div className="flex items-center gap-2 mb-1">
          <Shield className="h-5 w-5" />
          <h1 className="text-lg font-semibold">Admin Panel</h1>
        </div>
        <p className="text-gray-300 text-sm">Manage users and features</p>
      </header>

      {/* Tabs */}
      <div className="px-4 -mt-4">
        <div className="bg-white rounded-2xl shadow-sm p-1 flex gap-1">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex-1 flex items-center justify-center gap-1.5 py-2 rounded-xl text-sm font-medium transition-colors
                ${
                  activeTab === tab.id
                    ? "bg-primary-500 text-white"
                    : "text-gray-500 hover:bg-gray-50"
                }`}
            >
              {tab.icon}
              {tab.label}
            </button>
          ))}
        </div>
      </div>

      {/* Tab content */}
      <div className="px-4 mt-4">
        {loading ? (
          <div className="flex justify-center py-12">
            <Loader2 className="h-8 w-8 animate-spin text-gray-300" />
          </div>
        ) : (
          <>
            {/* ─── Users tab ────────────────────────────────────── */}
            {activeTab === "users" && (
              <div className="bg-white rounded-2xl shadow-sm overflow-hidden">
                <div className="overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="bg-gray-50 text-gray-500 text-xs font-medium">
                        <th className="text-left px-4 py-3">Name</th>
                        <th className="text-left px-4 py-3 hidden sm:table-cell">
                          Email
                        </th>
                        <th className="text-center px-4 py-3">Status</th>
                        <th className="text-right px-4 py-3 hidden sm:table-cell">
                          Created
                        </th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-gray-50">
                      {users.map((u) => (
                        <tr key={u.id} className="hover:bg-gray-50/50">
                          <td className="px-4 py-3">
                            <div>
                              <p className="font-medium text-gray-800 truncate max-w-[160px]">
                                {u.display_name || u.email.split("@")[0]}
                              </p>
                              <p className="text-xs text-gray-400 sm:hidden truncate max-w-[160px]">
                                {u.email}
                              </p>
                            </div>
                          </td>
                          <td className="px-4 py-3 text-gray-600 hidden sm:table-cell">
                            <span className="truncate block max-w-[200px]">
                              {u.email}
                            </span>
                          </td>
                          <td className="px-4 py-3 text-center">
                            {u.is_active ? (
                              <span className="inline-flex items-center gap-1 text-xs font-medium text-green-600 bg-green-50 px-2 py-0.5 rounded-full">
                                <CheckCircle2 className="h-3 w-3" />
                                Active
                              </span>
                            ) : (
                              <span className="inline-flex items-center gap-1 text-xs font-medium text-red-600 bg-red-50 px-2 py-0.5 rounded-full">
                                <XCircle className="h-3 w-3" />
                                Inactive
                              </span>
                            )}
                          </td>
                          <td className="px-4 py-3 text-right text-gray-400 text-xs hidden sm:table-cell">
                            {new Date(u.created_at).toLocaleDateString(
                              "en-US",
                              {
                                month: "short",
                                day: "numeric",
                                year: "numeric",
                              }
                            )}
                          </td>
                        </tr>
                      ))}
                      {users.length === 0 && (
                        <tr>
                          <td
                            colSpan={4}
                            className="px-4 py-8 text-center text-gray-400"
                          >
                            No users found
                          </td>
                        </tr>
                      )}
                    </tbody>
                  </table>
                </div>
              </div>
            )}

            {/* ─── Feature Flags tab ────────────────────────────── */}
            {activeTab === "flags" && (
              <div className="space-y-4">
                {/* User selector */}
                <div className="bg-white rounded-2xl shadow-sm p-4">
                  <label className="block text-xs font-medium text-gray-500 mb-2">
                    Select User
                  </label>
                  <select
                    value={selectedUserId ?? ""}
                    onChange={(e) =>
                      setSelectedUserId(e.target.value || null)
                    }
                    className="w-full rounded-xl border border-gray-200 bg-gray-50 py-2.5 px-3
                               text-sm text-gray-800 focus:outline-none focus:ring-2
                               focus:ring-primary-500 focus:border-transparent"
                  >
                    <option value="">-- Choose a user --</option>
                    {users.map((u) => (
                      <option key={u.id} value={u.id}>
                        {u.display_name || u.email} ({u.email})
                      </option>
                    ))}
                  </select>
                </div>

                {/* Flags toggles */}
                {selectedUserId && (
                  <div className="bg-white rounded-2xl shadow-sm p-4 space-y-3">
                    {flagsLoading ? (
                      <div className="flex justify-center py-6">
                        <Loader2 className="h-6 w-6 animate-spin text-gray-300" />
                      </div>
                    ) : (
                      FEATURE_FLAGS.map((flag) => (
                        <div
                          key={flag.key}
                          className="flex items-center justify-between py-2"
                        >
                          <div>
                            <p className="text-sm font-medium text-gray-800">
                              {flag.label}
                            </p>
                            <p className="text-xs text-gray-400 mt-0.5">
                              {flag.key}
                            </p>
                          </div>
                          <button
                            onClick={() => handleToggleFlag(flag.key)}
                            disabled={togglingFlag === flag.key}
                            className={`relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer
                                       rounded-full border-2 border-transparent transition-colors
                                       duration-200 ease-in-out focus:outline-none focus:ring-2
                                       focus:ring-primary-500 focus:ring-offset-2
                                       disabled:opacity-50
                                       ${
                                         userFlags[flag.key]
                                           ? "bg-primary-500"
                                           : "bg-gray-200"
                                       }`}
                            role="switch"
                            aria-checked={userFlags[flag.key] ?? false}
                          >
                            <span
                              className={`pointer-events-none inline-block h-5 w-5 transform
                                         rounded-full bg-white shadow ring-0 transition
                                         duration-200 ease-in-out
                                         ${
                                           userFlags[flag.key]
                                             ? "translate-x-5"
                                             : "translate-x-0"
                                         }`}
                            />
                          </button>
                        </div>
                      ))
                    )}
                  </div>
                )}

                {!selectedUserId && (
                  <p className="text-center text-sm text-gray-400 py-8">
                    Select a user above to manage their feature flags
                  </p>
                )}
              </div>
            )}

            {/* ─── Stats tab ────────────────────────────────────── */}
            {activeTab === "stats" && (
              <div className="grid grid-cols-2 gap-3">
                {stats ? (
                  Object.entries(stats).map(([key, value]) => (
                    <div
                      key={key}
                      className="bg-white rounded-2xl shadow-sm p-4"
                    >
                      <p className="text-xs font-medium text-gray-400 capitalize">
                        {key.replace(/_/g, " ")}
                      </p>
                      <p className="text-2xl font-bold text-gray-800 mt-1">
                        {typeof value === "number"
                          ? value.toLocaleString()
                          : value}
                      </p>
                    </div>
                  ))
                ) : (
                  <div className="col-span-2 text-center text-gray-400 py-8">
                    No stats available
                  </div>
                )}
              </div>
            )}
          </>
        )}
      </div>

      <Navigation />
    </div>
  );
}
