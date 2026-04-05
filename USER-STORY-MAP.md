# User Story Map -- Finance Tracker

> Jeff Patton-style story map for the Finance Tracker expense tracking application.
> Covers all 8 user activities, 50+ user tasks, and 60 detailed user stories with
> full test traceability to backend (pytest), frontend (vitest), and E2E (Playwright).

---

## 1. Story Map Overview

This document follows the **Jeff Patton User Story Mapping** format. Reading the map:

- **Backbone (top row):** The 8 high-level *user activities* that describe the major things users do with the system. These are the column headers and flow left-to-right in a rough usage sequence.
- **Walking skeleton (second row):** Under each activity, *user tasks* break the activity into concrete steps a user performs. Tasks are ordered top-to-bottom by priority within their column.
- **Story cards (body):** Each task decomposes into one or more *user stories* -- the smallest unit of deliverable value. Stories are sliced into three horizontal bands:
  - **MVP** -- Minimum viable product. The system is usable with only these stories.
  - **v1** -- First full release. Adds completeness and polish.
  - **v2** -- Future enhancements. Nice-to-haves and advanced features.
- **Traceability:** Every story links to specific backend test files, frontend test files, and E2E spec sections, with explicit `COVERED`, `PARTIAL`, or `GAP` markers.

### Personas

| Persona | Role | Notes |
|---------|------|-------|
| **Armando** | Superuser / Admin | Full access, all features enabled, manages other users |
| **Mom** | Standard User | Core expense tracking, debt management, Spanish-friendly |
| **Demo Reviewer** | Evaluator | Reads analytics, tests input methods, evaluates UX |
| **Future User** | New Registrant | Onboards, sets up categories, begins tracking |

### Numbering Convention

- Activities: A1 through A8
- Tasks: T{activity}.{sequence} (e.g., T2.3 is the 3rd task under Activity 2)
- Stories: US-{activity}{sequence} (e.g., US-203 is the 3rd story under Activity 2)

---

## 2. Backbone (User Activities)

| A1: Authenticate | A2: Track Expenses | A3: Manage Categories | A4: Scan Receipts | A5: Import Statements | A6: Manage Debt | A7: Analyze Spending | A8: Communicate |
|---|---|---|---|---|---|---|---|
| Register, log in, manage session | Add/edit/delete daily expenses | Create, reorder, budget categories | Photograph and OCR receipts | Upload bank/CC CSV and PDF files | Track CCs, loans, payoff strategies | View charts, budgets, tax exports | AI Chat, Telegram bot, admin panel |

---

## 3. User Tasks

### A1: Authenticate
| ID | Task |
|----|------|
| T1.1 | Register a new account |
| T1.2 | Log in with email and password |
| T1.3 | Refresh an expired session |
| T1.4 | View/update my profile |
| T1.5 | Reset a forgotten password |

### A2: Track Expenses
| ID | Task |
|----|------|
| T2.1 | Quick-add an expense (amount + category) |
| T2.2 | Create a full expense (all fields) |
| T2.3 | View and filter expense list |
| T2.4 | Edit an existing expense |
| T2.5 | Delete an expense |
| T2.6 | View hidden-category expenses (feature-gated) |
| T2.7 | Set up recurring expense templates |

### A3: Manage Categories
| ID | Task |
|----|------|
| T3.1 | Create a new category |
| T3.2 | Reorder categories via drag-and-drop |
| T3.3 | Edit category name, icon, color, budget |
| T3.4 | Archive (soft-delete) a category |
| T3.5 | Set a monthly budget per category |
| T3.6 | Mark a category as hidden (feature-gated) |

### A4: Scan Receipts
| ID | Task |
|----|------|
| T4.1 | Capture a receipt photo |
| T4.2 | Run OCR extraction on the image |
| T4.3 | Review and confirm extracted data |
| T4.4 | Queue receipts for later review |
| T4.5 | Browse receipt archive by month/year |
| T4.6 | Flag receipts as tax-deductible |

### A5: Import Statements
| ID | Task |
|----|------|
| T5.1 | Upload a CSV bank statement |
| T5.2 | Upload a PDF bank statement |
| T5.3 | Review parsed transactions with auto-labels |
| T5.4 | Confirm and import selected transactions |
| T5.5 | Manage auto-label rules |
| T5.6 | View import history |

### A6: Manage Debt
| ID | Task |
|----|------|
| T6.1 | Add a credit card |
| T6.2 | Add a personal loan |
| T6.3 | View debt summary dashboard |
| T6.4 | Compare payoff strategies |
| T6.5 | Log a debt payment |
| T6.6 | Log a snowflake (windfall) payment |
| T6.7 | Manage friend debt (feature-gated) |
| T6.8 | Delete a credit card or loan |

### A7: Analyze Spending
| ID | Task |
|----|------|
| T7.1 | View daily/weekly/monthly spending charts |
| T7.2 | View category breakdown (pie chart) |
| T7.3 | Check budget status per category |
| T7.4 | View dashboard summary (today/week/month) |
| T7.5 | Export tax summary and receipts |
| T7.6 | Compare spending across periods |

### A8: Communicate
| ID | Task |
|----|------|
| T8.1 | Chat with AI finance assistant |
| T8.2 | Manage chat conversations |
| T8.3 | Link Telegram account |
| T8.4 | Log expenses via Telegram bot |
| T8.5 | Query spending via Telegram bot |
| T8.6 | Manage users and feature flags (admin) |
| T8.7 | View system statistics (admin) |

---

## 4. Story Map Table

Each cell contains the user story IDs that belong to that activity-priority intersection.

| Priority | A1: Authenticate | A2: Track Expenses | A3: Manage Categories | A4: Scan Receipts | A5: Import Statements | A6: Manage Debt | A7: Analyze Spending | A8: Communicate |
|----------|---|---|---|---|---|---|---|---|
| **MVP** | US-101, US-102, US-103 | US-201, US-202, US-203, US-204 | US-301, US-302 | US-401, US-402 | US-501 | US-601, US-602, US-603 | US-701, US-702 | US-801 |
| **v1** | US-104, US-105 | US-205, US-206 | US-303, US-304, US-305 | US-403, US-404, US-405 | US-502, US-503, US-504 | US-604, US-605, US-606, US-607 | US-703, US-704, US-705 | US-802, US-803, US-804, US-805, US-806 |
| **v2** | US-106 | US-207, US-208 | US-306 | US-406 | US-505, US-506 | US-608, US-609 | US-706, US-707 | US-807, US-808, US-809 |

---

## 5. User Stories (Detailed)

---

### A1: Authenticate

---

#### US-101: Register a New Account
**As a** Future User, **I can** create an account with email, password, and display name, **so that** I have a personal space to track my finances.
**Feature IDs:** F-AUTH-01
**Priority:** MVP
**Backend Test:** `test_auth.py` | COVERED
**Frontend Test:** `api-client.test.ts` (register method) | COVERED
**E2E Test:** `finance-workflow.spec.ts` ("register a new account") | COVERED
**Coverage:** COVERED

---

#### US-102: Log In with Credentials
**As a** Mom, **I can** log in with my email and password, **so that** I can access my expenses securely from any device.
**Feature IDs:** F-AUTH-02
**Priority:** MVP
**Backend Test:** `test_auth.py` | COVERED
**Frontend Test:** `api-client.test.ts` (login method) | COVERED
**E2E Test:** `finance-workflow.spec.ts` | GAP (no explicit login-after-logout test)
**Coverage:** PARTIAL

---

#### US-103: Refresh an Expired Session
**As a** Armando, **I can** have my session automatically refreshed when my access token expires, **so that** I am not forced to re-enter my password every 15 minutes.
**Feature IDs:** F-AUTH-03
**Priority:** MVP
**Backend Test:** `test_auth.py` | COVERED
**Frontend Test:** `api-client.test.ts` (refreshToken method) | COVERED
**E2E Test:** `finance-workflow.spec.ts` | GAP
**Coverage:** PARTIAL

---

#### US-104: View and Update My Profile
**As a** Mom, **I can** view and update my display name, currency, and timezone, **so that** the app is personalized for my region and preferences.
**Feature IDs:** F-AUTH-04
**Priority:** v1
**Backend Test:** `test_auth.py` | COVERED
**Frontend Test:** `api-client.test.ts` (getMe) | COVERED
**E2E Test:** `finance-workflow.spec.ts` | GAP (settings page not tested)
**Coverage:** PARTIAL

---

#### US-105: Reset a Forgotten Password
**As a** Future User, **I can** request a password reset email and set a new password, **so that** I can recover access if I forget my credentials.
**Feature IDs:** F-AUTH-05
**Priority:** v1
**Backend Test:** `test_auth.py` | GAP (no reset password test)
**Frontend Test:** GAP
**E2E Test:** GAP
**Coverage:** GAP

---

#### US-106: Add to Home Screen (PWA)
**As a** Mom, **I can** add the web app to my phone's home screen, **so that** it feels like a native app with a quick launch icon.
**Feature IDs:** F-AUTH-06
**Priority:** v2
**Backend Test:** N/A (frontend-only)
**Frontend Test:** GAP
**E2E Test:** GAP
**Coverage:** GAP

---

### A2: Track Expenses

---

#### US-201: Quick-Add an Expense
**As a** Armando, **I can** enter an amount and tap a category to log an expense in under 10 seconds, **so that** I can capture spending the moment it happens without friction.
**Feature IDs:** F-EXP-01
**Priority:** MVP
**Backend Test:** `test_expenses.py` | COVERED
**Frontend Test:** GAP (QuickAddModal not unit-tested)
**E2E Test:** `finance-workflow.spec.ts` ("add expenses via API") | COVERED
**Coverage:** PARTIAL

---

#### US-202: Create a Full Expense
**As a** Mom, **I can** create an expense with amount, category, description, merchant, date, and notes, **so that** I have complete records for my bookkeeping.
**Feature IDs:** F-EXP-02
**Priority:** MVP
**Backend Test:** `test_expenses.py` | COVERED
**Frontend Test:** `api-client.test.ts` (createExpense) | COVERED
**E2E Test:** `finance-workflow.spec.ts` ("add expenses via API") | COVERED
**Coverage:** COVERED

---

#### US-203: View and Filter Expense List
**As a** Demo Reviewer, **I can** browse my expenses grouped by date, search by keyword, and filter by category or amount range, **so that** I can quickly find specific transactions.
**Feature IDs:** F-EXP-03
**Priority:** MVP
**Backend Test:** `test_expenses.py` | COVERED
**Frontend Test:** GAP (Expenses page component not tested)
**E2E Test:** `finance-workflow.spec.ts` ("view expenses list") | COVERED
**Coverage:** PARTIAL

---

#### US-204: Delete an Expense
**As a** Armando, **I can** delete an expense I entered by mistake, **so that** my records stay accurate.
**Feature IDs:** F-EXP-04
**Priority:** MVP
**Backend Test:** `test_expenses.py` | COVERED
**Frontend Test:** `api-client.test.ts` (deleteExpense) | COVERED
**E2E Test:** `finance-workflow.spec.ts` | GAP (no delete flow)
**Coverage:** PARTIAL

---

#### US-205: Edit an Existing Expense
**As a** Mom, **I can** tap an expense to edit its amount, category, or description, **so that** I can correct mistakes after the fact.
**Feature IDs:** F-EXP-05
**Priority:** v1
**Backend Test:** `test_expenses.py` | COVERED
**Frontend Test:** GAP (expense edit component not tested)
**E2E Test:** GAP
**Coverage:** PARTIAL

---

#### US-206: View Hidden-Category Expenses
**As a** Armando, **I can** access a private expenses view showing only hidden-category transactions, **so that** I can review discreet spending separately from the main list.
**Feature IDs:** F-EXP-06
**Priority:** v1
**Backend Test:** `test_feature_flags.py` | PARTIAL (flag check tested, not hidden expenses endpoint)
**Frontend Test:** GAP (hidden page component not tested)
**E2E Test:** GAP
**Coverage:** GAP

---

#### US-207: Set Up Recurring Expense Templates
**As a** Mom, **I can** create a recurring expense (e.g., monthly rent), **so that** the app auto-creates it each period without me remembering.
**Feature IDs:** F-EXP-07
**Priority:** v2
**Backend Test:** GAP (no recurring expenses test)
**Frontend Test:** GAP
**E2E Test:** GAP
**Coverage:** GAP

---

#### US-208: Multi-User Data Isolation
**As a** Mom, **I can** only see my own expenses and never Armando's, **so that** each user's financial data is completely private.
**Feature IDs:** F-EXP-08
**Priority:** v2
**Backend Test:** GAP (data_isolation not tested)
**Frontend Test:** GAP
**E2E Test:** GAP
**Coverage:** GAP

---

### A3: Manage Categories

---

#### US-301: Create a New Category
**As a** Future User, **I can** create a category with a name, icon, and color, **so that** I can organize my expenses the way I think about spending.
**Feature IDs:** F-CAT-01
**Priority:** MVP
**Backend Test:** `test_categories.py` | COVERED
**Frontend Test:** GAP (categories page not unit-tested)
**E2E Test:** `finance-workflow.spec.ts` ("create expense categories via API") | COVERED
**Coverage:** PARTIAL

---

#### US-302: Reorder Categories via Drag-and-Drop
**As a** Armando, **I can** drag categories into my preferred order, **so that** the most-used categories appear first in the quick-add grid.
**Feature IDs:** F-CAT-02
**Priority:** MVP
**Backend Test:** `test_categories.py` | COVERED
**Frontend Test:** `api-client.test.ts` (reorderCategories) | COVERED
**E2E Test:** GAP
**Coverage:** PARTIAL

---

#### US-303: Edit a Category
**As a** Mom, **I can** change a category's name, icon, color, or budget, **so that** I can keep my taxonomy up to date as my spending habits change.
**Feature IDs:** F-CAT-03
**Priority:** v1
**Backend Test:** `test_categories.py` | COVERED
**Frontend Test:** GAP
**E2E Test:** GAP
**Coverage:** PARTIAL

---

#### US-304: Archive a Category
**As a** Armando, **I can** archive a category I no longer use, **so that** it stops appearing in the quick-add grid but my historical expenses remain intact.
**Feature IDs:** F-CAT-04
**Priority:** v1
**Backend Test:** `test_categories.py` | COVERED
**Frontend Test:** GAP
**E2E Test:** GAP
**Coverage:** PARTIAL

---

#### US-305: Set a Monthly Budget per Category
**As a** Mom, **I can** set a monthly spending limit on any category, **so that** I can track whether I am staying within my budget.
**Feature IDs:** F-CAT-05
**Priority:** v1
**Backend Test:** `test_categories.py` | COVERED
**Frontend Test:** GAP
**E2E Test:** GAP
**Coverage:** PARTIAL

---

#### US-306: Mark a Category as Hidden
**As a** Armando, **I can** flag a category as hidden (when the feature is enabled by admin), **so that** expenses in that category do not appear on the main dashboard or analytics.
**Feature IDs:** F-CAT-06
**Priority:** v2
**Backend Test:** `test_feature_flags.py` | PARTIAL (flag toggle tested)
**Frontend Test:** GAP
**E2E Test:** GAP
**Coverage:** GAP

---

### A4: Scan Receipts

---

#### US-401: Capture a Receipt Photo
**As a** Armando, **I can** open the camera from the scan page and photograph a receipt, **so that** I can log expenses without typing any details.
**Feature IDs:** F-REC-01
**Priority:** MVP
**Backend Test:** N/A (client-side camera)
**Frontend Test:** GAP (ReceiptScanner component not tested)
**E2E Test:** `finance-workflow.spec.ts` ("visit scan page") | PARTIAL (page-load only, no camera in headless)
**Coverage:** GAP

---

#### US-402: Run OCR on a Receipt Image
**As a** Mom, **I can** have the app automatically extract amount, tax, merchant, and date from a receipt photo, **so that** I do not have to type those details manually.
**Feature IDs:** F-REC-02
**Priority:** MVP
**Backend Test:** GAP (receipt_scan service not directly tested)
**Frontend Test:** `api-client.test.ts` (scanReceipt) | COVERED
**E2E Test:** GAP (OCR pipeline not exercised in E2E)
**Coverage:** GAP

---

#### US-403: Review and Confirm Extracted Data
**As a** Armando, **I can** review the OCR-extracted fields and correct any errors before saving, **so that** my expense records are accurate even if OCR is imperfect.
**Feature IDs:** F-REC-03
**Priority:** v1
**Backend Test:** GAP
**Frontend Test:** GAP
**E2E Test:** GAP
**Coverage:** GAP

---

#### US-404: Queue Receipts for Later Review
**As a** Mom, **I can** upload a receipt to a pending queue, **so that** I can batch-review and categorize receipts when I have time.
**Feature IDs:** F-REC-04
**Priority:** v1
**Backend Test:** `test_pending_receipts.py` | COVERED
**Frontend Test:** `api-client.test.ts` (queueReceipt, getPendingReceipts) | COVERED
**E2E Test:** `finance-workflow.spec.ts` ("visit receipts page") | PARTIAL (page loads but no queue interaction)
**Coverage:** PARTIAL

---

#### US-405: Browse Receipt Archive
**As a** Demo Reviewer, **I can** browse stored receipt images organized by year and month, **so that** I can find any receipt for record-keeping or disputes.
**Feature IDs:** F-REC-05
**Priority:** v1
**Backend Test:** GAP (receipt archive endpoint not tested)
**Frontend Test:** GAP
**E2E Test:** `finance-workflow.spec.ts` ("visit receipts page") | PARTIAL
**Coverage:** GAP

---

#### US-406: Flag Receipts as Tax-Deductible
**As a** Armando, **I can** mark specific receipts as tax-deductible and assign a tax category, **so that** I can easily find and export them during tax season.
**Feature IDs:** F-REC-06
**Priority:** v2
**Backend Test:** GAP (tax_export tests absent)
**Frontend Test:** GAP
**E2E Test:** GAP
**Coverage:** GAP

---

### A5: Import Statements

---

#### US-501: Upload a CSV Bank Statement
**As a** Armando, **I can** upload a CSV file from my bank, **so that** dozens of transactions are parsed automatically instead of entering them one by one.
**Feature IDs:** F-IMP-01
**Priority:** MVP
**Backend Test:** `test_csv_parser.py` | COVERED
**Frontend Test:** `api-client.test.ts` (uploadStatement) | COVERED
**E2E Test:** GAP (import flow not in E2E)
**Coverage:** PARTIAL

---

#### US-502: Upload a PDF Bank Statement
**As a** Mom, **I can** upload a PDF bank statement and have the app extract transactions from tables, **so that** I can import a full month of spending even from scanned documents.
**Feature IDs:** F-IMP-02
**Priority:** v1
**Backend Test:** GAP (PDF parsing not directly tested)
**Frontend Test:** `api-client.test.ts` (uploadStatement) | COVERED
**E2E Test:** GAP
**Coverage:** GAP

---

#### US-503: Review Parsed Transactions with Auto-Labels
**As a** Armando, **I can** see a preview table of parsed transactions with auto-suggested categories, **so that** I can review and correct labels before importing.
**Feature IDs:** F-IMP-03
**Priority:** v1
**Backend Test:** GAP (auto_label service tested indirectly)
**Frontend Test:** GAP (import page component not tested)
**E2E Test:** GAP
**Coverage:** GAP

---

#### US-504: Confirm and Import Selected Transactions
**As a** Mom, **I can** select which transactions to import and exclude duplicates, **so that** only new transactions enter my records.
**Feature IDs:** F-IMP-04
**Priority:** v1
**Backend Test:** GAP (imports router not tested)
**Frontend Test:** `api-client.test.ts` (confirmImport) | COVERED
**E2E Test:** GAP
**Coverage:** GAP

---

#### US-505: Manage Auto-Label Rules
**As a** Armando, **I can** create, edit, and delete keyword-to-category rules, **so that** future imports automatically categorize transactions I see often.
**Feature IDs:** F-IMP-05
**Priority:** v2
**Backend Test:** GAP (auto_label router not tested)
**Frontend Test:** GAP
**E2E Test:** GAP
**Coverage:** GAP

---

#### US-506: View Import History
**As a** Demo Reviewer, **I can** see a log of past imports showing date, source file, and number of transactions, **so that** I know what has already been imported.
**Feature IDs:** F-IMP-06
**Priority:** v2
**Backend Test:** GAP (imports router history endpoint not tested)
**Frontend Test:** GAP
**E2E Test:** GAP
**Coverage:** GAP

---

### A6: Manage Debt

---

#### US-601: Add a Credit Card
**As a** Armando, **I can** add a credit card with its name, last 4 digits, balance, limit, APR, and minimum payment, **so that** I can track what I owe and plan payoff.
**Feature IDs:** F-DEBT-01
**Priority:** MVP
**Backend Test:** `test_credit_cards.py` | COVERED
**Frontend Test:** `api-client.test.ts` (createCreditCard) | COVERED
**E2E Test:** `finance-workflow.spec.ts` ("add credit card") | COVERED
**Coverage:** COVERED

---

#### US-602: Add a Personal Loan
**As a** Mom, **I can** add a loan with name, lender, type, principal, balance, rate, and minimum payment, **so that** I can see all my debts in one place.
**Feature IDs:** F-DEBT-02
**Priority:** MVP
**Backend Test:** `test_loans.py` | COVERED
**Frontend Test:** `api-client.test.ts` (createLoan) | COVERED
**E2E Test:** `finance-workflow.spec.ts` ("add a loan") | COVERED
**Coverage:** COVERED

---

#### US-603: View Debt Summary Dashboard
**As a** Demo Reviewer, **I can** see a summary of all my debts -- total owed, individual cards and loans with balances and utilization, **so that** I understand my full debt picture at a glance.
**Feature IDs:** F-DEBT-03
**Priority:** MVP
**Backend Test:** GAP (debt_summary endpoint not tested)
**Frontend Test:** `api-client.test.ts` (getDebtSummary) | COVERED
**E2E Test:** `finance-workflow.spec.ts` | PARTIAL (debt page visited, no summary verification)
**Coverage:** GAP

---

#### US-604: Compare Payoff Strategies
**As a** Armando, **I can** enter a monthly debt budget and see a side-by-side comparison of Avalanche, Snowball, Hybrid, and Minimum-only strategies, **so that** I can choose the payoff plan that fits my psychology and math.
**Feature IDs:** F-DEBT-04
**Priority:** v1
**Backend Test:** `test_debt_strategies.py` | COVERED
**Frontend Test:** `debt-math.test.ts` | COVERED
**E2E Test:** GAP (debt strategy page not in E2E)
**Coverage:** PARTIAL

---

#### US-605: Log a Debt Payment
**As a** Mom, **I can** log a payment toward a credit card or loan, **so that** my balances update and I can track progress over time.
**Feature IDs:** F-DEBT-05
**Priority:** v1
**Backend Test:** `test_credit_cards.py` / `test_loans.py` | COVERED
**Frontend Test:** GAP (payment UI not tested)
**E2E Test:** GAP
**Coverage:** PARTIAL

---

#### US-606: Log a Snowflake (Windfall) Payment
**As a** Armando, **I can** log a windfall payment (tax refund, bonus, found money) toward a specific debt, **so that** the app tracks my extra contributions separately.
**Feature IDs:** F-DEBT-06
**Priority:** v1
**Backend Test:** `test_debt_strategies.py` | PARTIAL
**Frontend Test:** GAP
**E2E Test:** GAP
**Coverage:** GAP

---

#### US-607: Delete a Credit Card or Loan
**As a** Armando, **I can** remove a credit card or loan I paid off or added by mistake, **so that** my debt dashboard stays clean.
**Feature IDs:** F-DEBT-07
**Priority:** v1
**Backend Test:** `test_credit_cards.py` / `test_loans.py` | COVERED
**Frontend Test:** `api-client.test.ts` (deleteCreditCard, deleteLoan) | COVERED
**E2E Test:** GAP
**Coverage:** PARTIAL

---

#### US-608: Manage Friend Debt
**As a** Armando, **I can** track friend salary deposits, withdrawals, bank balance, and external accounts to calculate how much I owe, **so that** I always know my true financial position with my friend.
**Feature IDs:** F-DEBT-08
**Priority:** v2
**Backend Test:** `test_friend_debt.py` | COVERED
**Frontend Test:** GAP (friend-debt page not tested)
**E2E Test:** GAP (friend-debt flow not in E2E)
**Coverage:** PARTIAL

---

#### US-609: View Payoff Projection and Amortization
**As a** Mom, **I can** see a month-by-month amortization schedule and projected payoff date for any debt, **so that** I understand exactly when I will be debt-free.
**Feature IDs:** F-DEBT-09
**Priority:** v2
**Backend Test:** `test_debt_calculator.py` | COVERED
**Frontend Test:** `debt-math.test.ts` | COVERED
**E2E Test:** GAP
**Coverage:** PARTIAL

---

### A7: Analyze Spending

---

#### US-701: View Daily/Weekly/Monthly Spending Charts
**As a** Demo Reviewer, **I can** view bar and line charts showing my spending over time at day, week, and month granularity, **so that** I can spot trends and anomalies.
**Feature IDs:** F-ANA-01
**Priority:** MVP
**Backend Test:** GAP (analytics router not tested)
**Frontend Test:** GAP (analytics page not tested)
**E2E Test:** `finance-workflow.spec.ts` ("view analytics page") | COVERED
**Coverage:** GAP

---

#### US-702: View Category Breakdown
**As a** Mom, **I can** see a pie/donut chart showing how my spending breaks down by category, **so that** I know where most of my money goes.
**Feature IDs:** F-ANA-02
**Priority:** MVP
**Backend Test:** GAP (analytics router not tested)
**Frontend Test:** GAP
**E2E Test:** `finance-workflow.spec.ts` ("view analytics page") | PARTIAL
**Coverage:** GAP

---

#### US-703: Check Budget Status per Category
**As a** Armando, **I can** see progress bars showing actual vs. budgeted spending per category, **so that** I know if I am on track or overspending.
**Feature IDs:** F-ANA-03
**Priority:** v1
**Backend Test:** GAP (analytics/budget-status not tested)
**Frontend Test:** GAP
**E2E Test:** GAP (budget status not in E2E)
**Coverage:** GAP

---

#### US-704: View Dashboard Summary
**As a** Mom, **I can** see today's total, this week's total, and this month's total prominently on the home screen, **so that** I have an instant snapshot of my spending.
**Feature IDs:** F-ANA-04
**Priority:** v1
**Backend Test:** GAP (dashboard endpoints not tested)
**Frontend Test:** GAP (dashboard page not tested)
**E2E Test:** `finance-workflow.spec.ts` ("return to dashboard") | PARTIAL (page loads but no value verification)
**Coverage:** GAP

---

#### US-705: Compare Spending Across Periods
**As a** Demo Reviewer, **I can** compare this month's spending to last month's, **so that** I can see whether I am improving or worsening.
**Feature IDs:** F-ANA-05
**Priority:** v1
**Backend Test:** GAP (analytics trends/comparison not tested)
**Frontend Test:** GAP
**E2E Test:** GAP
**Coverage:** GAP

---

#### US-706: Export Tax Summary
**As a** Armando, **I can** download a CSV of all expenses for a tax year, **so that** I can share it with my accountant.
**Feature IDs:** F-ANA-06
**Priority:** v2
**Backend Test:** GAP (tax_export router not tested)
**Frontend Test:** GAP
**E2E Test:** GAP
**Coverage:** GAP

---

#### US-707: Export Tax Receipts as ZIP
**As a** Armando, **I can** download a ZIP file of all receipt images for a tax year, **so that** I have proof of expenses if audited.
**Feature IDs:** F-ANA-07
**Priority:** v2
**Backend Test:** GAP (tax_export router not tested)
**Frontend Test:** GAP
**E2E Test:** GAP
**Coverage:** GAP

---

### A8: Communicate

---

#### US-801: Chat with AI Finance Assistant
**As a** Armando, **I can** ask questions about my spending, budgets, and debts in a chat interface and receive AI-generated analysis based on my actual data, **so that** I get personalized financial advice without leaving the app.
**Feature IDs:** F-COM-01
**Priority:** MVP
**Backend Test:** `test_chat.py` | COVERED
**Frontend Test:** `navigation.test.tsx` (chat route) | PARTIAL
**E2E Test:** GAP (chat flow not in E2E)
**Coverage:** PARTIAL

---

#### US-802: Manage Chat Conversations
**As a** Mom, **I can** create, rename, and delete chat conversations, **so that** I can organize my financial questions by topic.
**Feature IDs:** F-COM-02
**Priority:** v1
**Backend Test:** `test_chat.py` | COVERED
**Frontend Test:** `api-client.test.ts` (createConversation, getConversations, deleteConversation) | COVERED
**E2E Test:** GAP
**Coverage:** PARTIAL

---

#### US-803: Switch AI Model (Haiku / Sonnet)
**As a** Armando, **I can** toggle between Haiku (faster/cheaper) and Sonnet (more detailed) in chat settings, **so that** I can choose speed vs. depth for my queries.
**Feature IDs:** F-COM-03
**Priority:** v1
**Backend Test:** `test_chat.py` | COVERED
**Frontend Test:** GAP (model toggle UI not tested)
**E2E Test:** GAP
**Coverage:** PARTIAL

---

#### US-804: Link Telegram Account
**As a** Armando, **I can** generate a link code in the web app and verify it in the Telegram bot, **so that** my Telegram is connected to my finance account.
**Feature IDs:** F-COM-04
**Priority:** v1
**Backend Test:** `test_telegram.py` | COVERED
**Frontend Test:** `api-client.test.ts` (generateTelegramLink, getTelegramStatus) | COVERED
**E2E Test:** GAP (telegram link flow not in E2E)
**Coverage:** PARTIAL

---

#### US-805: Log Expenses via Telegram Bot
**As a** Armando, **I can** send a text like "coffee 4.50" to the Telegram bot and select a category via inline keyboard, **so that** I can log expenses on the go without opening the web app.
**Feature IDs:** F-COM-05
**Priority:** v1
**Backend Test:** `test_telegram.py` | COVERED
**Frontend Test:** N/A (Telegram-only)
**E2E Test:** GAP
**Coverage:** PARTIAL

---

#### US-806: Admin: Manage Users and Feature Flags
**As a** Armando (admin), **I can** view all users, toggle feature flags (friend debt, hidden categories) per user, and view system stats, **so that** I control who has access to advanced features.
**Feature IDs:** F-COM-06
**Priority:** v1
**Backend Test:** `test_feature_flags.py` | COVERED (flag toggle)
**Frontend Test:** `api-client.test.ts` (getAdminUsers, toggleFeatureFlag) | COVERED
**E2E Test:** GAP (admin panel not in E2E)
**Coverage:** PARTIAL

---

#### US-807: Scan Receipt via Telegram Photo
**As a** Armando, **I can** send a receipt photo to the Telegram bot and have it OCR-extracted and saved as an expense, **so that** I can digitize receipts while away from my computer.
**Feature IDs:** F-COM-07
**Priority:** v2
**Backend Test:** `test_telegram.py` | PARTIAL
**Frontend Test:** N/A
**E2E Test:** GAP
**Coverage:** PARTIAL

---

#### US-808: Query Spending via Telegram
**As a** Armando, **I can** send /today, /month, or /budget to the Telegram bot, **so that** I can check my spending without opening the web app.
**Feature IDs:** F-COM-08
**Priority:** v2
**Backend Test:** `test_telegram.py` | PARTIAL
**Frontend Test:** N/A
**E2E Test:** GAP
**Coverage:** PARTIAL

---

#### US-809: Admin: View System Statistics
**As a** Armando (admin), **I can** view total users, total expenses logged, and storage usage, **so that** I can monitor the system health and growth.
**Feature IDs:** F-COM-09
**Priority:** v2
**Backend Test:** GAP (admin stats endpoint not tested)
**Frontend Test:** `api-client.test.ts` (getAdminStats) | COVERED
**E2E Test:** GAP
**Coverage:** GAP

---

## 6. Coverage Summary

### Coverage by Activity

| Activity | Total Stories | COVERED | PARTIAL | GAP |
|----------|-------------|---------|---------|-----|
| A1: Authenticate | 6 | 1 | 3 | 2 |
| A2: Track Expenses | 8 | 1 | 4 | 3 |
| A3: Manage Categories | 6 | 0 | 4 | 2 |
| A4: Scan Receipts | 6 | 0 | 1 | 5 |
| A5: Import Statements | 6 | 0 | 1 | 5 |
| A6: Manage Debt | 9 | 2 | 5 | 2 |
| A7: Analyze Spending | 7 | 0 | 0 | 7 |
| A8: Communicate | 9 | 0 | 7 | 2 |
| **Totals** | **57** | **4 (7%)** | **25 (44%)** | **28 (49%)** |

### Coverage by Priority Tier

| Tier | Total Stories | COVERED | PARTIAL | GAP |
|------|-------------|---------|---------|-----|
| MVP | 16 | 4 | 7 | 5 |
| v1 | 24 | 0 | 14 | 10 |
| v2 | 17 | 0 | 4 | 13 |

### Coverage by Test Layer

| Layer | Files Exist | Key Gaps |
|-------|------------|----------|
| **Backend (pytest)** | `test_auth`, `test_expenses`, `test_categories`, `test_credit_cards`, `test_loans`, `test_debt_calculator`, `test_debt_strategies`, `test_csv_parser`, `test_chat`, `test_feature_flags`, `test_friend_debt`, `test_pending_receipts`, `test_telegram` (13 files) | `analytics`, `admin`, `tax_export`, `auto_label`, `imports` (router), `receipt_scan`, `debt_summary`, `data_isolation` |
| **Frontend (vitest)** | `api-client.test.ts`, `debt-math.test.ts`, `format-helpers.test.ts`, `image-compress.test.ts`, `navigation.test.tsx` (5 files) | `AuthContext`, `FeatureFlagsContext`, `QuickAddModal`, `ReceiptScanner`, all 15 page components |
| **E2E (Playwright)** | `finance-workflow.spec.ts` -- covers registration, categories, expenses, debt add, analytics visit, scan visit, receipts visit, dashboard (1 file, 10 tests) | login, chat, import, settings, admin, friend-debt, hidden categories, telegram link, debt strategy, budget status |

### Highest-Impact Test Gaps

These are the stories most in need of test coverage based on priority and user impact:

| Story | Priority | Gap Description |
|-------|----------|-----------------|
| US-701 | MVP | Analytics daily/category endpoints have zero backend tests |
| US-702 | MVP | Category breakdown chart: no backend, no frontend, E2E only visits page |
| US-401 | MVP | Receipt camera capture: no component test for ReceiptScanner |
| US-402 | MVP | Receipt OCR pipeline: no backend test for scan service |
| US-201 | MVP | Quick-add modal: no frontend unit test for the primary input method |
| US-801 | MVP | AI Chat: no E2E test for the streaming conversation flow |
| US-603 | MVP | Debt summary: no backend test for the `/debt/summary` endpoint |
| US-703 | v1 | Budget status: untested across all layers |
| US-503 | v1 | Import review with auto-labels: untested across all layers |
| US-806 | v1 | Admin panel: feature flag toggle has no E2E coverage |

---

## Appendix: Test File Index

### Backend Tests (`backend/tests/`)

| File | Stories Covered |
|------|----------------|
| `test_auth.py` | US-101, US-102, US-103, US-104 |
| `test_expenses.py` | US-201, US-202, US-203, US-204, US-205 |
| `test_categories.py` | US-301, US-302, US-303, US-304, US-305 |
| `test_credit_cards.py` | US-601, US-605, US-607 |
| `test_loans.py` | US-602, US-605, US-607 |
| `test_debt_calculator.py` | US-609 |
| `test_debt_strategies.py` | US-604, US-606 |
| `test_csv_parser.py` | US-501 |
| `test_chat.py` | US-801, US-802, US-803 |
| `test_feature_flags.py` | US-206, US-306, US-806 |
| `test_friend_debt.py` | US-608 |
| `test_pending_receipts.py` | US-404 |
| `test_telegram.py` | US-804, US-805, US-807, US-808 |

### Frontend Tests (`frontend/__tests__/`)

| File | Stories Covered |
|------|----------------|
| `api-client.test.ts` | US-101, US-102, US-103, US-104, US-202, US-204, US-302, US-404, US-501, US-504, US-601, US-602, US-607, US-802, US-804, US-806, US-809 |
| `debt-math.test.ts` | US-604, US-609 |
| `format-helpers.test.ts` | (utility -- supports all display stories) |
| `image-compress.test.ts` | US-401 (preprocessing) |
| `navigation.test.tsx` | US-801 (route existence) |

### E2E Tests (`e2e/finance-workflow.spec.ts`)

| Test Name | Stories Covered |
|-----------|----------------|
| "register a new account" | US-101 |
| "create expense categories via API" | US-301 |
| "add expenses via API" | US-201, US-202 |
| "view expenses list" | US-203 |
| "navigate to debt page and add credit card" | US-601 |
| "add a loan" | US-602 |
| "view analytics page" | US-701, US-702 |
| "visit scan page" | US-401 |
| "visit receipts page" | US-404, US-405 |
| "return to dashboard" | US-704 |
