# Product Requirements Document -- Finance Tracker

**Product:** Finance Tracker -- Expense Tracking with Receipt Scanner & Debt Management
**Domain:** finance.armandointeligencia.com
**Version:** 4.0.0
**Last Updated:** 2026-04-04
**Status:** Living Document

---

## Table of Contents

1. [Product Vision & Objectives](#1-product-vision--objectives)
2. [Target Users & Personas](#2-target-users--personas)
3. [Functional Requirements](#3-functional-requirements)
4. [Non-Functional Requirements](#4-non-functional-requirements)
5. [Demo Environment](#5-demo-environment)
6. [Success Metrics](#6-success-metrics)
7. [Test Coverage Cross-Reference](#7-test-coverage-cross-reference)

---

## 1. Product Vision & Objectives

### Mission

**Make expense logging take less than 10 seconds.**

Finance Tracker is a mobile-first responsive web application that replaces the friction of traditional expense tracking with five ultra-fast data input methods: manual quick-add (2 taps), receipt photo scanning with ML extraction, bank/CC statement import (PDF and CSV), AI-powered chat for natural-language queries, and a Telegram bot for on-the-go logging. It also provides a full-featured debt elimination engine covering credit cards, personal loans, and payoff strategy comparison.

This is a website, not a native app. No App Store listing. No Apple Developer License. It works in iPhone Safari, Android Chrome, and desktop browsers. Users can optionally "Add to Home Screen" for a native-like shortcut.

### Objectives

| ID | Objective | Description |
|----|-----------|-------------|
| O1 | Ultra-Fast Capture | A user can log an expense in under 10 seconds via the quick-add flow (amount + category, two taps, done). Receipt scanning completes OCR in under 15 seconds. |
| O2 | Intelligent Automation | Auto-label imported transactions using keyword rules. Learn from user corrections. Dual-mode OCR (Claude Vision primary, Tesseract fallback) with confidence scoring. |
| O3 | Debt Elimination | Track credit cards and loans with real balances. Compare avalanche, snowball, hybrid, and minimum-only payoff strategies. Show months-to-freedom and total interest saved. |
| O4 | AI Insight | Claude-powered finance chat answers spending questions, gives budget advice, and coaches debt payoff -- all grounded in the user's real financial data via intent classification and context injection. |
| O5 | Multi-Channel Access | Web app (primary), Telegram bot (on-the-go text and photo logging), future Slack/WhatsApp. Data flows into the same backend regardless of channel. |
| O6 | Privacy & Multi-Tenancy | Complete data isolation between users. Hidden categories for discreet tracking. Feature flags for per-user capability gating. Admin panel for superuser oversight. Soft deletes preserve audit trails. |

---

## 2. Target Users & Personas

### Persona 1: Armando (Superuser / Admin)

| Attribute | Detail |
|-----------|--------|
| Role | System administrator and primary power user |
| Access Level | `is_superuser = true` -- full admin panel access |
| Feature Flags | All flags enabled (friend_debt_calculator, hidden_categories) |
| Primary Devices | iPhone Safari (70%), MacBook Chrome (30%) |
| Languages | English (primary), Spanish (secondary) |
| Key Workflows | Quick-add expenses daily, scan receipts at point of sale, import bank CSV monthly, review debt strategy weekly, chat with AI for budget planning, manage other users via admin panel |
| Pain Points | Wants zero friction for daily logging; needs debt visibility across 3+ cards and 2 loans; wants discreet tracking of certain categories |

### Persona 2: Mom (Standard User / Mobile-Only)

| Attribute | Detail |
|-----------|--------|
| Role | Standard user, non-technical |
| Access Level | `is_superuser = false` |
| Feature Flags | hidden_categories (enabled), friend_debt_calculator (disabled) |
| Primary Devices | Android Chrome (95%), occasional tablet |
| Languages | Spanish (primary), English (secondary) |
| Key Workflows | Quick-add grocery and bill expenses, review monthly spending totals, photo-scan receipts for tax records |
| Pain Points | Needs simple UI with large tap targets; Spanish labels; minimal learning curve |

### Persona 3: Demo Reviewer (Evaluation Account)

| Attribute | Detail |
|-----------|--------|
| Role | Pre-seeded demo account for showcasing the product |
| Access Level | Standard user with pre-populated data |
| Feature Flags | All flags enabled for demo purposes |
| Primary Devices | Any browser |
| Key Workflows | Browse pre-seeded expenses, categories, debt items, and analytics to evaluate the product without creating data |
| Pain Points | Must see a realistic, populated dashboard immediately after login |

### Persona 4: Future User (Onboarding Template)

| Attribute | Detail |
|-----------|--------|
| Role | New user who registers via the public registration form |
| Access Level | `is_superuser = false` |
| Feature Flags | None enabled by default; admin must enable per-user |
| Primary Devices | Unknown |
| Key Workflows | Register, receive 9 default categories, start logging expenses, optionally link Telegram |
| Pain Points | Must have a productive first session within 60 seconds of registration |

---

## 3. Functional Requirements

### 3.1 Authentication (F-AUTH)

#### F-AUTH-01: User Registration

| Field | Value |
|-------|-------|
| **Description** | New users register with email, password, and optional display name. The system creates the user account and seeds 9 default expense categories. Returns JWT access + refresh token pair. |
| **Endpoint** | `POST /api/v1/auth/register` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN a visitor with a valid email and password
WHEN they submit the registration form
THEN the system creates a new user record
  AND seeds 9 default categories (Food & Dining, Transportation, Shopping, Entertainment, Bills & Utilities, Health, Education, Personal, Other)
  AND returns an access_token (JWT, 15-min expiry) and refresh_token (7-day expiry)
  AND the response status is 201 Created

GIVEN a visitor with an email that already exists
WHEN they submit the registration form
THEN the system returns 409 Conflict with detail "A user with this email already exists"
```

#### F-AUTH-02: User Login

| Field | Value |
|-------|-------|
| **Description** | Authenticate with email and password. Returns JWT access + refresh token pair. |
| **Endpoint** | `POST /api/v1/auth/login` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN a registered user with valid credentials
WHEN they submit the login form
THEN the system returns an access_token and refresh_token
  AND the response status is 200 OK

GIVEN a visitor with an invalid password
WHEN they submit the login form
THEN the system returns 401 Unauthorized with detail "Invalid email or password"
```

#### F-AUTH-03: Token Refresh

| Field | Value |
|-------|-------|
| **Description** | Exchange a valid refresh token for a new access + refresh token pair. Old tokens are revoked. |
| **Endpoint** | `POST /api/v1/auth/refresh` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN a user with a valid refresh_token
WHEN they call the refresh endpoint
THEN the system revokes the old token pair
  AND returns a new access_token and refresh_token
  AND the response status is 200 OK

GIVEN a user with an expired or invalid refresh_token
WHEN they call the refresh endpoint
THEN the system returns 401 Unauthorized
```

#### F-AUTH-04: Logout

| Field | Value |
|-------|-------|
| **Description** | Revoke all refresh tokens for the authenticated user, forcing re-login. |
| **Endpoint** | `POST /api/v1/auth/logout` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user
WHEN they call the logout endpoint
THEN all refresh tokens for that user are revoked
  AND the response status is 204 No Content
```

#### F-AUTH-05: Profile Management

| Field | Value |
|-------|-------|
| **Description** | Retrieve and update the authenticated user's profile (display_name, currency, timezone). |
| **Endpoints** | `GET /api/v1/auth/me`, `PATCH /api/v1/auth/me` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user
WHEN they call GET /api/v1/auth/me
THEN the system returns the user's id, email, display_name, currency, timezone, is_superuser, and created_at

GIVEN an authenticated user
WHEN they call PATCH /api/v1/auth/me with {"display_name": "Armando G"}
THEN the user's display_name is updated to "Armando G"
  AND the updated user profile is returned

GIVEN an authenticated user
WHEN they call PATCH /api/v1/auth/me with an empty body
THEN the system returns 422 Unprocessable Entity
```

---

### 3.2 Expenses (F-EXP)

#### F-EXP-01: List Expenses with Filters

| Field | Value |
|-------|-------|
| **Description** | Paginated list of user's expenses with optional filters: date range, category, search text, amount range. Hidden-category expenses are excluded by default. |
| **Endpoint** | `GET /api/v1/expenses/` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with 25 expenses
WHEN they call GET /api/v1/expenses/?page=1&per_page=20
THEN the system returns the first 20 expenses ordered by date descending
  AND the response includes total, page, and per_page metadata
  AND expenses in hidden categories are NOT included

GIVEN an authenticated user
WHEN they call GET /api/v1/expenses/?start_date=2026-03-01&end_date=2026-03-31&category_id={id}
THEN only expenses matching all filter criteria are returned
```

#### F-EXP-02: Create Expense (Full)

| Field | Value |
|-------|-------|
| **Description** | Create a new expense with all fields: amount, category, description, merchant, date, time, tax, notes, tags, recurring flag, tax-deductible flag. |
| **Endpoint** | `POST /api/v1/expenses/` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with a valid category
WHEN they submit a new expense with amount=25.50, category_id={id}, description="Lunch"
THEN the system creates the expense with user_id set to the authenticated user
  AND expense_date defaults to today if not provided
  AND the response status is 201 Created

GIVEN an authenticated user
WHEN they submit an expense with a category_id belonging to another user
THEN the system returns 404 Not Found
```

#### F-EXP-03: Quick-Add Expense

| Field | Value |
|-------|-------|
| **Description** | Minimal expense creation: just amount and category. Date defaults to today, currency defaults to user's setting. Optimized for the <10 second workflow. |
| **Endpoint** | `POST /api/v1/expenses/quick` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with category "Food & Dining"
WHEN they submit a quick-add with amount=12.99 and category_id={food_id}
THEN the system creates an expense dated today with the user's default currency
  AND the response status is 201 Created
  AND the total interaction requires at most 2 inputs (amount + category tap)
```

#### F-EXP-04: Get Single Expense

| Field | Value |
|-------|-------|
| **Description** | Retrieve a single expense by ID. Only the owning user can access it. |
| **Endpoint** | `GET /api/v1/expenses/{expense_id}` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user who owns expense {id}
WHEN they call GET /api/v1/expenses/{id}
THEN the full expense record is returned

GIVEN an authenticated user
WHEN they request an expense belonging to another user
THEN the system returns 404 Not Found
```

#### F-EXP-05: Update Expense

| Field | Value |
|-------|-------|
| **Description** | Partial update of an expense's fields. Validates category ownership if category_id is changed. |
| **Endpoint** | `PATCH /api/v1/expenses/{expense_id}` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user who owns expense {id}
WHEN they call PATCH with {"amount": 30.00, "description": "Updated lunch"}
THEN only the specified fields are updated
  AND updated_at is refreshed

GIVEN an authenticated user
WHEN they call PATCH with an empty body
THEN the system returns 422 Unprocessable Entity
```

#### F-EXP-06: Delete Expense

| Field | Value |
|-------|-------|
| **Description** | Permanently delete an expense. Only the owning user can delete. |
| **Endpoint** | `DELETE /api/v1/expenses/{expense_id}` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user who owns expense {id}
WHEN they call DELETE /api/v1/expenses/{id}
THEN the expense is removed from the database
  AND the response status is 204 No Content

GIVEN an authenticated user
WHEN they try to delete an expense belonging to another user
THEN the system returns 404 Not Found
```

#### F-EXP-07: List Hidden Expenses

| Field | Value |
|-------|-------|
| **Description** | Paginated list of expenses that belong to hidden categories only. Provides a private view separated from the main expense list. |
| **Endpoint** | `GET /api/v1/expenses/hidden` |
| **Priority** | P2 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with expenses in both normal and hidden categories
WHEN they call GET /api/v1/expenses/hidden
THEN only expenses linked to categories where is_hidden=true are returned
  AND the response is paginated with total, page, per_page
```

---

### 3.3 Categories (F-CAT)

#### F-CAT-01: List Categories

| Field | Value |
|-------|-------|
| **Description** | List all categories for the authenticated user, sorted by sort_order. By default only active categories are returned. |
| **Endpoint** | `GET /api/v1/categories/` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with 9 default categories
WHEN they call GET /api/v1/categories/
THEN all 9 active categories are returned sorted by sort_order ascending

GIVEN an authenticated user
WHEN they call GET /api/v1/categories/?include_inactive=true
THEN both active and soft-deleted categories are returned
```

#### F-CAT-02: Create Category

| Field | Value |
|-------|-------|
| **Description** | Create a new category with name, icon, color, optional hidden flag, and optional monthly budget. Duplicate names within the same user are rejected. |
| **Endpoint** | `POST /api/v1/categories/` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user
WHEN they create a category with name="Groceries", icon="shopping-cart", color="#22C55E"
THEN the category is created with the next available sort_order
  AND the response status is 201 Created

GIVEN an authenticated user who already has a "Groceries" category
WHEN they try to create another category named "Groceries"
THEN the system returns 409 Conflict
```

#### F-CAT-03: Update Category

| Field | Value |
|-------|-------|
| **Description** | Partial update of a category's fields (name, icon, color, is_hidden, monthly_budget). Validates name uniqueness on rename. |
| **Endpoint** | `PATCH /api/v1/categories/{category_id}` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user who owns category {id}
WHEN they call PATCH with {"monthly_budget": 500.00}
THEN the category's monthly_budget is updated to 500.00

GIVEN an authenticated user
WHEN they rename a category to a name that already exists
THEN the system returns 409 Conflict
```

#### F-CAT-04: Delete Category (Soft)

| Field | Value |
|-------|-------|
| **Description** | Soft-delete a category by setting is_active=false. Existing expenses retain their category_id reference. |
| **Endpoint** | `DELETE /api/v1/categories/{category_id}` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user who owns category {id}
WHEN they call DELETE /api/v1/categories/{id}
THEN the category's is_active flag is set to false
  AND the response status is 204 No Content
  AND existing expenses with that category_id are NOT orphaned
```

#### F-CAT-05: Reorder Categories

| Field | Value |
|-------|-------|
| **Description** | Bulk update sort_order for all categories based on a provided ordered list of UUIDs. Supports drag-and-drop reorganization on the frontend. |
| **Endpoint** | `PUT /api/v1/categories/reorder` |
| **Priority** | P2 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with categories [A, B, C]
WHEN they call PUT /api/v1/categories/reorder with category_ids=[C, A, B]
THEN C.sort_order=0, A.sort_order=1, B.sort_order=2
  AND the reordered categories are returned in the new order

GIVEN an authenticated user
WHEN they provide a category_id that does not belong to them
THEN the system returns 404 Not Found
```

---

### 3.4 Receipts (F-REC)

#### F-REC-01: Scan Receipt (OCR)

| Field | Value |
|-------|-------|
| **Description** | Upload a receipt image, preprocess it (EXIF correction, resize, thumbnail), and run OCR (Claude Vision primary, Tesseract fallback). Returns extracted data for user review. |
| **Endpoint** | `POST /api/v1/receipts/scan` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with a JPEG receipt image
WHEN they upload it to the scan endpoint
THEN the system preprocesses the image (resize, thumbnail, base64)
  AND runs OCR to extract merchant_name, date, total, tax, items
  AND returns a temp_id, image_path, ocr_data, and needs_review flag
  AND the response includes ocr_method ("claude" or "tesseract")

GIVEN an authenticated user uploading a non-image file (e.g., .txt)
WHEN they call the scan endpoint
THEN the system returns 415 Unsupported Media Type

GIVEN an authenticated user uploading an empty file
WHEN they call the scan endpoint
THEN the system returns 422 Unprocessable Entity
```

#### F-REC-02: Confirm Scanned Receipt

| Field | Value |
|-------|-------|
| **Description** | After OCR review, the user confirms the extracted data (with any corrections). Creates an Expense record and a ReceiptArchive record for tax purposes. |
| **Endpoint** | `POST /api/v1/receipts/confirm` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user who has scanned a receipt and corrected the OCR output
WHEN they submit the confirm endpoint with amount, merchant_name, category_id, image_path
THEN the system creates an Expense record linked to the user
  AND creates a ReceiptArchive record with tax_year and tax_month
  AND returns the expense_id and archive_id
  AND the response status is 201 Created
```

#### F-REC-03: Browse Archived Receipts

| Field | Value |
|-------|-------|
| **Description** | Paginated listing of archived receipt images with optional year/month filtering. Used for tax season browsing. |
| **Endpoint** | `GET /api/v1/receipts/archive` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with 15 archived receipts
WHEN they call GET /api/v1/receipts/archive?year=2026&month=3
THEN only receipts from March 2026 are returned
  AND each item includes id, expense_id, image_path, thumbnail_path, tax_year, tax_month
```

#### F-REC-04: Serve Receipt Image

| Field | Value |
|-------|-------|
| **Description** | Serve a receipt image file by archive ID. Only the owning user can access it. Supports full-size and thumbnail via query parameter. |
| **Endpoint** | `GET /api/v1/receipts/{receipt_id}/image` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user who owns receipt archive {id}
WHEN they call GET /api/v1/receipts/{id}/image
THEN the full-size receipt image is returned as a FileResponse

GIVEN an authenticated user who owns receipt archive {id}
WHEN they call GET /api/v1/receipts/{id}/image?thumbnail=true
THEN the thumbnail image is returned

GIVEN an authenticated user
WHEN they request a receipt belonging to another user
THEN the system returns 404 Not Found
```

#### F-REC-05: Queue Receipt for Later

| Field | Value |
|-------|-------|
| **Description** | Save a receipt image to the pending queue for later OCR analysis. Image is processed and stored immediately but OCR is deferred. |
| **Endpoint** | `POST /api/v1/receipts/queue` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with a receipt image
WHEN they upload it to the queue endpoint
THEN the image is processed and stored on disk
  AND a PendingReceipt record is created with status="pending"
  AND the response includes id, status, thumbnail_path, and created_at
  AND the response status is 201 Created
```

#### F-REC-06: List Pending Receipts

| Field | Value |
|-------|-------|
| **Description** | List all pending and analyzed receipts for the current user, newest first. |
| **Endpoint** | `GET /api/v1/receipts/pending` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with 3 pending receipts
WHEN they call GET /api/v1/receipts/pending
THEN all 3 pending receipts are returned sorted by created_at descending
  AND each item includes id, status, image_path, ocr_data, and timestamps
```

#### F-REC-07: Delete Pending Receipt

| Field | Value |
|-------|-------|
| **Description** | Remove a pending receipt from the queue. Also deletes the associated image files from disk. |
| **Endpoint** | `DELETE /api/v1/receipts/pending/{pending_id}` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user who owns pending receipt {id}
WHEN they call DELETE /api/v1/receipts/pending/{id}
THEN the PendingReceipt record is deleted
  AND the image and thumbnail files are removed from disk
  AND the response status is 204 No Content
```

---

### 3.5 Imports (F-IMP)

#### F-IMP-01: Upload and Parse Statement

| Field | Value |
|-------|-------|
| **Description** | Upload a bank statement (CSV or PDF), parse transactions, auto-label using the user's rules, and detect potential duplicates. Returns a preview for user review. |
| **Endpoint** | `POST /api/v1/import/upload` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with a Chase CSV bank statement
WHEN they upload it to the import endpoint
THEN the system auto-detects the bank format
  AND parses all transactions with date, description, and amount
  AND applies auto-label rules to suggest categories
  AND flags potential duplicates (same date + amount + similar description)
  AND returns an ImportPreview with total_parsed and bank_detected

GIVEN an authenticated user uploading an unsupported file type
WHEN they call the upload endpoint
THEN the system returns 415 Unsupported Media Type
```

#### F-IMP-02: Confirm Import

| Field | Value |
|-------|-------|
| **Description** | After reviewing the parsed preview, confirm and import selected transactions. Creates Expense records and an ImportHistory record. |
| **Endpoint** | `POST /api/v1/import/confirm` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with a previewed set of 50 parsed transactions
WHEN they confirm import with 45 transactions selected (5 excluded as duplicates)
THEN 45 Expense records are created
  AND an ImportHistory record is created with transactions_parsed=50, transactions_imported=45
  AND the response includes imported count and import_id

GIVEN an authenticated user
WHEN they confirm with zero transactions selected
THEN the system returns 422 Unprocessable Entity
```

#### F-IMP-03: Import History

| Field | Value |
|-------|-------|
| **Description** | List past import operations for the current user, most recent first. |
| **Endpoint** | `GET /api/v1/import/history` |
| **Priority** | P2 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user who has imported 3 statements
WHEN they call GET /api/v1/import/history
THEN all 3 import records are returned sorted by import_date descending
  AND each includes source_type, bank_preset, filename, parsed/imported counts
```

#### F-IMP-04: Bank Templates

| Field | Value |
|-------|-------|
| **Description** | Return available bank presets for CSV import so the frontend can display supported banks. |
| **Endpoint** | `GET /api/v1/import/templates` |
| **Priority** | P2 |
| **Acceptance Criteria** | |

```gherkin
GIVEN any authenticated user
WHEN they call GET /api/v1/import/templates
THEN the system returns a list of bank presets (Chase, BofA, Wells Fargo, etc.)
  AND each preset includes column mapping details (date, description, amount columns)
  AND "Generic / Other" is always included as the last option
```

#### F-IMP-05: PDF Statement Parsing

| Field | Value |
|-------|-------|
| **Description** | Parse PDF bank statements using pdfplumber table extraction. Falls back to Claude Vision for scanned/image-based PDFs. |
| **Endpoint** | (Part of `POST /api/v1/import/upload` when file is PDF) |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with a text-based PDF bank statement
WHEN they upload it to the import endpoint
THEN pdfplumber extracts tables from each page
  AND transactions are parsed from the table rows
  AND results are returned in the same ImportPreview format as CSV

GIVEN an authenticated user with a scanned (image-based) PDF
WHEN pdfplumber finds no tables
THEN the system falls back to Claude Vision API for OCR extraction
```

#### F-IMP-06: Duplicate Detection

| Field | Value |
|-------|-------|
| **Description** | During import, flag transactions that likely already exist in the database. Uses date + amount matching with fuzzy description comparison (rapidfuzz). |
| **Endpoint** | (Part of `POST /api/v1/import/upload` processing) |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user who already has an expense for $25.50 on 2026-03-15 at "Chipotle"
WHEN they import a statement containing a transaction for $25.50 on 2026-03-15 described "CHIPOTLE GRILL #1234"
THEN the transaction is flagged as possible_duplicate=true
  AND duplicate_confidence is >= 0.85
  AND include defaults to false (auto-excluded)
```

---

### 3.6 Credit Cards (F-CC)

#### F-CC-01: CRUD Credit Cards

| Field | Value |
|-------|-------|
| **Description** | Create, read, update, and soft-delete credit cards. Each card tracks: name, last four digits, balance, credit limit, APR, minimum payment, statement day, and due day. Utilization percentage is computed on read. |
| **Endpoints** | `GET /api/v1/credit-cards/`, `POST /api/v1/credit-cards/`, `GET /api/v1/credit-cards/{id}`, `PATCH /api/v1/credit-cards/{id}`, `DELETE /api/v1/credit-cards/{id}` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user
WHEN they create a credit card with balance=2500, credit_limit=5000, apr=0.2499
THEN the card is created and utilization is computed as 50.00%
  AND the response status is 201 Created

GIVEN an authenticated user
WHEN they delete a credit card
THEN is_active is set to false (soft delete)
  AND the card no longer appears in the list

GIVEN an authenticated user with a card that has no credit_limit
WHEN they read the card
THEN utilization is returned as null
```

#### F-CC-02: Log Credit Card Payment

| Field | Value |
|-------|-------|
| **Description** | Log a payment toward a credit card. Reduces the card's balance and creates a DebtPayment record and DebtSnapshot for history tracking. |
| **Endpoint** | `POST /api/v1/credit-cards/{card_id}/payment` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with a credit card balance of $2,500
WHEN they log a payment of $500
THEN the card's current_balance is reduced to $2,000
  AND a DebtPayment record is created with debt_type="credit_card"
  AND a DebtSnapshot is recorded for the new balance
  AND the response includes payment_id, amount, and new_balance
```

#### F-CC-03: Payoff Projection

| Field | Value |
|-------|-------|
| **Description** | Calculate how long it will take to pay off a credit card at a given monthly payment. Returns months to payoff and total interest paid. |
| **Endpoint** | `GET /api/v1/credit-cards/{card_id}/payoff` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with a card: balance=$2,500, APR=24.99%
WHEN they request a payoff projection with monthly_payment=$200
THEN the system calculates months_to_payoff and total_interest_paid
  AND returns a PayoffProjection with payoff_months, total_interest, and payoff_date

GIVEN a card with no minimum_payment set and no monthly_payment parameter
WHEN they request a payoff projection
THEN the system returns 422 Unprocessable Entity
```

---

### 3.7 Loans (F-LN)

#### F-LN-01: CRUD Loans

| Field | Value |
|-------|-------|
| **Description** | Create, read, update, and soft-delete personal loans. Each loan tracks: name, lender, type (car/student/personal/mortgage/other), original principal, current balance, interest rate, minimum payment, due day, start date. Progress percentage is computed on read. |
| **Endpoints** | `GET /api/v1/loans/`, `POST /api/v1/loans/`, `GET /api/v1/loans/{id}`, `PATCH /api/v1/loans/{id}`, `DELETE /api/v1/loans/{id}` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user
WHEN they create a loan with original_principal=15000, current_balance=12000
THEN progress_percent is computed as 20.00%
  AND the response status is 201 Created

GIVEN an authenticated user
WHEN they delete a loan
THEN is_active is set to false (soft delete)
```

#### F-LN-02: Log Loan Payment with Interest Split

| Field | Value |
|-------|-------|
| **Description** | Log a payment toward a loan. The system automatically splits the payment into principal and interest portions based on the loan's current rate. Also supports snowflake (windfall) payments that go entirely to principal. |
| **Endpoints** | `POST /api/v1/loans/{loan_id}/payment`, `POST /api/v1/loans/{loan_id}/snowflake` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN a loan with balance=$12,000, interest_rate=0.06 (6% annual)
WHEN the user logs a payment of $500
THEN interest_portion = $12,000 * 0.005 = $60.00
  AND principal_portion = $500 - $60 = $440.00
  AND new_balance = $12,000 - $440 = $11,560.00

GIVEN the same loan
WHEN the user logs a snowflake payment of $1,000
THEN the entire $1,000 is applied to principal
  AND interest_portion = $0.00
  AND a DebtSnapshot is recorded
```

#### F-LN-03: Amortization Schedule

| Field | Value |
|-------|-------|
| **Description** | Generate a full month-by-month amortization schedule for the remaining loan balance. Each row shows payment, principal, interest, and remaining balance. |
| **Endpoint** | `GET /api/v1/loans/{loan_id}/amortization` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN a loan with balance=$12,000, rate=6%, minimum_payment=$500
WHEN the user requests the amortization schedule
THEN the system returns a schedule array where each entry has month, payment, principal, interest, remaining
  AND the final entry has remaining near $0.00
  AND total_months matches the schedule length
```

---

### 3.8 Debt Strategy (F-DEBT)

#### F-DEBT-01: Debt Summary

| Field | Value |
|-------|-------|
| **Description** | Total debt overview aggregating all active credit cards and loans. Shows balances, minimums, utilization, and progress broken down by debt type. |
| **Endpoint** | `GET /api/v1/debt/summary` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with 2 credit cards and 1 loan
WHEN they call GET /api/v1/debt/summary
THEN the response includes total_balance, total_minimum_payment
  AND credit_cards section with count, total_balance, overall_utilization, average_apr
  AND loans section with count, total_balance, overall_progress_percent, average_rate
```

#### F-DEBT-02: Strategy Comparison

| Field | Value |
|-------|-------|
| **Description** | Compare payoff strategies (avalanche, snowball, hybrid, minimum-only) given a monthly debt-payment budget. Simulates each strategy and returns months-to-freedom and total interest paid. |
| **Endpoint** | `GET /api/v1/debt/strategies?monthly_budget={amount}` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with 3 debts and a monthly_budget of $1,000
WHEN they call GET /api/v1/debt/strategies?monthly_budget=1000
THEN the system simulates avalanche, snowball, hybrid, and minimum_only strategies
  AND returns for each: total_months, total_interest, monthly_payment
  AND includes a recommendation field identifying the best strategy
  AND interest_saved shows savings compared to minimum-only

GIVEN a monthly_budget less than total minimum payments
WHEN the user requests strategies
THEN the system returns 422 with a shortfall message
```

#### F-DEBT-03: Debt History

| Field | Value |
|-------|-------|
| **Description** | Time-series of debt balance snapshots for charting debt paydown progress. Grouped by date with credit card and loan subtotals. |
| **Endpoint** | `GET /api/v1/debt/history?months={N}` |
| **Priority** | P2 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with debt snapshots over the past 6 months
WHEN they call GET /api/v1/debt/history?months=6
THEN the system returns a sorted time-series of balance entries
  AND each entry includes date, credit_card_total, loan_total, total, and individual items
```

---

### 3.9 Friend Debt (F-FD)

> Feature-gated: Requires `friend_debt_calculator` flag enabled by admin.

#### F-FD-01: Friend Debt Summary

| Field | Value |
|-------|-------|
| **Description** | Calculate the current friend debt position: accumulated deposits minus withdrawals, compared against bank balance and external safety-net accounts. Returns status: "clear", "covered", or "shortfall". |
| **Endpoint** | `GET /api/v1/friend-debt/summary?bank_balance={amount}` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN a user with friend_debt_calculator enabled, $5,000 in deposits, $1,000 in withdrawals, bank_balance=$3,000
WHEN they call GET /api/v1/friend-debt/summary?bank_balance=3000
THEN friend_accumulated = $4,000
  AND amount_owed = $4,000 - $3,000 = $1,000
  AND the system checks external accounts for the safety net
  AND status is "covered" if external accounts >= $1,000, else "shortfall"

GIVEN a user WITHOUT friend_debt_calculator enabled
WHEN they call any /api/v1/friend-debt/ endpoint
THEN the system returns 403 Forbidden with "Feature not enabled for your account"
```

#### F-FD-02: Deposit/Withdrawal CRUD

| Field | Value |
|-------|-------|
| **Description** | Log friend deposits and withdrawals. List all entries with optional friend_name filter. Delete individual entries. |
| **Endpoints** | `POST /api/v1/friend-debt/deposits`, `GET /api/v1/friend-debt/deposits`, `DELETE /api/v1/friend-debt/deposits/{id}` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN a user with friend_debt_calculator enabled
WHEN they log a deposit with amount=2500, friend_name="Maria", transaction_type="deposit"
THEN a FriendDeposit record is created
  AND the response status is 201 Created

GIVEN a user with friend_debt_calculator enabled
WHEN they call GET /api/v1/friend-debt/deposits?friend_name=Maria
THEN only deposits for "Maria" are returned
```

#### F-FD-03: External Account CRUD

| Field | Value |
|-------|-------|
| **Description** | Manage external safety-net accounts (savings, Venmo, etc.) with name and balance. Used in the friend debt calculation to determine the true shortfall. |
| **Endpoints** | `GET /api/v1/friend-debt/external-accounts`, `POST /api/v1/friend-debt/external-accounts`, `PATCH /api/v1/friend-debt/external-accounts/{id}`, `DELETE /api/v1/friend-debt/external-accounts/{id}` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN a user with friend_debt_calculator enabled
WHEN they add an external account with name="Savings", balance=5000
THEN an ExternalAccount record is created

GIVEN a user with friend_debt_calculator enabled
WHEN they update the balance of an existing external account
THEN the balance is updated and the friend debt summary reflects the change
```

---

### 3.10 Analytics (F-ANA)

#### F-ANA-01: Daily Spending

| Field | Value |
|-------|-------|
| **Description** | Daily spending totals within a date range, with optional category filter. Hidden-category expenses are excluded. |
| **Endpoint** | `GET /api/v1/analytics/daily?start_date={}&end_date={}` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with expenses on 5 days in March
WHEN they call GET /api/v1/analytics/daily?start_date=2026-03-01&end_date=2026-03-31
THEN the response includes 5 data points, each with date, total, and count
  AND data is sorted chronologically
  AND expenses in hidden categories are excluded

GIVEN end_date < start_date
WHEN the user calls the daily endpoint
THEN the system returns 422 Unprocessable Entity
```

#### F-ANA-02: Weekly Spending

| Field | Value |
|-------|-------|
| **Description** | Weekly spending aggregation within a date range, grouped by ISO week number. |
| **Endpoint** | `GET /api/v1/analytics/weekly?start_date={}&end_date={}` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with expenses spanning 4 weeks
WHEN they call GET /api/v1/analytics/weekly?start_date=2026-03-01&end_date=2026-03-31
THEN the response includes up to 5 data points with year, week, total, count, week_start, week_end
```

#### F-ANA-03: Monthly Spending

| Field | Value |
|-------|-------|
| **Description** | Monthly spending totals for a given year. Returns all 12 months (with zeros for empty months) and a grand total. |
| **Endpoint** | `GET /api/v1/analytics/monthly?year={}` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with expenses in January, March, and April 2026
WHEN they call GET /api/v1/analytics/monthly?year=2026
THEN the response includes 12 month entries (1 through 12)
  AND months without expenses have total=0.0 and count=0
  AND grand_total is the sum of all 12 months
```

#### F-ANA-04: Spending by Category

| Field | Value |
|-------|-------|
| **Description** | Spending breakdown by category within a date range. Returns totals, counts, and percentages per category for pie chart visualization. Uncategorized expenses are grouped under "Uncategorized". |
| **Endpoint** | `GET /api/v1/analytics/by-category?start_date={}&end_date={}` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with expenses across 4 categories
WHEN they call GET /api/v1/analytics/by-category?start_date=2026-03-01&end_date=2026-03-31
THEN the response includes data for each category with category_name, color, icon, total, count, percentage
  AND percentages sum to approximately 100%
  AND hidden categories are excluded
```

#### F-ANA-05: Budget Status

| Field | Value |
|-------|-------|
| **Description** | Budget vs actual spending per category for a given month. Compares each category's monthly_budget against actual spending. Returns status labels: on_track, warning (>=80%), over_budget (>=100%). |
| **Endpoint** | `GET /api/v1/analytics/budget-status?month={}&year={}` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with category "Food" budgeted at $500 and $450 spent this month
WHEN they call GET /api/v1/analytics/budget-status
THEN the Food category shows budget=500, spent=450, remaining=50, percentage_used=90.0, status="warning"

GIVEN a user with no budgeted categories
WHEN they call the budget-status endpoint
THEN the response includes total_budget=0, total_spent=0, and an empty categories array
```

---

### 3.11 AI Finance Chat (F-CHAT)

#### F-CHAT-01: Conversation CRUD

| Field | Value |
|-------|-------|
| **Description** | Create, list, update, and delete chat conversations. Each conversation belongs to the authenticated user. Listing includes last message preview. |
| **Endpoints** | `POST /api/v1/chat/conversations`, `GET /api/v1/chat/conversations`, `PUT /api/v1/chat/conversations/{id}`, `DELETE /api/v1/chat/conversations/{id}` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user
WHEN they create a conversation with title="March Budget Review"
THEN a ChatConversation record is created
  AND the response status is 201 Created

GIVEN an authenticated user with 3 conversations
WHEN they list conversations
THEN all 3 are returned sorted by updated_at descending
  AND each includes a last_message_preview (truncated to 100 chars)

GIVEN an authenticated user
WHEN they delete a conversation
THEN the conversation and all its messages are deleted
  AND the response status is 204 No Content
```

#### F-CHAT-02: Send Message with SSE Streaming

| Field | Value |
|-------|-------|
| **Description** | Send a user message to a conversation. The system saves the message, classifies intent (spending, budget, debt, category, trend), retrieves relevant financial context, and streams the AI response via Server-Sent Events. The complete response is saved as an assistant message. |
| **Endpoint** | `POST /api/v1/chat/conversations/{id}/messages` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with a conversation
WHEN they send a message "How much did I spend on food this month?"
THEN the user message is saved to the database
  AND the system classifies intent as ["spending", "category"]
  AND retrieves current month spending and category breakdown from the database
  AND streams the AI response via SSE (Content-Type: text/event-stream)
  AND each SSE event contains {"type": "text", "content": "..."}
  AND the final event contains {"type": "done", "message_id": "..."}
  AND the complete assistant response is saved as a ChatMessage

GIVEN a conversation with no title
WHEN the first message is sent
THEN the conversation title is auto-generated from the message content (first 60 chars)
```

#### F-CHAT-03: List Messages

| Field | Value |
|-------|-------|
| **Description** | Retrieve paginated message history for a conversation, sorted chronologically. |
| **Endpoint** | `GET /api/v1/chat/conversations/{id}/messages?limit={}&offset={}` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN a conversation with 10 messages
WHEN the user calls GET /api/v1/chat/conversations/{id}/messages?limit=5&offset=0
THEN 5 messages are returned sorted by created_at ascending
  AND the response includes total count of 10
```

#### F-CHAT-04: Bilingual Support

| Field | Value |
|-------|-------|
| **Description** | The chat system recognizes both English and Spanish queries. Intent classification handles Spanish keywords (gasté, presupuesto, deuda, tarjeta). The AI responds in the same language as the user's query. |
| **Endpoint** | (Part of `POST /api/v1/chat/conversations/{id}/messages`) |
| **Priority** | P2 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user
WHEN they send "Cuánto gasté este mes?"
THEN the intent classifier identifies "spending" from the Spanish keyword "gasté"
  AND the AI response is in Spanish

GIVEN an authenticated user
WHEN they send "Cuánta deuda tengo en mi tarjeta?"
THEN the intent classifier identifies "debt" from the Spanish keywords "deuda" and "tarjeta"
```

---

### 3.12 Tax Export (F-TAX)

#### F-TAX-01: Annual Tax Summary

| Field | Value |
|-------|-------|
| **Description** | Annual spending totals by category for a given year. Shows total spending, tax collected, deductible amounts, and receipt count. Used for tax preparation. |
| **Endpoint** | `GET /api/v1/tax/summary/{year}` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with 100 expenses in 2026
WHEN they call GET /api/v1/tax/summary/2026
THEN the response includes per-category totals: total_spending, total_tax_collected, deductible_amount, expense_count
  AND grand_total, grand_tax_collected, grand_deductible, and receipt_count
```

#### F-TAX-02: Export Expenses CSV

| Field | Value |
|-------|-------|
| **Description** | Download all expenses for a given year as a CSV file. Includes date, description, merchant, amount, tax, currency, category, tax-deductible flag. Hidden categories excluded by default. |
| **Endpoint** | `GET /api/v1/tax/export/{year}` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with expenses in 2026
WHEN they call GET /api/v1/tax/export/2026
THEN a CSV file is downloaded with Content-Disposition header
  AND columns: Date, Description, Merchant, Amount, Tax, Currency, Category, Tax Deductible, Recurring, Notes, Tags
  AND hidden-category expenses are excluded unless ?include_hidden=true

GIVEN no expenses for the requested year
WHEN the user calls the export endpoint
THEN the system returns 404 Not Found
```

#### F-TAX-03: Export Receipts ZIP

| Field | Value |
|-------|-------|
| **Description** | Download all receipt images for a given year as a ZIP archive. Files are organized by month with descriptive filenames including merchant name and amount. |
| **Endpoint** | `GET /api/v1/tax/receipts/{year}` |
| **Priority** | P2 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with 20 receipts in 2026
WHEN they call GET /api/v1/tax/receipts/2026
THEN a ZIP file is downloaded containing receipt images
  AND images are organized in folders by month (01/, 02/, etc.)
  AND filenames include date, merchant, amount, and TAX flag for deductible receipts

GIVEN no receipts for the requested year
WHEN the user calls the endpoint
THEN the system returns 404 Not Found
```

---

### 3.13 Auto-Label (F-AL)

#### F-AL-01: Rule CRUD

| Field | Value |
|-------|-------|
| **Description** | Create, list, update, and delete auto-label rules. Rules map keyword patterns to categories for automatic transaction labeling during import. Rules have priority ordering (lower = evaluated first). |
| **Endpoints** | `GET /api/v1/auto-label/rules`, `POST /api/v1/auto-label/rules`, `PATCH /api/v1/auto-label/rules/{id}`, `DELETE /api/v1/auto-label/rules/{id}` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user
WHEN they create a rule with keyword="CHIPOTLE", category_id={food_id}, priority=10
THEN an AutoLabelRule record is created
  AND the response status is 201 Created

GIVEN an authenticated user with an existing "CHIPOTLE" rule
WHEN they try to create another rule with keyword="CHIPOTLE"
THEN the system returns 409 Conflict

GIVEN an authenticated user
WHEN they delete a rule
THEN the rule is permanently removed
```

#### F-AL-02: Test Description Against Rules

| Field | Value |
|-------|-------|
| **Description** | Test a transaction description against the user's auto-label rules to preview which rule would match. |
| **Endpoint** | `POST /api/v1/auto-label/test` |
| **Priority** | P2 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with a rule: keyword="CHIPOTLE" -> Food category
WHEN they test description "POS DEBIT CHIPOTLE GRILL #1234"
THEN matched=true, rule_keyword="CHIPOTLE", category_id={food_id}

GIVEN no matching rule
WHEN they test a description
THEN matched=false
```

#### F-AL-03: Learn from User Correction

| Field | Value |
|-------|-------|
| **Description** | When a user manually categorizes an imported transaction, extract a keyword from the description and suggest an auto-label rule. |
| **Endpoint** | `POST /api/v1/auto-label/learn` |
| **Priority** | P2 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user who manually assigns "UBER TRIP 03/15" to Transportation
WHEN they call the learn endpoint
THEN the system extracts "UBER" as the suggested keyword
  AND returns a prompt: "Create a rule: when a transaction contains 'UBER', auto-assign it to 'Transportation'?"
```

---

### 3.14 Telegram (F-TG)

#### F-TG-01: Generate Link Code

| Field | Value |
|-------|-------|
| **Description** | Generate a one-time code for linking a Telegram account to the Finance Tracker user. Code expires in 24 hours. Old unused codes are invalidated. |
| **Endpoint** | `POST /api/v1/telegram/link` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user
WHEN they call POST /api/v1/telegram/link
THEN a unique 8-character hex code is generated
  AND any previous unused codes for this user are deleted
  AND the code expires in 24 hours
  AND the response includes code and expires_at
```

#### F-TG-02: Verify Link Code

| Field | Value |
|-------|-------|
| **Description** | Verify a link code sent from the Telegram bot. Called by the bot (not the web app). Activates the link and associates the Telegram user ID with the Finance Tracker user. |
| **Endpoint** | `POST /api/v1/telegram/verify` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN a valid, unexpired link code
WHEN the bot calls verify with the link_code, telegram_user_id, and telegram_username
THEN the TelegramLink record is activated (is_active=true)
  AND the telegram_user_id and username are stored
  AND the link_code is cleared (one-time use)
  AND the response includes success=true and user_id

GIVEN an expired link code
WHEN the bot calls verify
THEN the system returns 410 Gone

GIVEN a telegram_user_id already linked to another account
WHEN the bot calls verify
THEN the system returns 409 Conflict
```

#### F-TG-03: Lookup User by Telegram ID

| Field | Value |
|-------|-------|
| **Description** | Look up a Finance Tracker user by their Telegram user ID. Called by the bot to resolve incoming messages to user accounts. |
| **Endpoint** | `GET /api/v1/telegram/user/{telegram_user_id}` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN a linked Telegram account with telegram_user_id=123456789
WHEN the bot calls GET /api/v1/telegram/user/123456789
THEN the system returns user_id, linked=true, and telegram_username

GIVEN an unknown telegram_user_id
WHEN the bot calls the lookup endpoint
THEN the system returns 404 Not Found
```

#### F-TG-04: Get Link Status

| Field | Value |
|-------|-------|
| **Description** | Get the current user's Telegram link status: linked/unlinked, username, and linked_at timestamp. |
| **Endpoint** | `GET /api/v1/telegram/status` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with a linked Telegram account
WHEN they call GET /api/v1/telegram/status
THEN the response includes linked=true, telegram_username, and linked_at

GIVEN an authenticated user with no Telegram link
WHEN they call GET /api/v1/telegram/status
THEN the response includes linked=false
```

#### F-TG-05: Unlink Telegram

| Field | Value |
|-------|-------|
| **Description** | Unlink the current user's Telegram account. Removes the TelegramLink record. |
| **Endpoint** | `DELETE /api/v1/telegram/unlink` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN an authenticated user with a linked Telegram account
WHEN they call DELETE /api/v1/telegram/unlink
THEN the TelegramLink record is deleted
  AND the response includes success=true

GIVEN a user with no Telegram link
WHEN they call unlink
THEN the system returns 404 Not Found
```

---

### 3.15 Admin (F-ADM)

#### F-ADM-01: List Users

| Field | Value |
|-------|-------|
| **Description** | List all users in the system with pagination. Requires superuser access. |
| **Endpoint** | `GET /api/v1/admin/users` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN a superuser
WHEN they call GET /api/v1/admin/users
THEN all users are returned sorted by created_at descending
  AND each user includes id, email, display_name, is_active, is_superuser, created_at

GIVEN a non-superuser
WHEN they call any /api/v1/admin/ endpoint
THEN the system returns 403 Forbidden
```

#### F-ADM-02: Get/Toggle User Active Status

| Field | Value |
|-------|-------|
| **Description** | View a specific user's details and toggle their is_active status. Superusers cannot deactivate themselves. |
| **Endpoints** | `GET /api/v1/admin/users/{user_id}`, `PATCH /api/v1/admin/users/{user_id}` |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN a superuser
WHEN they call PATCH /api/v1/admin/users/{other_user_id}
THEN the target user's is_active flag is toggled
  AND the updated user record is returned

GIVEN a superuser
WHEN they try to deactivate their own account
THEN the system returns 400 Bad Request with "Cannot deactivate your own account"
```

#### F-ADM-03: System Statistics

| Field | Value |
|-------|-------|
| **Description** | System-wide statistics: total users, active users, total expenses, total receipts, and total debt items. |
| **Endpoint** | `GET /api/v1/admin/stats` |
| **Priority** | P2 |
| **Acceptance Criteria** | |

```gherkin
GIVEN a superuser
WHEN they call GET /api/v1/admin/stats
THEN the response includes total_users, active_users, total_expenses, total_receipts, total_debt_items
```

#### F-ADM-04: Manage Feature Flags per User

| Field | Value |
|-------|-------|
| **Description** | View and toggle feature flags for specific users. Creates the flag record if it does not exist yet. Tracks who enabled it and when. |
| **Endpoints** | `GET /api/v1/admin/users/{user_id}/features`, `PATCH /api/v1/admin/users/{user_id}/features` |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN a superuser
WHEN they call PATCH /api/v1/admin/users/{user_id}/features with {"feature_name": "friend_debt_calculator", "is_enabled": true}
THEN the feature flag is created or updated for the target user
  AND enabled_by is set to the superuser's ID
  AND enabled_at is set to the current timestamp

GIVEN a superuser
WHEN they call GET /api/v1/admin/users/{user_id}/features
THEN all feature flags for the target user are returned
```

---

### 3.16 Feature Flags (F-FF)

#### F-FF-01: Feature-Gated Access Control

| Field | Value |
|-------|-------|
| **Description** | Endpoints gated by `require_feature()` dependency reject requests from users who do not have the required flag enabled. Currently two flags: `friend_debt_calculator` and `hidden_categories`. |
| **Endpoint** | (Applied as dependency on `/api/v1/friend-debt/*` endpoints) |
| **Priority** | P0 |
| **Acceptance Criteria** | |

```gherkin
GIVEN a user WITHOUT the "friend_debt_calculator" flag enabled
WHEN they call any /api/v1/friend-debt/ endpoint
THEN the system returns 403 Forbidden with "Feature not enabled for your account"

GIVEN a user WITH the "friend_debt_calculator" flag enabled
WHEN they call /api/v1/friend-debt/summary?bank_balance=5000
THEN the request proceeds normally and returns the friend debt summary
```

#### F-FF-02: Dynamic Flag Evaluation

| Field | Value |
|-------|-------|
| **Description** | Feature flags are evaluated at request time by querying the UserFeatureFlag table. The frontend fetches flags via the admin endpoint and uses a FeatureFlagContext to conditionally render UI components. |
| **Endpoint** | (Implemented in `src/app/dependencies/feature_flags.py`) |
| **Priority** | P1 |
| **Acceptance Criteria** | |

```gherkin
GIVEN a user whose flag was just enabled by the admin
WHEN they make their next API request to a gated endpoint
THEN the updated flag value is respected immediately (no cache delay)

GIVEN the frontend FeatureFlagContext
WHEN the user's flags are loaded
THEN UI components for friend-debt and hidden-categories are conditionally shown/hidden
```

---

## 4. Non-Functional Requirements

| ID | Category | Requirement | Rationale |
|----|----------|-------------|-----------|
| NFR-01 | Mobile-First | All pages must be fully functional on screens as small as 320px wide. Tap targets must be at least 44x44px. CSS follows mobile-first breakpoints. | Primary users are on iPhone Safari and Android Chrome. |
| NFR-02 | Auth Security | Access tokens expire in 15 minutes. Refresh tokens expire in 7 days. Passwords are hashed with bcrypt. All tokens are invalidated on logout. Refresh token rotation is enforced (old tokens revoked on refresh). | Protects against token theft and session hijacking. |
| NFR-03 | Data Isolation | Every database query that returns user data must include a `WHERE user_id = {authenticated_user_id}` clause. No user can read, update, or delete another user's data via any API endpoint. | Multi-tenant system serving multiple independent users. |
| NFR-04 | Soft Deletes | Categories and debt items (credit cards, loans) use `is_active = false` for deletion rather than hard deletes. Existing foreign key references (e.g., expenses referencing a deleted category) remain intact. | Preserves referential integrity and audit trail. |
| NFR-05 | OCR Resilience | The OCR pipeline must gracefully handle: (a) Claude API unavailable -- fall back to Tesseract, (b) unreadable images -- return needs_review=true with partial data, (c) empty files -- return 422 before processing. All scanned receipts must include an ocr_method and confidence score. | Receipt scanning is a primary data input method and must not block the user workflow. |
| NFR-06 | API Versioning | All API endpoints are prefixed with `/api/v1/`. Future breaking changes will use `/api/v2/` while maintaining `/api/v1/` for backward compatibility. | Allows frontend and backend to evolve independently. |
| NFR-07 | CORS | CORS is configured to allow credentials from the frontend origin (finance.armandointeligencia.com in production, localhost:3000 in development). All HTTP methods and headers are allowed. | Required for cross-origin requests between frontend and backend subdomains. |
| NFR-08 | UUIDs | All primary keys use UUID v4, never auto-incrementing integers. | Prevents enumeration attacks and supports distributed ID generation. |
| NFR-09 | Timestamps | All `created_at` and `updated_at` columns are timezone-aware (`TIMESTAMPTZ`). The application normalizes to UTC internally. User-facing display respects the user's configured timezone. | Correct time handling across timezones for a multi-region user base. |
| NFR-10 | Receipt Image Security | Receipt images are stored in user-scoped directories (`receipts/{user_id}/{year}/{month}/`). Serving images via API requires authentication and ownership verification. Static file mounting does NOT bypass auth for API-served images. | Receipt images may contain sensitive financial information. |
| NFR-11 | Feature Flag Isolation | Feature-gated endpoints must return 403 (not 404) when the user lacks the required flag. The response must clearly indicate the feature is not enabled, not that the resource does not exist. Feature flags are evaluated at request time with no caching. | Users must understand why they cannot access a feature (disabled vs. nonexistent). |
| NFR-12 | Duplicate Detection | Import duplicate detection uses date + amount exact match combined with fuzzy description comparison (rapidfuzz token_set_ratio >= 85%). Detected duplicates default to include=false in the preview but can be overridden by the user. | Prevents double-counting when importing overlapping statement periods. |

---

## 5. Demo Environment

Three pre-seeded demo accounts provide immediate product evaluation without requiring account setup.

### Account 1: demo@armando.com (Superuser)

| Attribute | Value |
|-----------|-------|
| **Password** | `demo1234!` |
| **Role** | Superuser (admin panel access) |
| **Feature Flags** | friend_debt_calculator=true, hidden_categories=true |
| **Categories** | 9 defaults + 2 hidden ("Private Entertainment", "Personal Gifts") |
| **Expenses** | 100+ expenses across 6 months (Jan-Jun 2026) with realistic amounts |
| **Credit Cards** | Chase Sapphire ($2,500 balance, $10K limit, 24.99% APR), Amex Gold ($1,800 balance, $5K limit, 21.49% APR) |
| **Loans** | Car Loan ($12,000 remaining of $25,000, 5.9% rate), Student Loan ($8,500 remaining of $15,000, 4.5% rate) |
| **Friend Debt** | 5 deposits from "Maria" totaling $12,500, 2 withdrawals totaling $3,000 |
| **Receipts** | 10 archived receipt images with OCR data |
| **Chat History** | 2 conversations with budget review and debt strategy threads |
| **Auto-Label Rules** | 5 rules (Chipotle->Food, Uber->Transport, Netflix->Entertainment, Walmart->Shopping, Starbucks->Food) |

### Account 2: demo@maria.com (Standard User)

| Attribute | Value |
|-----------|-------|
| **Password** | `demo1234!` |
| **Role** | Standard user |
| **Feature Flags** | hidden_categories=true, friend_debt_calculator=false |
| **Categories** | 9 defaults + 1 custom ("Mercado") |
| **Expenses** | 50+ expenses across 3 months (Apr-Jun 2026) with Spanish merchant names |
| **Credit Cards** | Visa Oro ($800 balance, $3K limit, 29.99% APR) |
| **Loans** | None |
| **Language Preference** | Spanish labels where applicable |

### Account 3: demo@reviewer.com (Standard User)

| Attribute | Value |
|-----------|-------|
| **Password** | `demo1234!` |
| **Role** | Standard user (minimal data, clean evaluation) |
| **Feature Flags** | All enabled for demo purposes |
| **Categories** | 9 defaults only |
| **Expenses** | 15 expenses in the current month |
| **Credit Cards** | 1 sample card |
| **Loans** | 1 sample loan |
| **Purpose** | Clean, minimal account for evaluating the core flow without noise |

---

## 6. Success Metrics

| Metric | Target | Measurement Method |
|--------|--------|--------------------|
| Quick-Add Time | < 10 seconds from app open to expense saved | E2E test: measure time from page load to 201 response on `/api/v1/expenses/quick` |
| OCR Processing Time | < 15 seconds from image upload to extracted data returned | Backend instrumentation: measure wall-clock time of `POST /api/v1/receipts/scan` |
| Backend Test Coverage | >= 80% line coverage across all routers and services | `pytest --cov` report |
| Frontend Test Coverage | >= 70% line coverage across components and utilities | `vitest --coverage` report |
| Data Isolation | 0 cross-user data leaks | Automated test suite: register two users, create data for each, verify neither can access the other's data via any endpoint |
| Token Security | 0 instances of expired tokens granting access | Test: use an expired access token, verify 401; use a revoked refresh token, verify 401 |
| Regression Rate | < 5% of sprints introduce a regression | Track via CI: count test failures on main branch after merges |
| Debt Strategy Accuracy | Interest calculations within 0.5% of a reference amortization table | Unit tests: compare `compare_strategies()` output against manually calculated reference values |
| Import Duplicate Precision | >= 85% precision (flagged duplicates are actually duplicates) | Test with known duplicate and non-duplicate datasets |
| Mobile Lighthouse Score | >= 90 Performance, >= 95 Accessibility | Lighthouse CI in deployment pipeline |

---

## 7. Test Coverage Cross-Reference

The following matrix maps every functional requirement to existing test files and indicates coverage status:

- **COVERED**: Test exists and meaningfully exercises the feature
- **PARTIAL**: Test exists but does not fully cover all acceptance criteria
- **GAP**: No test exists for this feature

### 7.1 Authentication (F-AUTH)

| Feature ID | Feature | Backend Test | Frontend Test | E2E Test | Status |
|------------|---------|-------------|---------------|----------|--------|
| F-AUTH-01 | User Registration | `test_auth.py::test_register`, `test_auth.py::test_register_duplicate_email` | `api-client.test.ts` (register method tested via fetch mock) | `finance-workflow.spec.ts::register a new account` | **COVERED** |
| F-AUTH-02 | User Login | `test_auth.py::test_login`, `test_auth.py::test_login_wrong_password` | `api-client.test.ts` (login method) | `finance-workflow.spec.ts` (implicit via auth setup) | **COVERED** |
| F-AUTH-03 | Token Refresh | -- | `api-client.test.ts` (refreshToken method in ApiClient) | -- | **PARTIAL** -- backend has no dedicated refresh endpoint test |
| F-AUTH-04 | Logout | -- | -- | -- | **GAP** -- no test for POST /api/v1/auth/logout |
| F-AUTH-05 | Profile Management | `test_auth.py::test_get_me`, `test_auth.py::test_get_me_no_token` | -- | -- | **PARTIAL** -- GET /me tested, PATCH /me not tested |

### 7.2 Expenses (F-EXP)

| Feature ID | Feature | Backend Test | Frontend Test | E2E Test | Status |
|------------|---------|-------------|---------------|----------|--------|
| F-EXP-01 | List Expenses | `test_expenses.py::test_list_expenses_pagination_shape` | -- | `finance-workflow.spec.ts::view expenses list` | **PARTIAL** -- filter parameters (date range, search, amount) not tested |
| F-EXP-02 | Create Expense | `test_expenses.py::test_create_expense`, `test_expenses.py::test_create_expense_with_category` | -- | `finance-workflow.spec.ts::add expenses via API` | **COVERED** |
| F-EXP-03 | Quick-Add Expense | `test_expenses.py::test_quick_add_expense` | -- | -- | **PARTIAL** -- happy path tested, edge cases (invalid category, missing amount) not tested |
| F-EXP-04 | Get Single Expense | -- | -- | -- | **GAP** -- no test for GET /api/v1/expenses/{id} |
| F-EXP-05 | Update Expense | -- | -- | -- | **GAP** -- no test for PATCH /api/v1/expenses/{id} |
| F-EXP-06 | Delete Expense | `test_expenses.py::test_delete_expense` | -- | -- | **COVERED** |
| F-EXP-07 | List Hidden Expenses | -- | -- | -- | **GAP** -- no test for GET /api/v1/expenses/hidden |

### 7.3 Categories (F-CAT)

| Feature ID | Feature | Backend Test | Frontend Test | E2E Test | Status |
|------------|---------|-------------|---------------|----------|--------|
| F-CAT-01 | List Categories | `test_categories.py::test_list_categories` | -- | `finance-workflow.spec.ts::create expense categories via API` | **COVERED** |
| F-CAT-02 | Create Category | `test_categories.py::test_create_category`, `test_categories.py::test_create_category_with_options`, `test_categories.py::test_create_duplicate_category_returns_409` | -- | `finance-workflow.spec.ts` | **COVERED** |
| F-CAT-03 | Update Category | -- | -- | -- | **GAP** -- no test for PATCH /api/v1/categories/{id} |
| F-CAT-04 | Delete Category | `test_categories.py::test_delete_category` | -- | -- | **COVERED** |
| F-CAT-05 | Reorder Categories | -- | -- | -- | **GAP** -- no test for PUT /api/v1/categories/reorder |

### 7.4 Receipts (F-REC)

| Feature ID | Feature | Backend Test | Frontend Test | E2E Test | Status |
|------------|---------|-------------|---------------|----------|--------|
| F-REC-01 | Scan Receipt (OCR) | -- | -- | `finance-workflow.spec.ts::visit scan page` (navigates only, no upload test) | **GAP** -- no test for POST /api/v1/receipts/scan |
| F-REC-02 | Confirm Scanned Receipt | -- | -- | -- | **GAP** -- no test for POST /api/v1/receipts/confirm |
| F-REC-03 | Browse Archived Receipts | -- | -- | `finance-workflow.spec.ts::visit receipts page` (navigates only) | **GAP** -- no test for GET /api/v1/receipts/archive |
| F-REC-04 | Serve Receipt Image | -- | -- | -- | **GAP** -- no test for GET /api/v1/receipts/{id}/image |
| F-REC-05 | Queue Receipt | `test_pending_receipts.py::test_queue_receipt`, `test_pending_receipts.py::test_queue_receipt_rejects_non_image`, `test_pending_receipts.py::test_queue_receipt_unauthenticated` | -- | -- | **COVERED** |
| F-REC-06 | List Pending Receipts | `test_pending_receipts.py::test_list_pending_receipts`, `test_pending_receipts.py::test_list_pending_unauthenticated` | -- | -- | **COVERED** |
| F-REC-07 | Delete Pending Receipt | `test_pending_receipts.py::test_delete_pending_receipt` | -- | -- | **COVERED** |

### 7.5 Imports (F-IMP)

| Feature ID | Feature | Backend Test | Frontend Test | E2E Test | Status |
|------------|---------|-------------|---------------|----------|--------|
| F-IMP-01 | Upload and Parse Statement | `test_csv_parser.py::test_parse_chase_csv`, `test_csv_parser.py::test_parse_bofa_csv` | -- | -- | **PARTIAL** -- CSV parsing logic tested, but not the full upload endpoint (auto-label, duplicate detection) |
| F-IMP-02 | Confirm Import | -- | -- | -- | **GAP** -- no test for POST /api/v1/import/confirm |
| F-IMP-03 | Import History | -- | -- | -- | **GAP** -- no test for GET /api/v1/import/history |
| F-IMP-04 | Bank Templates | -- | -- | -- | **GAP** -- no test for GET /api/v1/import/templates |
| F-IMP-05 | PDF Statement Parsing | -- | -- | -- | **GAP** -- no test for PDF parsing path |
| F-IMP-06 | Duplicate Detection | `test_csv_parser.py::test_detect_chase_format`, `test_csv_parser.py::test_detect_bofa_format`, `test_csv_parser.py::test_detect_generic_fallback` | -- | -- | **PARTIAL** -- bank format detection tested, but not the fuzzy duplicate matching logic |

### 7.6 Credit Cards (F-CC)

| Feature ID | Feature | Backend Test | Frontend Test | E2E Test | Status |
|------------|---------|-------------|---------------|----------|--------|
| F-CC-01 | CRUD Credit Cards | `test_credit_cards.py::test_create_credit_card`, `test_credit_cards.py::test_list_credit_cards`, `test_credit_cards.py::test_delete_credit_card`, `test_credit_cards.py::test_utilization_computed_correctly`, `test_credit_cards.py::test_utilization_none_when_no_limit` | -- | `finance-workflow.spec.ts::navigate to debt page and add credit card` | **COVERED** |
| F-CC-02 | Log Payment | -- | -- | -- | **GAP** -- no test for POST /api/v1/credit-cards/{id}/payment |
| F-CC-03 | Payoff Projection | `test_debt_calculator.py::test_cc_payoff_basic`, `test_debt_calculator.py::test_cc_payoff_insufficient_payment`, `test_debt_calculator.py::test_cc_payoff_zero_balance` | `debt-math.test.ts::calculateCCPayoff` (4 test cases) | -- | **PARTIAL** -- calculation logic tested, but not the API endpoint |

### 7.7 Loans (F-LN)

| Feature ID | Feature | Backend Test | Frontend Test | E2E Test | Status |
|------------|---------|-------------|---------------|----------|--------|
| F-LN-01 | CRUD Loans | `test_loans.py::test_create_loan`, `test_loans.py::test_list_loans`, `test_loans.py::test_delete_loan`, `test_loans.py::test_progress_percent_computed_correctly`, `test_loans.py::test_progress_percent_fully_paid` | -- | `finance-workflow.spec.ts::add a loan` | **COVERED** |
| F-LN-02 | Log Payment / Snowflake | -- | -- | -- | **GAP** -- no test for POST /api/v1/loans/{id}/payment or /snowflake |
| F-LN-03 | Amortization Schedule | `test_debt_calculator.py::test_amortization_schedule`, `test_debt_calculator.py::test_amortization_final_balance_zero` | `debt-math.test.ts::calculateLoanPayoff` (3 test cases) | -- | **PARTIAL** -- calculation logic tested, but not the API endpoint |

### 7.8 Debt Strategy (F-DEBT)

| Feature ID | Feature | Backend Test | Frontend Test | E2E Test | Status |
|------------|---------|-------------|---------------|----------|--------|
| F-DEBT-01 | Debt Summary | -- | -- | -- | **GAP** -- no test for GET /api/v1/debt/summary |
| F-DEBT-02 | Strategy Comparison | `test_debt_strategies.py::test_avalanche_targets_highest_apr`, `test_debt_strategies.py::test_snowball_targets_smallest_balance`, `test_debt_strategies.py::test_compare_strategies`, `test_debt_strategies.py::test_budget_insufficient`, `test_debt_strategies.py::test_single_debt` | `debt-math.test.ts::compareStrategies` (4 test cases) | -- | **PARTIAL** -- service-layer logic tested thoroughly, but not the API endpoint |
| F-DEBT-03 | Debt History | -- | -- | -- | **GAP** -- no test for GET /api/v1/debt/history |

### 7.9 Friend Debt (F-FD)

| Feature ID | Feature | Backend Test | Frontend Test | E2E Test | Status |
|------------|---------|-------------|---------------|----------|--------|
| F-FD-01 | Friend Debt Summary | `test_friend_debt.py::test_clear_status`, `test_friend_debt.py::test_shortfall_status`, `test_friend_debt.py::test_covered_by_external`, `test_friend_debt.py::test_zero_deposits` | -- | -- | **PARTIAL** -- calculation logic tested, but not the API endpoint with feature flag gating |
| F-FD-02 | Deposit/Withdrawal CRUD | -- | -- | -- | **GAP** -- no test for POST/GET/DELETE /api/v1/friend-debt/deposits |
| F-FD-03 | External Account CRUD | -- | -- | -- | **GAP** -- no test for /api/v1/friend-debt/external-accounts endpoints |

### 7.10 Analytics (F-ANA)

| Feature ID | Feature | Backend Test | Frontend Test | E2E Test | Status |
|------------|---------|-------------|---------------|----------|--------|
| F-ANA-01 | Daily Spending | -- | -- | `finance-workflow.spec.ts::view analytics page` (navigates, checks elements) | **GAP** -- no direct API test for GET /api/v1/analytics/daily |
| F-ANA-02 | Weekly Spending | -- | -- | -- | **GAP** -- no test for GET /api/v1/analytics/weekly |
| F-ANA-03 | Monthly Spending | -- | -- | -- | **GAP** -- no test for GET /api/v1/analytics/monthly |
| F-ANA-04 | Spending by Category | -- | -- | -- | **GAP** -- no test for GET /api/v1/analytics/by-category |
| F-ANA-05 | Budget Status | -- | -- | -- | **GAP** -- no test for GET /api/v1/analytics/budget-status |

### 7.11 AI Finance Chat (F-CHAT)

| Feature ID | Feature | Backend Test | Frontend Test | E2E Test | Status |
|------------|---------|-------------|---------------|----------|--------|
| F-CHAT-01 | Conversation CRUD | `test_chat.py::TestConversationAPI` (create, list, update, delete, not_found -- 5 tests) | -- | -- | **COVERED** |
| F-CHAT-02 | Send Message (SSE) | `test_chat.py::TestMessagesAPI::test_send_message_requires_auth` | `chat.test.ts` (if present) | -- | **PARTIAL** -- auth check tested, but not the actual SSE streaming flow |
| F-CHAT-03 | List Messages | `test_chat.py::TestMessagesAPI::test_list_messages_empty`, `test_chat.py::TestMessagesAPI::test_messages_not_found_for_wrong_conversation` | -- | -- | **COVERED** |
| F-CHAT-04 | Bilingual Support | `test_chat.py::TestIntentClassification::test_spanish_spending`, `test_chat.py::TestIntentClassification::test_spanish_debt` | -- | -- | **PARTIAL** -- intent classification tested for Spanish, but not the AI response language |

### 7.12 Tax Export (F-TAX)

| Feature ID | Feature | Backend Test | Frontend Test | E2E Test | Status |
|------------|---------|-------------|---------------|----------|--------|
| F-TAX-01 | Annual Tax Summary | -- | -- | -- | **GAP** -- no test for GET /api/v1/tax/summary/{year} |
| F-TAX-02 | Export Expenses CSV | -- | -- | -- | **GAP** -- no test for GET /api/v1/tax/export/{year} |
| F-TAX-03 | Export Receipts ZIP | -- | -- | -- | **GAP** -- no test for GET /api/v1/tax/receipts/{year} |

### 7.13 Auto-Label (F-AL)

| Feature ID | Feature | Backend Test | Frontend Test | E2E Test | Status |
|------------|---------|-------------|---------------|----------|--------|
| F-AL-01 | Rule CRUD | -- | -- | -- | **GAP** -- no test for /api/v1/auto-label/rules endpoints |
| F-AL-02 | Test Description | -- | -- | -- | **GAP** -- no test for POST /api/v1/auto-label/test |
| F-AL-03 | Learn from Correction | -- | -- | -- | **GAP** -- no test for POST /api/v1/auto-label/learn |

### 7.14 Telegram (F-TG)

| Feature ID | Feature | Backend Test | Frontend Test | E2E Test | Status |
|------------|---------|-------------|---------------|----------|--------|
| F-TG-01 | Generate Link Code | `test_telegram.py::TestTelegramLink::test_generate_link_code`, `test_telegram.py::TestTelegramLink::test_generate_replaces_old_codes` | -- | -- | **COVERED** |
| F-TG-02 | Verify Link Code | `test_telegram.py::TestTelegramVerify` (valid, invalid, expired, duplicate -- 4 tests) | -- | -- | **COVERED** |
| F-TG-03 | Lookup by Telegram ID | `test_telegram.py::TestTelegramLookup::test_lookup_linked_user`, `test_telegram.py::TestTelegramLookup::test_lookup_unknown_user` | -- | -- | **COVERED** |
| F-TG-04 | Get Link Status | `test_telegram.py::TestTelegramStatus::test_status_not_linked`, `test_telegram.py::TestTelegramStatus::test_status_linked` | -- | -- | **COVERED** |
| F-TG-05 | Unlink Telegram | `test_telegram.py::TestTelegramUnlink::test_unlink`, `test_telegram.py::TestTelegramUnlink::test_unlink_not_linked` | -- | -- | **COVERED** |

### 7.15 Admin (F-ADM)

| Feature ID | Feature | Backend Test | Frontend Test | E2E Test | Status |
|------------|---------|-------------|---------------|----------|--------|
| F-ADM-01 | List Users | -- | -- | -- | **GAP** -- no test for GET /api/v1/admin/users |
| F-ADM-02 | Toggle User Active | -- | -- | -- | **GAP** -- no test for PATCH /api/v1/admin/users/{id} |
| F-ADM-03 | System Statistics | -- | -- | -- | **GAP** -- no test for GET /api/v1/admin/stats |
| F-ADM-04 | Manage Feature Flags | `test_feature_flags.py::test_admin_toggle_flag` | -- | -- | **PARTIAL** -- toggle tested, but list flags (GET) not tested |

### 7.16 Feature Flags (F-FF)

| Feature ID | Feature | Backend Test | Frontend Test | E2E Test | Status |
|------------|---------|-------------|---------------|----------|--------|
| F-FF-01 | Gated Access Control | `test_feature_flags.py::test_feature_gated_endpoint_without_flag`, `test_feature_flags.py::test_feature_gated_endpoint_with_flag` | -- | -- | **COVERED** |
| F-FF-02 | Dynamic Flag Evaluation | -- | -- | -- | **PARTIAL** -- tested via F-FF-01, but no test for frontend FeatureFlagContext |

### 7.17 Frontend Utility Tests

| Test File | Covers | Features Mapped |
|-----------|--------|-----------------|
| `api-client.test.ts` | ApiClient construction, auth headers, error handling, 204 responses | Cross-cutting: F-AUTH-01, F-AUTH-02 (indirectly) |
| `debt-math.test.ts` | CC payoff, loan payoff, strategy comparison calculations | F-CC-03, F-LN-03, F-DEBT-02 (client-side logic) |
| `format-helpers.test.ts` | Currency formatting, percentage formatting | Cross-cutting: display layer |
| `image-compress.test.ts` | fileToBase64 conversion | F-REC-01 (preprocessing utility) |
| `navigation.test.tsx` | Bottom nav rendering, active state, href correctness | Cross-cutting: navigation UX |

### 7.18 E2E Workflow Coverage

| E2E Test | Steps Covered | Features Touched |
|----------|---------------|-----------------|
| `finance-workflow.spec.ts::register a new account` | Registration via API, token storage | F-AUTH-01 |
| `finance-workflow.spec.ts::create expense categories via API` | Category creation via API | F-CAT-02 |
| `finance-workflow.spec.ts::add expenses via API` | Expense creation via API | F-EXP-02 |
| `finance-workflow.spec.ts::view expenses list` | Navigate to expenses page, verify elements | F-EXP-01 (UI only) |
| `finance-workflow.spec.ts::navigate to debt page and add credit card` | CC creation via API, navigate debt page | F-CC-01 |
| `finance-workflow.spec.ts::add a loan` | Loan creation via API | F-LN-01 |
| `finance-workflow.spec.ts::view analytics page` | Navigate analytics page, verify charts | F-ANA-01 (UI only) |
| `finance-workflow.spec.ts::visit scan page` | Navigate scan page | F-REC-01 (UI only, no upload) |
| `finance-workflow.spec.ts::visit receipts page` | Navigate receipts page | F-REC-03 (UI only) |
| `finance-workflow.spec.ts::return to dashboard` | Navigate home | Cross-cutting |

---

### 7.19 Coverage Summary

| Status | Count | Percentage |
|--------|-------|------------|
| **COVERED** | 26 | 39.4% |
| **PARTIAL** | 14 | 21.2% |
| **GAP** | 26 | 39.4% |
| **Total Features** | **66** | 100% |

### Priority Gap Analysis

| Priority | Total | Covered | Partial | Gap |
|----------|-------|---------|---------|-----|
| P0 | 21 | 12 | 4 | 5 |
| P1 | 31 | 11 | 7 | 13 |
| P2 | 14 | 3 | 3 | 8 |

**Critical P0 Gaps (must address first):**
1. F-AUTH-04 -- Logout (no test)
2. F-REC-01 -- Scan Receipt OCR endpoint (no test)
3. F-REC-02 -- Confirm Scanned Receipt (no test)
4. F-DEBT-01 -- Debt Summary endpoint (no test)
5. F-ADM-01 -- List Users admin endpoint (no test)

**High-Priority P1 Gaps (address second):**
1. F-IMP-02 -- Confirm Import endpoint
2. F-CC-02 -- Log Credit Card Payment endpoint
3. F-LN-02 -- Log Loan Payment / Snowflake endpoints
4. F-TAX-01/02/03 -- All tax export endpoints
5. F-AL-01/02/03 -- All auto-label endpoints
6. F-ANA-01 through F-ANA-05 -- All analytics endpoints
7. F-FD-02/03 -- Friend debt CRUD endpoints

---

*End of Document*
