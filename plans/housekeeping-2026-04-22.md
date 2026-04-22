# Housekeeping Plan — 2026-04-22

## Overview
Clean up stranded state, remove tax from receipt OCR, harden API surface, and end-to-end verify the v4.0 build with a real Claude key. VPS deploy is explicitly out of scope.

## Architecture Decisions
- **Tax scope = OCR-only (Option A).** Stop extracting tax from receipts; keep DB columns + `tax_export.py` intact so historical data and year-end export still work. User can still toggle `is_tax_deductible` manually if needed. Rationale: zero data loss, narrow blast radius.
- **Rate limiting = per-user sliding window** using `slowapi` keyed on `current_user.id`. Target cap: **20 chat messages / 60s** and **2 OCR requests / 10s**. Configurable via env.
- **Bot-internal auth = shared-secret header.** Add `TELEGRAM_BOT_INTERNAL_SECRET` to `.env`; bot sends `X-Bot-Secret` header on internal calls; API validates via new dependency `require_bot_secret`. Retain `user_id` as body field but trust only after header check.
- **Stranded commits = one commit per logical group** (not one mega-commit).

## Task List

### Phase 0: Investigation (done)
- [x] Confirm API key present in `.env`
- [x] Audit branches (only stale `claude/ollama-receipt-ocr-2Fhc1`, already merged)
- [x] Map tax usage sites
- [x] Confirm `PendingReceipt` model matches migration `baeb5f1bd482`

### Phase 1: Environment + Git hygiene

**Task 1 — Flip OCR mode and sanity-check key**
- Acceptance: `.env` has `OCR_MODE=auto`; `curl -sH "x-api-key: $KEY" https://api.anthropic.com/v1/models | jq '.data[0].id'` returns a model id.
- Verification: key works; no commit (`.env` is gitignored).
- Files: `.env`
- Size: XS

**Task 2 — Delete merged feature branch**
- Acceptance: `claude/ollama-receipt-ocr-2Fhc1` gone locally and on remote. `git branch -a` shows only `main`.
- Verification: `git log --all --oneline` shows all of that branch's commits already reachable from `main`.
- Files: git refs only
- Size: XS

**Task 3 — Commit stranded work (grouped)**
- **3a** Add `PORTS.md` + `CLAUDE.md` tweak + `docker-compose.dev.yml` port reallocations (3000→3040, 8002→8040, 5432→5434) in one commit: `chore(ports): document and apply project-04 port allocation`.
- **3b** Add migration `baeb5f1bd482_add_pending_receipts_table_fix.py` in one commit: `fix(db): fixup migration for pending_receipts table`.
- **3c** Add `.claude/` project memory directory in one commit: `chore(memory): commit project .claude/ memory directory`.
- **3d** Ignore `.playwright-mcp/`, `e2e-screenshots/`, `e2e-test.mjs`, `Receipt-Examples 2/` via `.gitignore` in one commit: `chore(gitignore): ignore transient e2e artifacts`.
- Acceptance: `git status` clean.
- Verification: `git log --oneline -8` shows 4 new commits; tests still pass.
- Files: `.gitignore`, migration file, `.claude/*`, `PORTS.md`, `CLAUDE.md`, `docker-compose.dev.yml`
- Size: S

### Checkpoint A — git clean, ports documented
- [ ] `git status` clean
- [ ] Full backend+frontend test suites green
- [ ] User review before Phase 2

### Phase 2: Remove tax from receipt OCR (Option A)

**Task 4 — Strip tax extraction from OCR service**
- Acceptance:
  - `backend/src/app/services/ocr.py` prompts no longer request `tax_amount` or `subtotal`.
  - Tesseract path no longer returns `tax_amount` / `subtotal`.
  - `_TAX_PATTERNS` regex block removed.
  - Returned JSON shape: `{merchant_name, date, total_amount, currency, items, method, confidence}`. Category stays empty — categorization is still user-driven post-OCR (existing UX).
- Verification: unit test `test_ocr_no_tax` — mock Claude response, assert `tax_amount` key absent, `total_amount` present.
- Files: `backend/src/app/services/ocr.py`, `backend/tests/test_ocr.py` (new, or extend existing).
- Size: S

**Task 5 — Update ReceiptScanner UI**
- Acceptance: `ReceiptScanner.tsx` no longer renders Tax input; `result` state drops `tax` field; save payload omits `tax_amount`.
- Verification: vitest snapshot/unit passes; manual: scan → only Total + Merchant + Date + Category shown.
- Files: `frontend/src/components/ReceiptScanner.tsx`
- Size: S

**Task 6 — Keep DB/schema untouched, but default tax to 0 on create**
- Acceptance: `schemas/expense.py` and `routers/expenses.py` already default `tax_amount=0` — verify no breaking change. No migration needed.
- Verification: existing `test_expenses` still green.
- Files: none (verification only)
- Size: XS

### Checkpoint B — OCR simplified
- [ ] All tests pass
- [ ] Manually scan one receipt end-to-end, verify no Tax field in UI

### Phase 3: End-to-end smoke test (real Claude API)

**Task 7 — Boot stack and scan a real receipt**
- Acceptance: API up on 8040, frontend on 3040, DB on 5434. Upload one receipt from `Receipt-Examples/`; Claude returns merchant + total + date; saved as expense.
- Verification: request logged in API logs; expense row exists in DB.
- Files: runtime only
- Size: S

**Task 8 — AI Finance Chat smoke test**
- Acceptance: Log in; open `/chat`; send "What did I spend this month?"; get streaming response grounded in financial_context.
- Verification: `financial_context_json` populated on assistant message row.
- Files: runtime only
- Size: S

### Phase 4: Hardening

**Task 9 — Add rate limiting (slowapi)**
- Acceptance: `slowapi` installed; limits applied to `POST /api/v1/chat/conversations/{id}/messages` (20/min) and receipt OCR endpoint (2/10s). Exceeding returns 429.
- Verification: pytest test fires 21 requests, asserts final gets 429.
- Files: `backend/src/app/main.py`, chat/receipt routers, `backend/pyproject.toml`, `backend/tests/test_rate_limit.py`
- Size: M

**Task 10 — Secure Telegram bot internal auth**
- Acceptance: New env `TELEGRAM_BOT_INTERNAL_SECRET`; bot's httpx client sends `X-Bot-Secret`; API dependency `require_bot_secret` validates. `user_id` moves from query param to POST body but trust comes only from the header.
- Verification: pytest test — request without header → 401; with wrong secret → 401; with correct secret → 200.
- Files: `backend/src/app/config.py`, `backend/src/app/dependencies/auth.py` (add `require_bot_secret`), `backend/src/app/routers/telegram.py`, `backend/telegram_bot/main.py`, `.env.example`, `backend/tests/test_telegram.py`
- Size: M

### Checkpoint C — Hardening complete
- [ ] Rate limit test passes
- [ ] Bot auth test passes
- [ ] Full suite: 65+ backend tests / 24+ frontend tests pass

### Phase 5: Mobile app discussion (not coding yet)
**Task 11 — Present Capacitor vs Expo vs SwiftUI tradeoffs grounded in this codebase**
- Acceptance: Short written comparison with effort, code-reuse %, App Store path, recommended path for Armando's stack.
- Deliverable: conversation turn, not a file.

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Removing tax breaks existing tax export feature | Med | Keep DB columns + tax_export router; only remove from OCR flow |
| Claude key accidentally committed | High | `.env` already gitignored; sanity-check `git check-ignore .env` in Task 1 |
| Rate limit breaks chat for real users | Med | Cap is generous (20/min); make configurable via env `CHAT_RATE_LIMIT` |
| Bot auth change breaks prod bot | Med | Ship bot + API changes in same commit; no prod deploy this session |

## Open Questions
- Confirm **Option A** (OCR-only tax removal) vs Option B (full removal including DB columns + tax_export router). Recommend A.
- Rate-limit numbers — default to 20 chat msgs/min + 2 OCR/10s, or prefer tighter?
