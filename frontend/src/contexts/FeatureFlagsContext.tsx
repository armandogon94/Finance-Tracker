"use client";

import React, {
  createContext,
  useContext,
  useState,
  useEffect,
  useMemo,
  useCallback,
} from "react";
import { api, ApiError } from "@/lib/api";
import { useAuth } from "@/contexts/AuthContext";

// ─── Types ──────────────────────────────────────────────────────────

interface FeatureFlagsContextValue {
  flags: Record<string, boolean>;
  isLoading: boolean;
}

// ─── Context ────────────────────────────────────────────────────────

const FeatureFlagsContext = createContext<FeatureFlagsContextValue | undefined>(
  undefined,
);

// ─── Provider ───────────────────────────────────────────────────────

export function FeatureFlagsProvider({
  children,
}: {
  children: React.ReactNode;
}) {
  const { user, isAuthenticated } = useAuth();
  const [flags, setFlags] = useState<Record<string, boolean>>({});
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    if (!isAuthenticated || !user) {
      setFlags({});
      return;
    }

    let cancelled = false;
    setIsLoading(true);

    api
      .getFeatureFlags()
      .then((data) => {
        if (!cancelled) setFlags(data);
      })
      .catch((err: unknown) => {
        // 403 means the user is not an admin -- default to empty flags
        if (err instanceof ApiError && err.status === 403) {
          if (!cancelled) setFlags({});
        } else {
          // For any other error, also default to empty so the app
          // keeps working without feature flags.
          if (!cancelled) setFlags({});
        }
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [user, isAuthenticated]);

  const value = useMemo<FeatureFlagsContextValue>(
    () => ({ flags, isLoading }),
    [flags, isLoading],
  );

  return (
    <FeatureFlagsContext.Provider value={value}>
      {children}
    </FeatureFlagsContext.Provider>
  );
}

// ─── Hooks ──────────────────────────────────────────────────────────

export function useFeatureFlags(): FeatureFlagsContextValue {
  const ctx = useContext(FeatureFlagsContext);
  if (ctx === undefined) {
    throw new Error(
      "useFeatureFlags must be used within a FeatureFlagsProvider",
    );
  }
  return ctx;
}

/**
 * Returns `true` when the given feature flag is enabled, `false` otherwise.
 * Defaults to `false` while flags are still loading.
 */
export function useFeatureFlag(name: string): boolean {
  const { flags } = useFeatureFlags();
  return flags[name] ?? false;
}
