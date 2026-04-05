"use client";

import React, {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  useMemo,
} from "react";
import { api } from "@/lib/api";
import type { User } from "@/types";

// ─── Types ──────────────────────────────────────────────────────────

interface AuthState {
  user: User | null;
  isAuthenticated: boolean;
  isLoading: boolean;
}

interface AuthContextValue extends AuthState {
  login: (email: string, password: string) => Promise<void>;
  register: (email: string, password: string, displayName?: string) => Promise<void>;
  logout: () => void;
}

// ─── Context ────────────────────────────────────────────────────────

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

// ─── Provider ───────────────────────────────────────────────────────

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  // Check for an existing session on mount
  useEffect(() => {
    const token = localStorage.getItem("access_token");
    if (!token) {
      setIsLoading(false);
      return;
    }

    api.setToken(token);
    api
      .getMe()
      .then((me: User) => setUser(me))
      .catch(() => {
        // Token invalid or expired -- clear everything
        localStorage.removeItem("access_token");
        localStorage.removeItem("refresh_token");
        api.setToken(null);
      })
      .finally(() => setIsLoading(false));
  }, []);

  // ── login ──────────────────────────────────────────────────────────

  const login = useCallback(async (email: string, password: string) => {
    const { access_token, refresh_token } = await api.login(email, password);

    localStorage.setItem("access_token", access_token);
    localStorage.setItem("refresh_token", refresh_token);
    api.setToken(access_token);

    const me: User = await api.getMe();
    setUser(me);
  }, []);

  // ── register ───────────────────────────────────────────────────────

  const register = useCallback(
    async (email: string, password: string, displayName?: string) => {
      const { access_token, refresh_token } = await api.register(
        email,
        password,
        displayName,
      );

      localStorage.setItem("access_token", access_token);
      localStorage.setItem("refresh_token", refresh_token);
      api.setToken(access_token);

      const me: User = await api.getMe();
      setUser(me);
    },
    [],
  );

  // ── logout ─────────────────────────────────────────────────────────

  const logout = useCallback(() => {
    // Revoke refresh tokens server-side before clearing local state
    api.logout().catch(() => {});
    localStorage.removeItem("access_token");
    localStorage.removeItem("refresh_token");
    api.setToken(null);
    setUser(null);
  }, []);

  // ── value ──────────────────────────────────────────────────────────

  const value = useMemo<AuthContextValue>(
    () => ({
      user,
      isAuthenticated: user !== null,
      isLoading,
      login,
      register,
      logout,
    }),
    [user, isLoading, login, register, logout],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

// ─── Hook ───────────────────────────────────────────────────────────

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (ctx === undefined) {
    throw new Error("useAuth must be used within an AuthProvider");
  }
  return ctx;
}
