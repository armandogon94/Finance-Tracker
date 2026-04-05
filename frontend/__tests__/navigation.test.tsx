import { describe, expect, it, vi } from "vitest";
import React from "react";
import { render, screen } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";

// ─── Mocks ─────────────────────────────────────────────────────────

// Mock next/navigation
const mockPathname = vi.fn(() => "/");

vi.mock("next/navigation", () => ({
  usePathname: () => mockPathname(),
}));

// Mock next/link to render a plain anchor
vi.mock("next/link", () => ({
  __esModule: true,
  default: ({
    children,
    href,
    ...props
  }: {
    children: React.ReactNode;
    href: string;
    [key: string]: unknown;
  }) => (
    <a href={href} {...props}>
      {children}
    </a>
  ),
}));

// Mock AuthContext
vi.mock("@/contexts/AuthContext", () => ({
  useAuth: () => ({ user: null, isAuthenticated: false, isLoading: false }),
}));

// Mock FeatureFlagsContext
vi.mock("@/contexts/FeatureFlagsContext", () => ({
  useFeatureFlags: () => ({ flags: {}, isLoading: false }),
  useFeatureFlag: () => false,
}));

// ─── Import after mocks ────────────────────────────────────────────

import Navigation from "@/components/Navigation";

// ─── Tests ─────────────────────────────────────────────────────────

describe("Navigation", () => {
  it("renders all five primary nav items", () => {
    mockPathname.mockReturnValue("/");
    render(<Navigation />);

    expect(screen.getByText("Home")).toBeInTheDocument();
    expect(screen.getByText("Expenses")).toBeInTheDocument();
    expect(screen.getByText("Scan")).toBeInTheDocument();
    expect(screen.getByText("Debt")).toBeInTheDocument();
    expect(screen.getByText("Chat")).toBeInTheDocument();
  });

  it("renders the More button", () => {
    mockPathname.mockReturnValue("/");
    render(<Navigation />);

    expect(screen.getByText("More")).toBeInTheDocument();
  });

  it("highlights Home when pathname is /", () => {
    mockPathname.mockReturnValue("/");
    render(<Navigation />);

    const homeLink = screen.getByText("Home").closest("a");
    expect(homeLink).toHaveClass("text-primary-500");

    const expensesLink = screen.getByText("Expenses").closest("a");
    expect(expensesLink).not.toHaveClass("text-primary-500");
  });

  it("highlights Expenses when pathname starts with /expenses", () => {
    mockPathname.mockReturnValue("/expenses");
    render(<Navigation />);

    const expensesLink = screen.getByText("Expenses").closest("a");
    expect(expensesLink).toHaveClass("text-primary-500");

    const homeLink = screen.getByText("Home").closest("a");
    expect(homeLink).not.toHaveClass("text-primary-500");
  });

  it("highlights Debt when on a debt sub-page", () => {
    mockPathname.mockReturnValue("/debt/strategies");
    render(<Navigation />);

    const debtLink = screen.getByText("Debt").closest("a");
    expect(debtLink).toHaveClass("text-primary-500");
  });

  it("links have correct href attributes", () => {
    mockPathname.mockReturnValue("/");
    render(<Navigation />);

    expect(screen.getByText("Home").closest("a")).toHaveAttribute("href", "/");
    expect(screen.getByText("Scan").closest("a")).toHaveAttribute(
      "href",
      "/scan"
    );
    expect(screen.getByText("Debt").closest("a")).toHaveAttribute(
      "href",
      "/debt"
    );
  });
});
