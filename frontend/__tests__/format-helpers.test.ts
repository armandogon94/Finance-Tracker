import { describe, expect, it } from "vitest";

// ─── Extracted helpers ─────────────────────────────────────────────
//
// These functions are duplicated in 9+ page files across the frontend.
// We test the two variants here to verify the formatting logic
// that the whole app relies on.

/** Currency formatter — 2 decimal places (used in most pages) */
function fmt(n: number): string {
  return n.toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
  });
}

/** Currency formatter — 0 decimal places (used in debt page) */
function fmtRounded(n: number): string {
  return n.toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  });
}

/** Percentage formatter (used in debt page) */
function fmtPct(n: number): string {
  return `${n.toFixed(1)}%`;
}

// ─── Tests ─────────────────────────────────────────────────────────

describe("fmt (currency, 2 decimals)", () => {
  it("formats a typical dollar amount", () => {
    const result = fmt(1234.56);
    expect(result).toContain("1,234.56");
    expect(result).toContain("$");
  });

  it("formats zero", () => {
    const result = fmt(0);
    expect(result).toContain("$");
    expect(result).toContain("0.00");
  });

  it("formats negative numbers", () => {
    const result = fmt(-50.5);
    // Different engines may produce -$50.50 or ($50.50)
    expect(result).toContain("50.50");
  });

  it("formats large numbers with comma separators", () => {
    const result = fmt(1000000);
    expect(result).toContain("1,000,000");
  });

  it("preserves two decimal digits for whole numbers", () => {
    const result = fmt(42);
    expect(result).toContain("42.00");
  });
});

describe("fmtRounded (currency, 0 decimals)", () => {
  it("rounds to whole dollars", () => {
    const result = fmtRounded(1234.56);
    expect(result).toContain("1,235");
    expect(result).not.toContain(".");
  });

  it("formats zero without decimals", () => {
    const result = fmtRounded(0);
    expect(result).toContain("$");
    expect(result).toContain("0");
    expect(result).not.toContain(".00");
  });

  it("formats large values", () => {
    const result = fmtRounded(99999.99);
    expect(result).toContain("100,000");
  });
});

describe("fmtPct (percentage)", () => {
  it("formats a typical percentage", () => {
    expect(fmtPct(24.5)).toBe("24.5%");
  });

  it("formats zero", () => {
    expect(fmtPct(0)).toBe("0.0%");
  });

  it("rounds to one decimal place", () => {
    expect(fmtPct(33.333)).toBe("33.3%");
  });

  it("formats 100 percent", () => {
    expect(fmtPct(100)).toBe("100.0%");
  });

  it("handles negative percentages", () => {
    expect(fmtPct(-5.67)).toBe("-5.7%");
  });
});
