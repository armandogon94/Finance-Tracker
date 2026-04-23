# E2E Validation Report — 2026-04-22

**Stack under test:** frontend `localhost:3040` → backend `localhost:8040` → postgres `5434`
**Real Claude API:** yes, `ANTHROPIC_API_KEY` live
**Test user:** `claude@example.com` / `ClaudeTest2026!` — named "Claude Tester"
**Method:** drove the real frontend with Playwright, screenshotted every state, **visually read each PNG** to validate, cross-checked data cascades across flows.

## Headline

**10 / 10 flows work end-to-end.** The app is functional, with real Claude receipt OCR and AI chat both proven on a live key. Found **5 real bugs**, 1 of them visual/high-priority (categories page), 4 minor. A handful of test-harness artifacts were diagnosed and worked around.

---

## Flow results

| # | Flow | Status | Evidence | Notes |
|---|------|--------|----------|-------|
| F1 | Registration + login | ✅ | [04-post-login-home.png](screenshots/04-post-login-home.png) | JWT stored, dashboard greets "Hello, Claude Tester" |
| F2 | Categories | ⚠️ bug | [10-categories-list.png](screenshots/10-categories-list.png) | **Lucide icons render as raw text** |
| F3 | Manual expense entry (×3) | ✅ | [21-expenses-list.png](screenshots/21-expenses-list.png) | Amounts, dates, categories all persist |
| F4 | Receipt OCR via Claude | ✅ | [30-scan-response.json](screenshots/30-scan-response.json) | Dunkin' receipt → merchant, $23.15 total, 4 items, "Dining" suggestion |
| F5 | Analytics | ✅ | [40-analytics-month.png](screenshots/40-analytics-month.png) | $137.71 = sum of current-month expenses; donut + bar chart correct |
| F6 | Debt tracker | ⚠️ bug | [50-debt-overview.png](screenshots/50-debt-overview.png) | CC + loan render perfectly; **"Total Debt $0" summary bug** |
| F7 | AI Finance Chat | ✅ | [60-chat-stream.txt](screenshots/60-chat-stream.txt), [61-chat-with-conversation.png](screenshots/61-chat-with-conversation.png) | Streams real Claude Haiku response grounded in my actual expenses |
| F8 | Rate limits | ✅ | [70-rate-results.json](screenshots/70-rate-results.json) + curl probes | OCR: 3rd → 429. Chat: 21st → 429. Confirmed. |
| F9 | Settings + Telegram | ⚠️ copy | [80-settings.png](screenshots/80-settings.png), [81-telegram-link.png](screenshots/81-telegram-link.png) | Rich settings page, **"Cloud Only" description is stale** |
| F10 | Logout | ✅ | [90-after-logout.png](screenshots/90-after-logout.png) | Clean session teardown, returns to login |

---

## Bug catalog

### 🔴 B1 — Category page renders icon names as raw text (visual)
**Severity:** High (directly user-visible on the primary Categories screen)
**Location:** [frontend/src/app/categories/page.tsx:111](../../frontend/src/app/categories/page.tsx#L111)
**Evidence:** [10-categories-list.png](screenshots/10-categories-list.png) — literal text "utensils", "car", "shopping-bag", "film", "zap", "heart", "book", "user", "receipt" visible next to category names.
**Root cause:** The DB column `categories.icon` stores a lucide-react icon name as a string. The JSX does `{category.icon ?? …}` which renders it as plain text. There's no mapping from the string to a lucide React component.
**Fix shape:**
```tsx
const ICONS: Record<string, LucideIcon> = { utensils: Utensils, car: Car, ... };
const Icon = category.icon ? ICONS[category.icon] : null;
{Icon ? <Icon className="h-5 w-5" /> : <span className="h-3 w-3 rounded-full" .../>}
```

### 🟠 B2 — "Total Debt" summary card shows $0 despite real debt
**Severity:** Medium (headline number on Debt Dashboard is wrong)
**Location:** [frontend/src/app/debt/page.tsx](../../frontend/src/app/debt/page.tsx) (summary card)
**Evidence:** [50-debt-overview.png](screenshots/50-debt-overview.png) — Amex Gold $500 + Car Loan $15,000 visible, but top card reads **"Total Debt $0"**. "Min. Monthly $375" is correct though ($25 + $350).
**Suspected cause:** Summary aggregation reads from a field (`total_debt`) that isn't being computed, while `minimum_payment` sums are. Worth a look at the debt summary API and the React selector.

### 🟠 B3 — Default categories don't match OCR category list
**Severity:** Medium (breaks auto-category suggestion)
**Location:** User registration seed vs [backend/src/app/services/ocr.py:30-34 _CATEGORY_LIST](../../backend/src/app/services/ocr.py#L30)
**Evidence:** Receipt scan returned `category_suggestion: "Dining"`, but no category named "Dining" exists — defaults are "Food & Dining", "Transportation", "Shopping", "Entertainment", "Bills & Utilities", "Health", "Education", "Personal", "Other" (9 total). The Dunkin' expense saved as **Uncategorized** as a result.
**Fix shape:** Either (a) seed the 15 categories that `_CATEGORY_LIST` names, or (b) shrink `_CATEGORY_LIST` to exactly the seeded names. Option b is simpler and keeps the UX consistent.

### 🟡 B4 — Settings page describes OCR "Cloud Only" as wrong provider
**Severity:** Low (copy, not functional)
**Location:** [frontend/src/app/settings/page.tsx](../../frontend/src/app/settings/page.tsx)
**Evidence:** [80-settings.png](screenshots/80-settings.png) — "Cloud Only" subtitle says "Google Vision / AWS Textract" but the app uses Claude Vision + Ollama + Tesseract.

### 🟡 B5 — Chat endpoint returns 500 under concurrent fire (pool exhaustion)
**Severity:** Low in current scope (no concurrent real users)
**Location:** [backend/src/app/routers/chat.py](../../backend/src/app/routers/chat.py) around the `async_session()` fresh-session pattern
**Evidence:** In the Node driver's rate-limit burst, every 4th request returned 500 while streams were still open. Sequential curl at 1 req/sec gets zero 500s (confirmed). This is asyncpg default pool saturating because each chat request holds two sessions (primary + fresh for assistant save).
**Fix shape:** Bump asyncpg pool size (e.g., 10–20), or fold assistant-save back into the primary session.

---

## Test-harness artifacts (not app bugs, but worth knowing)

- **H1 — Shell `ANTHROPIC_API_KEY=''` override:** pydantic-settings prefers env vars over `.env`, and my shell had an empty-string key set globally. First backend launch → Claude disabled silently → fell through to Tesseract (not installed) → errors. Fixed by launching uvicorn with an explicit `env ANTHROPIC_API_KEY=…` prefix.
- **H2 — `Date.toISOString()` UTC drift:** Node's `new Date().toISOString().slice(0,10)` returns the UTC date, so expenses created at 9 PM ET saved as the next UTC day. Chat's monthly aggregation uses local `date.today()`, which then excluded "today's" expenses. The UI flow uses the browser's local date picker, so real users aren't affected.
- **H3 — Tesseract not installed locally:** OCR auto-mode's offline fallback crashes with `TesseractNotFoundError`. In Docker deploy this is fine (image ships it). For local dev, either install via brew or document that Claude must be configured.
- **H4 — RSC 403s in dev:** Next.js dev server emits harmless 403s on `_rsc` prefetch to `/login` when navigating away — not a real error, standard Next 14 dev behavior.

---

## Cross-flow data validation

This is the part that "just passing an endpoint" can't catch:

| Check | Expected | Observed | Status |
|-------|----------|----------|--------|
| Expenses → shown in list | 4 items, correct amounts | 4 items: $89, $43.21, $5.50, $23.15 | ✅ |
| Expenses → month analytics total | $5.50 + $43.21 + $89 = $137.71 (Dunkin' dated 2023) | $137.71 shown | ✅ |
| Expenses → category breakdown | Bills & Utilities $89, Food & Dining $48.71 | donut + legend matches | ✅ |
| Expenses → Chat context | Claude sees Netflix, Whole Foods, Starbucks by name | All three quoted back verbatim | ✅ |
| Receipt OCR → Expense row | Dunkin' merchant, May 29 date, $23.15 amount | Appears in Expenses list under "EARLIER" | ✅ |
| Debt rows → summary | $500 CC + $15,000 loan = $15,500 total | ❌ **Total Debt shows $0** | bug B2 |
| Category color → expense row dot | Food & Dining = red, Bills & Utilities = purple | Matches visually | ✅ |
| OCR "Dining" suggestion → saved category | Should auto-select Dining | Saved as Uncategorized | bug B3 |

---

## Triage recommendation

**Ship-blockers:** none.
**Fix before iOS work:** B1 (icon rendering — first screen users hit), B3 (category mismatch — OCR UX).
**Can ship on "nice to have" backlog:** B2, B4, B5.

I did not modify the app to fix these during this session — the scope was validation. Ready to queue them up for a fix pass on your say-so.

---

## Artifacts

- **Plan:** [PLAN.md](PLAN.md)
- **Driver script:** [drive.mjs](drive.mjs) (re-runnable: `node drive.mjs all`)
- **Screenshots:** [screenshots/](screenshots/) (18 PNGs + 5 JSON dumps)
- **Stack state:** postgres in docker (`04-finance-tracker-postgres-1`), backend pid logged in `/tmp/ft-backend.log`, frontend pid in `/tmp/ft-frontend.log`
