# E2E Validation — 2026-04-22

## Scope
Full user-flow smoke test of Finance Tracker v4.0 against a real Claude API key,
driven through the live frontend (localhost:3040 → localhost:8040 → postgres:5434).

I take a screenshot at every significant state transition, then **actually open the PNG**
and validate it visually (not just assert DOM). A flow is only marked ✅ when:
1. The visible UI matches expectations, and
2. The resulting data cascades correctly into the next flow (e.g. expense → analytics → chat grounding).

## Test user
- **Name:** Claude Tester
- **Email:** claude@test.local
- **Password:** ClaudeTest2026!

## Test Data
Three manual expenses + one scanned receipt — sized so I know the totals by heart
and can cross-check them in analytics and chat.

| # | Amount | Category | Description | Source |
|---|--------|----------|-------------|--------|
| 1 | $5.50 | Dining | Coffee — Starbucks | Manual |
| 2 | $43.21 | Groceries | Whole Foods | Manual |
| 3 | $89.00 | Subscriptions | Netflix annual | Manual |
| 4 | $23.15 | Dining | Dunkin' receipt scan | OCR (Claude) |
|   | **$160.86** | **Total** | | |

## Flows (in dependency order)

### F1 — Registration & Auth
- Register "Claude Tester"
- Expect: auto-login → redirect to dashboard
- Screenshot: login page, post-register dashboard
- **Cascading assumption:** default categories get seeded (verified in F2)

### F2 — Categories
- View categories page → expect 15 default categories (Groceries, Dining, …, Other)
- **Cross-check:** matches the `_CATEGORY_LIST` constant in `ocr.py`

### F3 — Manual expenses (three entries)
- Quick-add each expense from the home screen
- Screenshot each add + the resulting expenses list
- **Cascading expectation:** expenses list shows all 3 with correct amount/category/date

### F4 — Receipt OCR scan (real Claude API)
- Upload `Receipt-Examples/dunkin-donuts.jpg`
- Wait for OCR to finish
- Verify: merchant="Dunkin'", total=~$23.15, date extracted
- **Negative assertion**: no "Tax" field visible in UI (our recent change)
- Confirm & save
- Screenshot each state: scan pre-upload, analyzing, review, saved, expenses list after

### F5 — Analytics
- Open analytics page
- Expect total-this-month = $160.86 (± cents)
- Expect Dining > Groceries > Subscriptions by category
- **Cascade check:** the 4 expenses I added/scanned all show up

### F6 — Debt tracker
- Add a credit card: Amex Gold, $500 balance, 18% APR, $25 min
- Add a loan: Car Loan, $15,000 balance, 5.5% APR, $350/mo, 48 months
- Open debt strategies
- Expect: Avalanche/Snowball comparison renders with reasonable payoff months
- **Cross-check math:** the quick-estimate shouldn't be silly (e.g., payoff < 0)

### F7 — AI Finance Chat
- Open `/chat`, create new conversation
- Send: "What did I spend the most on this month?"
- Expect streaming response that references **real numbers** from F3 + F4:
  - Mentions Dining as #1 (Starbucks $5.50 + Dunkin' $23.15 = $28.65)
  - Mentions Subscriptions $89 and Groceries $43.21
- **Critical validation:** the chat is grounded in *our* data, not hallucinations

### F8 — Rate limits (negative path)
- Hit `/receipts/scan` 3× quickly → 3rd should return 429
- Hit chat endpoint 21× → 21st should return 429
- Uses direct fetch to API rather than UI (faster, more precise)

### F9 — Settings & Telegram link
- Settings page loads; Telegram section renders
- Generate link code, verify code shown on page

### F10 — Logout
- Logout → redirect to login
- Refresh → still on login (session cleared)

## Evidence format
All PNGs saved to `docs/e2e-validation/screenshots/`.
Each flow section in `REPORT.md` links to its screenshots and includes:
- Expected state
- Observed state (from visual read of the PNG)
- Pass/Fail

## Stop conditions
If any critical flow fails, I stop, report, fix or flag, and re-run from that point.
Non-critical issues (cosmetic, edge-case) get logged but don't block the next flow.
