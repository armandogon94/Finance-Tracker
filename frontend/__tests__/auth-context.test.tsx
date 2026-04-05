import { describe, expect, it, vi, beforeEach } from "vitest";
import React from "react";
import { render, screen, act } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";

// ─── Mocks ─────────────────────────────────────────────────────────

const mockLogin = vi.fn();
const mockRegister = vi.fn();
const mockGetMe = vi.fn();
const mockSetToken = vi.fn();
const mockLogoutApi = vi.fn().mockResolvedValue(undefined);

vi.mock("@/lib/api", () => ({
  api: {
    login: (...args: unknown[]) => mockLogin(...args),
    register: (...args: unknown[]) => mockRegister(...args),
    getMe: () => mockGetMe(),
    setToken: (t: unknown) => mockSetToken(t),
    logout: () => mockLogoutApi(),
  },
}));

// Mock localStorage
const store: Record<string, string> = {};
const mockLocalStorage = {
  getItem: vi.fn((key: string) => store[key] ?? null),
  setItem: vi.fn((key: string, value: string) => { store[key] = value; }),
  removeItem: vi.fn((key: string) => { delete store[key]; }),
  clear: vi.fn(() => { Object.keys(store).forEach(k => delete store[k]); }),
};
Object.defineProperty(global, "localStorage", { value: mockLocalStorage });

// ─── Import after mocks ────────────────────────────────────────────

import { AuthProvider, useAuth } from "@/contexts/AuthContext";

// Helper to render a component that uses useAuth
function TestConsumer() {
  const { user, isAuthenticated, isLoading, login, register, logout } = useAuth();
  return (
    <div>
      <span data-testid="loading">{isLoading ? "loading" : "ready"}</span>
      <span data-testid="authenticated">{isAuthenticated ? "yes" : "no"}</span>
      <span data-testid="user">{user?.email ?? "none"}</span>
      <button data-testid="login-btn" onClick={() => login("test@example.com", "pass")}>Login</button>
      <button data-testid="register-btn" onClick={() => register("new@example.com", "pass", "New")}>Register</button>
      <button data-testid="logout-btn" onClick={logout}>Logout</button>
    </div>
  );
}

// ─── Tests ─────────────────────────────────────────────────────────

describe("AuthContext", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    Object.keys(store).forEach(k => delete store[k]);
  });

  it("starts unauthenticated when no token in localStorage", async () => {
    render(
      <AuthProvider><TestConsumer /></AuthProvider>
    );

    await vi.waitFor(() => {
      expect(screen.getByTestId("loading")).toHaveTextContent("ready");
    });
    expect(screen.getByTestId("authenticated")).toHaveTextContent("no");
    expect(screen.getByTestId("user")).toHaveTextContent("none");
  });

  it("loads user from existing token on mount", async () => {
    store["access_token"] = "existing-token";
    mockGetMe.mockResolvedValueOnce({ id: "u1", email: "test@example.com" });

    render(
      <AuthProvider><TestConsumer /></AuthProvider>
    );

    await vi.waitFor(() => {
      expect(screen.getByTestId("loading")).toHaveTextContent("ready");
    });
    expect(mockSetToken).toHaveBeenCalledWith("existing-token");
    expect(screen.getByTestId("authenticated")).toHaveTextContent("yes");
    expect(screen.getByTestId("user")).toHaveTextContent("test@example.com");
  });

  it("clears state when existing token is invalid", async () => {
    store["access_token"] = "bad-token";
    mockGetMe.mockRejectedValueOnce(new Error("401"));

    render(
      <AuthProvider><TestConsumer /></AuthProvider>
    );

    await vi.waitFor(() => {
      expect(screen.getByTestId("loading")).toHaveTextContent("ready");
    });
    expect(screen.getByTestId("authenticated")).toHaveTextContent("no");
    expect(mockLocalStorage.removeItem).toHaveBeenCalledWith("access_token");
    expect(mockLocalStorage.removeItem).toHaveBeenCalledWith("refresh_token");
  });

  it("login stores tokens and loads user", async () => {
    mockLogin.mockResolvedValueOnce({
      access_token: "new-access",
      refresh_token: "new-refresh",
    });
    mockGetMe.mockResolvedValueOnce({ id: "u2", email: "test@example.com" });

    render(
      <AuthProvider><TestConsumer /></AuthProvider>
    );

    await vi.waitFor(() => {
      expect(screen.getByTestId("loading")).toHaveTextContent("ready");
    });

    await act(async () => {
      screen.getByTestId("login-btn").click();
    });

    await vi.waitFor(() => {
      expect(screen.getByTestId("authenticated")).toHaveTextContent("yes");
    });
    expect(mockLocalStorage.setItem).toHaveBeenCalledWith("access_token", "new-access");
    expect(mockLocalStorage.setItem).toHaveBeenCalledWith("refresh_token", "new-refresh");
    expect(mockSetToken).toHaveBeenCalledWith("new-access");
  });

  it("register stores tokens and loads user", async () => {
    mockRegister.mockResolvedValueOnce({
      access_token: "reg-access",
      refresh_token: "reg-refresh",
    });
    mockGetMe.mockResolvedValueOnce({ id: "u3", email: "new@example.com" });

    render(
      <AuthProvider><TestConsumer /></AuthProvider>
    );

    await vi.waitFor(() => {
      expect(screen.getByTestId("loading")).toHaveTextContent("ready");
    });

    await act(async () => {
      screen.getByTestId("register-btn").click();
    });

    await vi.waitFor(() => {
      expect(screen.getByTestId("user")).toHaveTextContent("new@example.com");
    });
    expect(mockRegister).toHaveBeenCalledWith("new@example.com", "pass", "New");
  });

  it("logout clears user and tokens and calls server logout", async () => {
    store["access_token"] = "existing-token";
    mockGetMe.mockResolvedValueOnce({ id: "u1", email: "test@example.com" });

    render(
      <AuthProvider><TestConsumer /></AuthProvider>
    );

    await vi.waitFor(() => {
      expect(screen.getByTestId("authenticated")).toHaveTextContent("yes");
    });

    await act(async () => {
      screen.getByTestId("logout-btn").click();
    });

    expect(screen.getByTestId("authenticated")).toHaveTextContent("no");
    expect(screen.getByTestId("user")).toHaveTextContent("none");
    expect(mockLogoutApi).toHaveBeenCalled();
    expect(mockLocalStorage.removeItem).toHaveBeenCalledWith("access_token");
    expect(mockSetToken).toHaveBeenCalledWith(null);
  });
});
