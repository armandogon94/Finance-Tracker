// ─── Types ──────────────────────────────────────────────────────────

export interface Debt {
  name: string;
  balance: number;
  apr: number;
  minPayment: number;
}

export interface CCPayoffResult {
  months: number;
  totalInterest: number;
  warning?: string;
}

export interface LoanScheduleEntry {
  month: number;
  payment: number;
  principal: number;
  interest: number;
  remainingBalance: number;
}

export interface LoanPayoffResult {
  months: number;
  totalInterest: number;
  schedule: LoanScheduleEntry[];
}

export interface TimelineEntry {
  month: number;
  debtName: string;
  payment: number;
  remainingBalance: number;
}

export interface SimulationResult {
  monthsToFreedom: number;
  totalInterest: number;
  timeline: TimelineEntry[];
}

export interface StrategyComparison {
  avalanche: SimulationResult;
  snowball: SimulationResult;
  hybrid: SimulationResult;
  minimumOnly: SimulationResult;
}

// ─── Helpers ────────────────────────────────────────────────────────

const MAX_MONTHS = 600; // 50 years -- safety cap

function monthlyRate(apr: number): number {
  return apr / 100 / 12;
}

// ─── Credit-card payoff ─────────────────────────────────────────────

export function calculateCCPayoff(
  balance: number,
  apr: number,
  monthlyPayment: number,
): CCPayoffResult {
  if (balance <= 0) return { months: 0, totalInterest: 0 };

  const r = monthlyRate(apr);

  // If the payment does not cover even the monthly interest the debt
  // will never be paid off.
  if (r > 0 && monthlyPayment <= balance * r) {
    return {
      months: Infinity,
      totalInterest: Infinity,
      warning:
        "Monthly payment does not cover the interest. The balance will grow indefinitely.",
    };
  }

  let remaining = balance;
  let months = 0;
  let totalInterest = 0;

  while (remaining > 0 && months < MAX_MONTHS) {
    const interest = remaining * r;
    totalInterest += interest;
    remaining += interest;

    const payment = Math.min(monthlyPayment, remaining);
    remaining -= payment;
    months++;
  }

  return {
    months,
    totalInterest: Math.round(totalInterest * 100) / 100,
  };
}

// ─── Loan payoff (amortisation) ─────────────────────────────────────

export function calculateLoanPayoff(
  balance: number,
  annualRate: number,
  monthlyPayment: number,
): LoanPayoffResult {
  if (balance <= 0) return { months: 0, totalInterest: 0, schedule: [] };

  const r = monthlyRate(annualRate);

  if (r > 0 && monthlyPayment <= balance * r) {
    return {
      months: Infinity,
      totalInterest: Infinity,
      schedule: [],
    };
  }

  let remaining = balance;
  let months = 0;
  let totalInterest = 0;
  const schedule: LoanScheduleEntry[] = [];

  while (remaining > 0.005 && months < MAX_MONTHS) {
    const interest = remaining * r;
    totalInterest += interest;

    const payment = Math.min(monthlyPayment, remaining + interest);
    const principal = payment - interest;
    remaining -= principal;
    if (remaining < 0) remaining = 0;
    months++;

    schedule.push({
      month: months,
      payment: Math.round(payment * 100) / 100,
      principal: Math.round(principal * 100) / 100,
      interest: Math.round(interest * 100) / 100,
      remainingBalance: Math.round(remaining * 100) / 100,
    });
  }

  return {
    months,
    totalInterest: Math.round(totalInterest * 100) / 100,
    schedule,
  };
}

// ─── Multi-debt simulation ──────────────────────────────────────────

/**
 * Simulate paying off a list of debts with a fixed monthly budget plus
 * an optional extra amount, prioritised by the given sort key.
 *
 * @param debts     Array of debts to pay off.
 * @param extra     Extra dollars per month beyond minimums.
 * @param sortKey   "apr" for avalanche (highest APR first),
 *                  "balance" for snowball (lowest balance first).
 */
export function simulatePayoff(
  debts: Debt[],
  extra: number,
  sortKey: "apr" | "balance",
): SimulationResult {
  if (debts.length === 0) {
    return { monthsToFreedom: 0, totalInterest: 0, timeline: [] };
  }

  // Working copies so we don't mutate the caller's data.
  const working = debts.map((d) => ({
    name: d.name,
    balance: d.balance,
    apr: d.apr,
    minPayment: d.minPayment,
  }));

  let month = 0;
  let totalInterest = 0;
  const timeline: TimelineEntry[] = [];

  while (working.some((d) => d.balance > 0.005) && month < MAX_MONTHS) {
    month++;

    // 1. Accrue interest
    for (const d of working) {
      if (d.balance <= 0) continue;
      const interest = d.balance * monthlyRate(d.apr);
      totalInterest += interest;
      d.balance += interest;
    }

    // 2. Pay minimums
    let budgetLeft = extra;
    for (const d of working) {
      if (d.balance <= 0) continue;
      const payment = Math.min(d.minPayment, d.balance);
      d.balance -= payment;

      timeline.push({
        month,
        debtName: d.name,
        payment: Math.round(payment * 100) / 100,
        remainingBalance: Math.round(Math.max(d.balance, 0) * 100) / 100,
      });
    }

    // 3. Apply extra to the prioritised debt
    const active = working
      .filter((d) => d.balance > 0.005)
      .sort((a, b) => {
        if (sortKey === "apr") return b.apr - a.apr; // highest APR first
        return a.balance - b.balance; // lowest balance first
      });

    for (const d of active) {
      if (budgetLeft <= 0) break;
      const extraPayment = Math.min(budgetLeft, d.balance);
      d.balance -= extraPayment;
      budgetLeft -= extraPayment;

      timeline.push({
        month,
        debtName: d.name,
        payment: Math.round(extraPayment * 100) / 100,
        remainingBalance: Math.round(Math.max(d.balance, 0) * 100) / 100,
      });
    }
  }

  return {
    monthsToFreedom: month,
    totalInterest: Math.round(totalInterest * 100) / 100,
    timeline,
  };
}

// ─── Compare all strategies ─────────────────────────────────────────

/**
 * Compares four debt-repayment strategies given a fixed monthly budget.
 *
 * The extra available each month is  `monthlyBudget - sum(minimums)`.
 */
export function compareStrategies(
  debts: Debt[],
  monthlyBudget: number,
): StrategyComparison {
  const totalMinimums = debts.reduce((sum, d) => sum + d.minPayment, 0);
  const extra = Math.max(0, monthlyBudget - totalMinimums);

  // Hybrid: alternate extra between highest-APR and lowest-balance each month.
  const hybridResult = simulateHybrid(debts, extra);

  return {
    avalanche: simulatePayoff(debts, extra, "apr"),
    snowball: simulatePayoff(debts, extra, "balance"),
    hybrid: hybridResult,
    minimumOnly: simulatePayoff(debts, 0, "apr"), // no extra -- strategy irrelevant
  };
}

// ─── Hybrid strategy ────────────────────────────────────────────────

function simulateHybrid(debts: Debt[], extra: number): SimulationResult {
  if (debts.length === 0) {
    return { monthsToFreedom: 0, totalInterest: 0, timeline: [] };
  }

  const working = debts.map((d) => ({
    name: d.name,
    balance: d.balance,
    apr: d.apr,
    minPayment: d.minPayment,
  }));

  let month = 0;
  let totalInterest = 0;
  const timeline: TimelineEntry[] = [];

  while (working.some((d) => d.balance > 0.005) && month < MAX_MONTHS) {
    month++;

    // 1. Accrue interest
    for (const d of working) {
      if (d.balance <= 0) continue;
      const interest = d.balance * monthlyRate(d.apr);
      totalInterest += interest;
      d.balance += interest;
    }

    // 2. Pay minimums
    for (const d of working) {
      if (d.balance <= 0) continue;
      const payment = Math.min(d.minPayment, d.balance);
      d.balance -= payment;

      timeline.push({
        month,
        debtName: d.name,
        payment: Math.round(payment * 100) / 100,
        remainingBalance: Math.round(Math.max(d.balance, 0) * 100) / 100,
      });
    }

    // 3. Hybrid extra: on odd months target highest APR, on even months
    //    target lowest balance.
    const active = working.filter((d) => d.balance > 0.005);
    const sorted =
      month % 2 === 1
        ? [...active].sort((a, b) => b.apr - a.apr)
        : [...active].sort((a, b) => a.balance - b.balance);

    let budgetLeft = extra;
    for (const d of sorted) {
      if (budgetLeft <= 0) break;
      const extraPayment = Math.min(budgetLeft, d.balance);
      d.balance -= extraPayment;
      budgetLeft -= extraPayment;

      timeline.push({
        month,
        debtName: d.name,
        payment: Math.round(extraPayment * 100) / 100,
        remainingBalance: Math.round(Math.max(d.balance, 0) * 100) / 100,
      });
    }
  }

  return {
    monthsToFreedom: month,
    totalInterest: Math.round(totalInterest * 100) / 100,
    timeline,
  };
}
