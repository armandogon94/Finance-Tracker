import { describe, expect, it } from "vitest";
import {
  calculateCCPayoff,
  calculateLoanPayoff,
  compareStrategies,
} from "@/lib/debt-math";

describe("calculateCCPayoff", () => {
  it("calculates basic payoff correctly", () => {
    // APR as percentage: 20 = 20%, monthly rate = 20/100/12 = 0.01667
    const result = calculateCCPayoff(5000, 20, 200);
    expect(result.months).toBeGreaterThan(25);
    expect(result.months).toBeLessThan(35);
    expect(result.totalInterest).toBeGreaterThan(500);
    expect(result.warning).toBeUndefined();
  });

  it("handles very low payment with Infinity or warning", () => {
    // $50/mo doesn't cover monthly interest of ~$83
    const result = calculateCCPayoff(5000, 20, 50);
    expect(result.months).toBe(Infinity);
    expect(result.warning).toBeDefined();
  });

  it("handles zero balance", () => {
    const result = calculateCCPayoff(0, 0.20, 200);
    expect(result.months).toBe(0);
    expect(result.totalInterest).toBe(0);
  });

  it("handles zero APR", () => {
    const result = calculateCCPayoff(1000, 0, 100);
    expect(result.months).toBe(10);
    expect(result.totalInterest).toBe(0);
  });
});

describe("calculateLoanPayoff", () => {
  it("generates correct schedule length", () => {
    // Annual rate as percentage: 6 = 6%
    const result = calculateLoanPayoff(20000, 6, 400);
    expect(result.months).toBeGreaterThan(50);
    expect(result.months).toBeLessThan(65);
    expect(result.totalInterest).toBeGreaterThan(1500);
    expect(result.schedule.length).toBe(result.months);
  });

  it("final balance is near zero", () => {
    const result = calculateLoanPayoff(10000, 5, 300);
    const lastEntry = result.schedule[result.schedule.length - 1];
    expect(lastEntry.remainingBalance).toBeLessThan(1);
  });

  it("interest decreases over time", () => {
    const result = calculateLoanPayoff(10000, 5, 300);
    const firstInterest = result.schedule[0].interest;
    const lastInterest = result.schedule[result.schedule.length - 1].interest;
    expect(firstInterest).toBeGreaterThan(lastInterest);
  });
});

describe("compareStrategies", () => {
  const debts = [
    { name: "Card A", balance: 2000, apr: 24, minPayment: 50 },
    { name: "Card B", balance: 8000, apr: 18, minPayment: 160 },
    { name: "Loan C", balance: 500, apr: 10, minPayment: 25 },
  ];

  it("returns all four strategies", () => {
    const result = compareStrategies(debts, 500);
    expect(result.avalanche).toBeDefined();
    expect(result.snowball).toBeDefined();
    expect(result.hybrid).toBeDefined();
    expect(result.minimumOnly).toBeDefined();
  });

  it("avalanche has lowest or equal interest vs snowball", () => {
    const result = compareStrategies(debts, 500);
    expect(result.avalanche.totalInterest).toBeLessThanOrEqual(
      result.snowball.totalInterest + 1 // allow rounding
    );
  });

  it("minimum only takes longest", () => {
    const result = compareStrategies(debts, 500);
    expect(result.minimumOnly.monthsToFreedom).toBeGreaterThanOrEqual(
      result.avalanche.monthsToFreedom
    );
  });

  it("handles insufficient budget with long payoff", () => {
    const result = compareStrategies(debts, 100);
    // Budget < sum of minimums (235), payoff takes very long or has high interest
    expect(result.avalanche.monthsToFreedom).toBeGreaterThan(0);
    expect(result.avalanche.totalInterest).toBeGreaterThan(0);
  });
});
