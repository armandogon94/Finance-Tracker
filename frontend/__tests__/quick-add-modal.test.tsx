import { describe, expect, it, vi, beforeEach } from "vitest";
import React from "react";
import { render, screen, fireEvent } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";

// ─── Mocks ─────────────────────────────────────────────────────────

const mockGetCategories = vi.fn().mockResolvedValue([
  { id: "cat-1", name: "Food", icon: "utensils", color: "#EF4444", is_active: true, is_hidden: false },
  { id: "cat-2", name: "Transport", icon: "car", color: "#F59E0B", is_active: true, is_hidden: false },
  { id: "cat-3", name: "Hidden", icon: "eye-off", color: "#666", is_active: true, is_hidden: true },
  { id: "cat-4", name: "Archived", icon: "box", color: "#999", is_active: false, is_hidden: false },
]);
const mockQuickAddExpense = vi.fn().mockResolvedValue({ id: "exp-1" });

vi.mock("@/lib/api", () => ({
  api: {
    getCategories: (...args: unknown[]) => mockGetCategories(...args),
    quickAddExpense: (...args: unknown[]) => mockQuickAddExpense(...args),
  },
}));

// ─── Import after mocks ────────────────────────────────────────────

import QuickAddModal from "@/components/QuickAddModal";

// ─── Tests ─────────────────────────────────────────────────────────

describe("QuickAddModal", () => {
  const onClose = vi.fn();
  const onSaved = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("renders nothing when isOpen is false", () => {
    const { container } = render(
      <QuickAddModal isOpen={false} onClose={onClose} onSaved={onSaved} />
    );
    expect(container.firstChild).toBeNull();
  });

  it("renders the modal when isOpen is true", () => {
    render(<QuickAddModal isOpen={true} onClose={onClose} onSaved={onSaved} />);
    expect(screen.getByText("Quick Add")).toBeInTheDocument();
  });

  it("shows $0 as the initial amount", () => {
    render(<QuickAddModal isOpen={true} onClose={onClose} onSaved={onSaved} />);
    expect(screen.getByText("$0")).toBeInTheDocument();
  });

  it("renders number pad keys (0-9 and decimal point)", () => {
    render(<QuickAddModal isOpen={true} onClose={onClose} onSaved={onSaved} />);
    for (const digit of ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "."]) {
      expect(screen.getByText(digit)).toBeInTheDocument();
    }
  });

  it("updates amount when digits are pressed", () => {
    render(<QuickAddModal isOpen={true} onClose={onClose} onSaved={onSaved} />);
    fireEvent.click(screen.getByText("4"));
    fireEvent.click(screen.getByText("5"));
    expect(screen.getByText("$45")).toBeInTheDocument();
  });

  it("handles decimal input correctly", () => {
    render(<QuickAddModal isOpen={true} onClose={onClose} onSaved={onSaved} />);
    fireEvent.click(screen.getByText("1"));
    fireEvent.click(screen.getByText("2"));
    fireEvent.click(screen.getByText("."));
    fireEvent.click(screen.getByText("5"));
    expect(screen.getByText("$12.5")).toBeInTheDocument();
  });

  it("limits decimal places to 2", () => {
    render(<QuickAddModal isOpen={true} onClose={onClose} onSaved={onSaved} />);
    fireEvent.click(screen.getByText("1"));
    fireEvent.click(screen.getByText("."));
    fireEvent.click(screen.getByText("9"));
    fireEvent.click(screen.getByText("9"));
    // Third decimal digit should be ignored
    fireEvent.click(screen.getByText("5"));
    expect(screen.getByText("$1.99")).toBeInTheDocument();
  });

  it("prevents multiple decimal points", () => {
    render(<QuickAddModal isOpen={true} onClose={onClose} onSaved={onSaved} />);
    fireEvent.click(screen.getByText("1"));
    fireEvent.click(screen.getByText("."));
    fireEvent.click(screen.getByText("."));
    fireEvent.click(screen.getByText("5"));
    expect(screen.getByText("$1.5")).toBeInTheDocument();
  });

  it("replaces leading zero with digit", () => {
    render(<QuickAddModal isOpen={true} onClose={onClose} onSaved={onSaved} />);
    // Initially $0, pressing 7 should give $7, not $07
    fireEvent.click(screen.getByText("7"));
    expect(screen.getByText("$7")).toBeInTheDocument();
  });

  it("filters out hidden and inactive categories", async () => {
    render(<QuickAddModal isOpen={true} onClose={onClose} onSaved={onSaved} />);
    // Wait for categories to load
    await vi.waitFor(() => {
      expect(screen.getByText("Food")).toBeInTheDocument();
      expect(screen.getByText("Transport")).toBeInTheDocument();
    });
    // Hidden and inactive should not appear
    expect(screen.queryByText("Hidden")).not.toBeInTheDocument();
    expect(screen.queryByText("Archived")).not.toBeInTheDocument();
  });

  it("shows error when trying to save with zero amount", async () => {
    render(<QuickAddModal isOpen={true} onClose={onClose} onSaved={onSaved} />);
    // Find and click the save/check button
    const checkBtn = screen.getByRole("button", { name: /save|add|check/i });
    if (checkBtn) {
      fireEvent.click(checkBtn);
      await vi.waitFor(() => {
        expect(screen.getByText(/enter an amount/i)).toBeInTheDocument();
      });
    }
  });
});
