# E2E Validation — Final Report (2026-04-22)

Two validation passes, 19 user flows, **7 bugs caught and 7 bugs fixed**, full Claude API verified end-to-end.

## Summary

| Metric | Value |
|---|---|
| User flows exercised | 19 |
| OK checkpoints | 50 |
| Bugs discovered | 7 |
| Bugs fixed this session | 7 |
| Test harness files | 2 drivers + 1 plan + 2 reports |
| Backend tests regression | 200 passed (was 200) |
| Frontend tests regression | 67 passed (was 67) |

## What was validated

### Pass 1 — core flows (10)
- F1 Registration + login
- F2 Categories page render
- F3 Manual expense entry × 3
- F4 Receipt OCR with real Claude Vision (Dunkin' receipt)
- F5 Analytics aggregate math
- F6 Debt dashboard (CC + loan display)
- F7 AI Finance Chat with real Claude Haiku streaming
- F8 Rate limiting (20/min chat, 2/10s OCR)
- F9 Settings page + Telegram link flow
- F10 Logout

### Pass 2 — deeper coverage (9 more)
- F11 Expense edit + delete
- F12 Category CRUD — create, rename, set budget, archive
- F13 Bank statement CSV import
- F14 Credit-card + loan payments, balance decrement, debt strategies, what-if slider
- F15 Chat conversation management — create, rename, delete, switch to Sonnet model
- F16 Admin panel + feature flags (hidden_categories, friend_debt_calculator)
- F17 Multi-user data isolation — User B sees 0 of User A's data
- F18 Auth edge cases — wrong password, duplicate email, invalid/missing token, short password
- F19 Spanish receipt OCR (Costco) — 22 line items extracted via Claude

## Bugs found + fixed

| # | Severity | Area | Root cause | Fix |
|---|---|---|---|---|
| **B1** | 🔴 High | Categories UI | `{category.icon}` rendered string icon names as literal text | Added `LUCIDE_ICON_MAP` and `<CategoryIcon>` component that resolves string → React component, falls through to emoji |
| **B2** | 🟠 Med | Debt Dashboard | Frontend read `debtSummary.total_debt` but backend returns `total_balance` | Renamed all reads to `total_balance` |
| **B3** | 🟠 Med | OCR service | `_CATEGORY_LIST` had 15 names that didn't match the 9 seeded defaults — OCR's `category_suggestion` could never auto-match | Shrunk `_CATEGORY_LIST` to exactly the 9 seeded names |
| **B4** | 🟡 Low | Settings copy | "Cloud Only" said "Google Vision / AWS Textract" — wrong provider | Changed to "Claude Vision (Haiku 4.5)" |
| **B5** | 🟡 Low | Chat concurrency | asyncpg default pool (5) exhausted by concurrent chat streaming (2 sessions per request) | Bumped to 20 + 10 overflow via `db_pool_size` / `db_max_overflow` config, SQLite bypass for tests |
| **B6** | 🟠 Med | Debt strategies | Router called low-level `compare_strategies` (raw dict) but declared `response_model=StrategyComparison` — 500 ResponseValidationError | Switched to `compare_strategies_schema` (Pydantic-wrapped variant) |
| **B7** | 🟡 Low | Registration validation | Backend accepted 3-char passwords despite "Min 6 characters" UI copy | Added `Field(..., min_length=6)` on `UserRegister.password` |

## Cross-flow evidence that the app actually works

The important test is not "does the endpoint return 200" — it's "does data flow correctly between features." Everything in this list I verified by reading screenshots or API responses:

| Chain | Expected | Observed | Result |
|---|---|---|---|
| `POST /expenses × 3` → `GET /expenses` | 3 items, correct amounts + categories | ✅ $89, $43.21, $5.50 with Food & Dining / Bills & Utilities | ✅ |
| `PATCH /expenses` + `DELETE /expenses` → `GET /expenses` | 2 items, edited amount shown | ✅ "Starbucks (edited) $12.34", 3rd gone | ✅ |
| Expenses → `GET /analytics/monthly` | Sum = ~$137 | ✅ $137.71 ($89 + $48.71) | ✅ |
| Expenses → Claude chat context | Claude quotes Netflix, Whole Foods, Starbucks by name | ✅ All three referenced verbatim in streaming response | ✅ |
| Receipt → Claude OCR → Confirm → Expenses | Dunkin' $23.15 appears in expenses list | ✅ Appears under "EARLIER" (OCR read original receipt date 2023-05-30) | ✅ |
| `POST /credit-cards/{id}/payment 100` → balance | $500 → $400 | ✅ Exact match | ✅ |
| `POST /loans/{id}/payment 350` → balance | Decreases but less than payment (interest) | ✅ $15,000 → $14,718.75 (~$281 principal, ~$69 interest — reasonable for 5.5% APR) | ✅ |
| Debt strategies `monthly_budget=600` vs `400` | Smaller budget → longer payoff | ✅ 27 months vs 42 months, $990 vs $1,763 total interest | ✅ |
| Category create/rename/archive → `GET /categories` | Coffee added, Shopping gone | ✅ Icons + budget render, Shopping no longer listed | ✅ |
| Bank CSV upload → preview | 3 transactions parsed from Chase CSV | ✅ Parsed Starbucks/Trader Joe's/Payroll | ✅ |
| User A creates data → User B registers → B lists | B sees 0 expenses, own 9 default categories | ✅ Isolation holds; cross-user GET returns 404 | ✅ |
| Admin enables flags → API call success | Flags stored | ✅ Both feature flags toggled to on |  ⚠ UI requires page reload to reflect (see F16-note) |
| Auth edge cases | wrong pw 401, dup 409, bad token 401, no token 401, short pw 422 | All 5 correct (after B7 fix) | ✅ |
| Claude receipt OCR — Spanish (Costco) | merchant + total + items | ✅ "Costco Wholesale", $505.41, 22 line items | ✅ |

## F16 note — feature flags + session caching

Enabling `hidden_categories` / `friend_debt_calculator` via the admin API returns 200, but the affected user's frontend still shows "Feature Not Enabled" on `/hidden` and `/friend-debt` until they re-login. The `FeatureFlagsContext` pulls on mount; without a refetch mechanism, in-session toggles look stale. **Not wired as a bug** because the real admin workflow usually involves the user re-logging anyway, but worth flagging as a UX polish for later (invalidate the flag cache on admin-triggered change).

## Test harness artifacts

- `drive.mjs` — pass-1 driver (10 flows)
- `drive-pass2.mjs` — pass-2 driver (9 flows, with page-warmup to handle Next dev compile latency)
- `PLAN.md` — original pass-1 plan
- `REPORT.md` — pass-1 findings
- `FINAL-REPORT.md` — this file (combined)

Screenshots go to `docs/e2e-validation/screenshots/` (pass 1, 21 PNGs) and `screenshots-pass2/` (pass 2, 8 PNGs + 5 JSON dumps). Both folders are gitignored — they're byproducts of local runs.

## Missed flows deliberately not covered

- **Telegram bot end-to-end** — would require a live bot token and chat session. The API side (link code generation, bot-secret auth on `/verify` and `/user/{id}`) is covered by backend pytest (15 passing).
- **Receipt upload via camera** — headless Chrome can't access a real camera. The Upload button path is exercised indirectly via `/scan` direct API calls.
- **PDF bank statement import** — CSV was tested; PDF would need pdfplumber integration, and we don't have a sample PDF on hand.
- **Tax export download** — tax_export router is left intact per Option A choice on receipt OCR; not re-tested since pass 1 didn't touch it.
- **PWA install / home-screen shortcut** — platform-specific, manual test.

## State after session

- 10 commits pushed to `origin/main` in prior session (v4.0 + hygiene + pass-1 fixes)
- 7 new bug-fix commits pending in this session (will be committed now)
- Backend: 200 tests passing, no regressions
- Frontend: 67 tests passing, `tsc --noEmit` clean
- Live stack state: postgres in docker, uvicorn on :8040, next dev on :3040, test user `claude@example.com` present

## Recommendation

**Ready for iOS work (Path A — Capacitor).** The web app is functionally sound end-to-end with real Claude, and the cross-feature data flows I verified are the exact flows a Capacitor-wrapped iOS app would exercise. Nothing here would block that work.
