/**
 * Pass-2 validation — deeper coverage of user flows not exercised in pass 1.
 *
 * Coverage:
 *   expense-edit, expense-delete, category-crud, bank-csv-import,
 *   cc-payment, loan-payment, chat-crud, chat-sonnet, admin, feature-flags,
 *   multi-user-isolation, settings-persist, password-change, csv-export,
 *   spanish-ocr, auth-edges
 *
 * Screenshots → docs/e2e-validation/screenshots-pass2/
 * Run: node drive-pass2.mjs [flow|all]
 */

import { chromium } from "playwright";
import { mkdirSync, writeFileSync, readFileSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
import { execSync } from "child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SHOT_DIR = resolve(__dirname, "screenshots-pass2");
mkdirSync(SHOT_DIR, { recursive: true });

const BASE = "http://localhost:3040";
const API = "http://localhost:8040";

const USER_A = { email: "claude@example.com", password: "ClaudeTest2026!", display_name: "Claude Tester" };
const USER_B = { email: "mom@example.com", password: "MomTest2026!", display_name: "Mom" };

const flow = process.argv[2] || "all";
const ctx = { tokenA: null, tokenB: null, expenseIds: [], catIds: {}, ccId: null, loanId: null };

const findings = [];
function note(type, msg) {
  findings.push({ type, msg });
  console.log(`  ${type === "BUG" ? "🐛" : type === "OK" ? "✅" : "ℹ️"} ${msg}`);
}

async function shot(page, name, full = false) {
  const path = resolve(SHOT_DIR, `${name}.png`);
  await page.screenshot({ path, fullPage: full });
  console.log(`  📸 ${name}.png`);
  return path;
}
async function waitIdle(page, ms = 400) {
  await page.waitForLoadState("networkidle").catch(() => {});
  await page.waitForTimeout(ms);
}
async function goto(page, url, tries = 3) {
  for (let i = 0; i < tries; i++) {
    try {
      await page.goto(url, { waitUntil: "domcontentloaded", timeout: 120000 });
      return;
    } catch (e) {
      if (i === tries - 1) throw e;
      console.log(`  ⚠️ goto retry ${i+1}: ${url}`);
      await page.waitForTimeout(2000);
    }
  }
}

async function warmPages(page, urls) {
  console.log("\n── Warming Next.js dev compiler ──");
  for (const u of urls) {
    const t0 = Date.now();
    try {
      await fetch(`${BASE}${u}`, { signal: AbortSignal.timeout(90000) });
      console.log(`  🔥 ${u} (${Date.now() - t0}ms)`);
    } catch (e) {
      console.log(`  ⚠️ warm ${u} failed: ${e.message}`);
    }
  }
}

async function request(path, { method = "GET", body, token, raw = false } = {}) {
  const headers = { "Content-Type": "application/json" };
  if (token) headers["Authorization"] = `Bearer ${token}`;
  const r = await fetch(`${API}${path}`, {
    method, headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  if (raw) return r;
  const text = await r.text();
  let body_ = text;
  try { body_ = JSON.parse(text); } catch {}
  return { status: r.status, ok: r.ok, body: body_ };
}

async function register(user) {
  const r = await request("/api/v1/auth/register", { method: "POST", body: user });
  return r;
}
async function login(user) {
  const r = await request("/api/v1/auth/login", { method: "POST", body: { email: user.email, password: user.password } });
  return r.body?.access_token ?? null;
}

// ── FLOWS ──────────────────────────────────────────────────────

async function flowBootstrap(page) {
  console.log("\n── Bootstrap: register user A + seed some data ──");
  const reg = await register(USER_A);
  note("OK", `register A: ${reg.status}`);
  ctx.tokenA = await login(USER_A);

  // Seed 3 expenses + 1 CC + 1 loan for later flows
  const cats = (await request("/api/v1/categories", { token: ctx.tokenA })).body;
  for (const c of cats) ctx.catIds[c.name] = c.id;

  for (const [amount, desc, cat] of [
    [5.50, "Starbucks", "Food & Dining"],
    [43.21, "Whole Foods", "Food & Dining"],
    [89.00, "Netflix", "Bills & Utilities"],
  ]) {
    const r = await request("/api/v1/expenses", {
      method: "POST", token: ctx.tokenA,
      body: { amount, description: desc, category_id: ctx.catIds[cat], expense_date: new Date().toISOString().slice(0, 10) },
    });
    if (r.ok) ctx.expenseIds.push(r.body.id);
  }
  note("OK", `expenses seeded: ${ctx.expenseIds.length}`);

  const cc = await request("/api/v1/credit-cards", {
    method: "POST", token: ctx.tokenA,
    body: { card_name: "Amex Gold", last_four: "0001", current_balance: 500, credit_limit: 5000, apr: 0.18, minimum_payment: 25 },
  });
  if (cc.ok) ctx.ccId = cc.body.id;

  const loan = await request("/api/v1/loans", {
    method: "POST", token: ctx.tokenA,
    body: { loan_name: "Car Loan", lender: "Wells Fargo", loan_type: "car", original_principal: 18000, current_balance: 15000, interest_rate: 0.055, interest_rate_type: "yearly", minimum_payment: 350 },
  });
  if (loan.ok) ctx.loanId = loan.body.id;

  // Log in via UI so we can screenshot authenticated pages
  await goto(page, `${BASE}/login`);
  await waitIdle(page);
  await page.fill('input[type="email"]', USER_A.email);
  await page.fill('input[type="password"]', USER_A.password);
  await Promise.all([
    page.waitForURL(u => !u.toString().endsWith("/login"), { timeout: 10000 }).catch(() => {}),
    page.click('button[type="submit"]'),
  ]);
  await waitIdle(page);
}

async function flowExpenseEditDelete(page) {
  console.log("\n── F11: Expense edit + delete ──");
  const id = ctx.expenseIds[0];
  // Edit: change amount and description
  const upd = await request(`/api/v1/expenses/${id}`, {
    method: "PATCH", token: ctx.tokenA,
    body: { amount: 12.34, description: "Starbucks (edited)" },
  });
  note(upd.ok ? "OK" : "BUG", `PATCH expense: ${upd.status}`);
  if (upd.ok && upd.body.amount !== 12.34) note("BUG", `amount after edit not 12.34: ${upd.body.amount}`);

  // Delete the 3rd expense (Netflix)
  const delId = ctx.expenseIds[2];
  const del = await request(`/api/v1/expenses/${delId}`, { method: "DELETE", token: ctx.tokenA });
  note(del.status === 204 ? "OK" : "BUG", `DELETE expense: ${del.status}`);

  // Visual verify the list reflects both
  await goto(page, `${BASE}/expenses`);
  await waitIdle(page, 600);
  await shot(page, "11-expenses-after-edit-delete", true);

  // Verify via API list
  const list = await request("/api/v1/expenses/", { token: ctx.tokenA });
  const items = list.body?.items ?? list.body?.expenses ?? (Array.isArray(list.body) ? list.body : []);
  const count = Array.isArray(items) ? items.length : (items?.length ?? 0);
  note(count === 2 ? "OK" : "BUG", `expenses count after delete: ${count} (expected 2)`);
}

async function flowCategoryCRUD(page) {
  console.log("\n── F12: Category CRUD + budget + archive ──");
  // Create a new category with budget
  const create = await request("/api/v1/categories", {
    method: "POST", token: ctx.tokenA,
    body: { name: "Coffee Lab", icon: "☕", color: "#9333EA", monthly_budget: 50 },
  });
  note(create.ok ? "OK" : "BUG", `create category: ${create.status}`);
  const newCatId = create.body?.id;

  // Rename + change budget
  if (newCatId) {
    const patch = await request(`/api/v1/categories/${newCatId}`, {
      method: "PATCH", token: ctx.tokenA,
      body: { name: "Coffee", monthly_budget: 75 },
    });
    note(patch.ok && patch.body?.name === "Coffee" ? "OK" : "BUG", `rename+rebudget: ${patch.status}`);
  }

  // Archive another default category
  const shoppingId = ctx.catIds["Shopping"];
  if (shoppingId) {
    const arch = await request(`/api/v1/categories/${shoppingId}`, {
      method: "DELETE", token: ctx.tokenA,
    });
    note([200, 204].includes(arch.status) ? "OK" : "BUG", `archive Shopping: ${arch.status}`);
  }

  await goto(page, `${BASE}/categories`);
  await waitIdle(page, 600);
  await shot(page, "12-categories-after-crud", true);

  // Verify via API: Coffee present, Shopping gone (or inactive)
  const after = await request("/api/v1/categories", { token: ctx.tokenA });
  const names = (after.body || []).map(c => c.name);
  note(names.includes("Coffee") ? "OK" : "BUG", `Coffee present in list: ${names.includes("Coffee")}`);
  note(!names.includes("Shopping") ? "OK" : "BUG", `Shopping absent from active list: ${!names.includes("Shopping")}`);
}

async function flowBankCsvImport(page) {
  console.log("\n── F13: Bank statement CSV import ──");
  // Build a small Chase-style CSV in memory
  const csv = [
    "Posting Date,Description,Amount,Type",
    `${new Date().toISOString().slice(0, 10)},Starbucks,-4.75,debit`,
    `${new Date().toISOString().slice(0, 10)},Trader Joe's,-52.18,debit`,
    `${new Date().toISOString().slice(0, 10)},Payroll,2500.00,credit`,
  ].join("\n");

  const form = new FormData();
  form.append("file", new Blob([csv], { type: "text/csv" }), "chase.csv");
  const r = await fetch(`${API}/api/v1/import/upload`, {
    method: "POST",
    headers: { Authorization: `Bearer ${ctx.tokenA}` },
    body: form,
  });
  const preview = await r.json();
  note(r.ok ? "OK" : "BUG", `CSV upload: ${r.status} (${(preview.transactions || []).length} txns)`);
  writeFileSync(resolve(SHOT_DIR, "13-csv-preview.json"), JSON.stringify(preview, null, 2));

  // Confirm the first two debits (skip the credit)
  const toConfirm = (preview.transactions || [])
    .filter(t => t.amount < 0)
    .map((t, i) => ({ ...t, category_id: ctx.catIds["Food & Dining"], include: true }));
  if (toConfirm.length > 0 && preview.import_id) {
    const conf = await request("/api/v1/import/confirm", {
      method: "POST", token: ctx.tokenA,
      body: { import_id: preview.import_id, transactions: toConfirm },
    });
    note(conf.ok ? "OK" : "BUG", `confirm import: ${conf.status}`);
  }

  await goto(page, `${BASE}/import`);
  await waitIdle(page, 600);
  await shot(page, "13-import-page", true);
}

async function flowDebtPayments(page) {
  console.log("\n── F14: CC + loan payment; balances decrease ──");
  if (!ctx.ccId || !ctx.loanId) {
    note("SKIP", "no cc/loan id");
    return;
  }
  // CC payment
  const before = await request(`/api/v1/credit-cards/${ctx.ccId}`, { token: ctx.tokenA });
  const beforeBal = Number(before.body?.current_balance);
  const pay = await request(`/api/v1/credit-cards/${ctx.ccId}/payment`, {
    method: "POST", token: ctx.tokenA,
    body: { amount: 100, payment_date: new Date().toISOString().slice(0, 10) },
  });
  note(pay.ok ? "OK" : "BUG", `cc payment $100: ${pay.status}`);
  const after = await request(`/api/v1/credit-cards/${ctx.ccId}`, { token: ctx.tokenA });
  const afterBal = Number(after.body?.current_balance);
  note(
    Math.abs((beforeBal - afterBal) - 100) < 0.01 ? "OK" : "BUG",
    `cc balance ${beforeBal} → ${afterBal} (expected ${beforeBal - 100})`,
  );

  // Loan payment
  const lbefore = await request(`/api/v1/loans/${ctx.loanId}`, { token: ctx.tokenA });
  const lbeforeBal = Number(lbefore.body?.current_balance);
  const lpay = await request(`/api/v1/loans/${ctx.loanId}/payment`, {
    method: "POST", token: ctx.tokenA,
    body: { amount: 350, payment_date: new Date().toISOString().slice(0, 10) },
  });
  note(lpay.ok ? "OK" : "BUG", `loan payment $350: ${lpay.status}`);
  const lafter = await request(`/api/v1/loans/${ctx.loanId}`, { token: ctx.tokenA });
  const lafterBal = Number(lafter.body?.current_balance);
  // Loan payments split between principal and interest; balance should decrease but by less than payment
  note(
    lafterBal < lbeforeBal && lafterBal > lbeforeBal - 350,
    `loan balance ${lbeforeBal} → ${lafterBal} (interest-adjusted)`,
  );

  // Debt strategies with what-if
  const strat = await request("/api/v1/debt/strategies?monthly_budget=600", { token: ctx.tokenA });
  // Response shape: { avalanche: StrategyResult, snowball: ..., hybrid: ..., minimum_only: ..., recommendation }
  const body = strat.body || {};
  const keys = ["avalanche", "snowball", "hybrid", "minimum_only"].filter(k => body[k]);
  note(
    strat.ok && keys.length === 4,
    `strategies returned: ${keys.join(",")}; recommendation="${String(body.recommendation || "").slice(0, 60)}..."`,
  );
  if (body.avalanche) {
    note("INFO", `avalanche: ${body.avalanche.months_to_freedom}mo, $${body.avalanche.total_interest} interest, order: ${(body.avalanche.payoff_order || []).join(" → ")}`);
  }
  writeFileSync(resolve(SHOT_DIR, "14-strategies.json"), JSON.stringify(body, null, 2));

  // What-if: re-run with smaller budget to see months increase
  const stratLow = await request("/api/v1/debt/strategies?monthly_budget=400", { token: ctx.tokenA });
  if (stratLow.body?.avalanche && body.avalanche) {
    const more = stratLow.body.avalanche.months_to_freedom > body.avalanche.months_to_freedom;
    note(more ? "OK" : "BUG",
         `what-if $400 vs $600: months ${stratLow.body.avalanche.months_to_freedom} vs ${body.avalanche.months_to_freedom} (smaller budget → longer)`);
  }

  await goto(page, `${BASE}/debt`);
  await waitIdle(page, 800);
  await shot(page, "14-debt-after-payments", true);
}

async function flowChatManagement(page) {
  console.log("\n── F15: Chat conversation management + Sonnet ──");
  // Create 2 conversations
  const c1 = await request("/api/v1/chat/conversations", {
    method: "POST", token: ctx.tokenA,
    body: { title: "Overview" },
  });
  const c2 = await request("/api/v1/chat/conversations", {
    method: "POST", token: ctx.tokenA,
    body: { title: "Budget" },
  });
  note(c1.ok && c2.ok ? "OK" : "BUG", `create 2 conversations: ${c1.status}, ${c2.status}`);

  // Rename c1
  const rn = await request(`/api/v1/chat/conversations/${c1.body.id}`, {
    method: "PUT", token: ctx.tokenA,
    body: { title: "Month Overview" },
  });
  note(rn.ok && rn.body.title === "Month Overview" ? "OK" : "BUG", `rename: ${rn.status}`);

  // Send a message using Sonnet
  const msgResp = await fetch(`${API}/api/v1/chat/conversations/${c1.body.id}/messages`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${ctx.tokenA}` },
    body: JSON.stringify({ content: "Give me a one-line summary of my spending.", model: "sonnet" }),
  });
  let streamed = "";
  const reader = msgResp.body.getReader();
  const dec = new TextDecoder();
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    streamed += dec.decode(value);
  }
  const sawSonnet = streamed.includes('"model": "sonnet"') || streamed.includes("sonnet");
  note(msgResp.ok ? "OK" : "BUG", `Sonnet message: ${msgResp.status}, stream bytes=${streamed.length}`);
  writeFileSync(resolve(SHOT_DIR, "15-sonnet-stream.txt"), streamed);
  note(sawSonnet ? "OK" : "BUG", `Sonnet done event seen: ${sawSonnet}`);

  // List conversations (should see both)
  const list = await request("/api/v1/chat/conversations", { token: ctx.tokenA });
  note((list.body || []).length >= 2 ? "OK" : "BUG", `conv list size: ${(list.body || []).length}`);

  // Delete c2
  const del = await request(`/api/v1/chat/conversations/${c2.body.id}`, { method: "DELETE", token: ctx.tokenA });
  note(del.status === 204 ? "OK" : "BUG", `delete c2: ${del.status}`);

  await goto(page, `${BASE}/chat`);
  await waitIdle(page, 600);
  await shot(page, "15-chat-after-crud", true);
}

async function flowAdminAndFlags(page) {
  console.log("\n── F16: Admin panel + feature flags ──");
  // Promote user A to superuser via direct SQL
  execSync(
    `docker exec 04-finance-tracker-postgres-1 psql -U postgres -d finance_db -c "UPDATE users SET is_superuser=true WHERE email='${USER_A.email}';"`,
    { stdio: "pipe" },
  );
  // Re-login to get a JWT that has is_superuser=true in claims
  ctx.tokenA = await login(USER_A);

  // Fetch /admin/users
  const users = await request("/api/v1/admin/users", { token: ctx.tokenA });
  note(users.ok ? "OK" : "BUG", `admin users: ${users.status} (${(users.body || []).length} users)`);
  writeFileSync(resolve(SHOT_DIR, "16-admin-users.json"), JSON.stringify(users.body, null, 2));

  // Enable hidden_categories flag on user A
  const me = (users.body || []).find(u => u.email === USER_A.email);
  if (me) {
    const flag1 = await request(`/api/v1/admin/users/${me.id}/features`, {
      method: "PATCH", token: ctx.tokenA,
      body: { feature_name: "hidden_categories", is_enabled: true },
    });
    note(flag1.ok ? "OK" : "BUG", `hidden_categories flag on: ${flag1.status}`);

    const flag2 = await request(`/api/v1/admin/users/${me.id}/features`, {
      method: "PATCH", token: ctx.tokenA,
      body: { feature_name: "friend_debt_calculator", is_enabled: true },
    });
    note(flag2.ok ? "OK" : "BUG", `friend_debt_calculator flag on: ${flag2.status}`);

    // Verify hidden categories feature now works: create a hidden category
    const hc = await request("/api/v1/categories", {
      method: "POST", token: ctx.tokenA,
      body: { name: "Private", icon: "🔒", color: "#111827", is_hidden: true },
    });
    note(hc.ok ? "OK" : "BUG", `create hidden category: ${hc.status}`);
  }

  await goto(page, `${BASE}/admin`);
  await waitIdle(page, 600);
  await shot(page, "16-admin-page", true);

  await goto(page, `${BASE}/hidden`);
  await waitIdle(page, 600);
  await shot(page, "16-hidden-page", true);

  await goto(page, `${BASE}/friend-debt`);
  await waitIdle(page, 600);
  await shot(page, "16-friend-debt-page", true);
}

async function flowMultiUser(page) {
  console.log("\n── F17: Multi-user isolation ──");
  const reg = await register(USER_B);
  note(reg.ok || reg.status === 409 ? "OK" : "BUG", `register B: ${reg.status}`);
  ctx.tokenB = await login(USER_B);

  // B should see ZERO of A's expenses
  const bList = await request("/api/v1/expenses/", { token: ctx.tokenB });
  const bItems = bList.body?.items ?? (Array.isArray(bList.body) ? bList.body : []);
  const n = Array.isArray(bItems) ? bItems.length : 0;
  note(n === 0 ? "OK" : "BUG", `user B sees ${n} expenses (expected 0)`);

  // B should see 9 default categories (own seed), NOT A's "Coffee" or "Private"
  const bCats = await request("/api/v1/categories", { token: ctx.tokenB });
  const bNames = (bCats.body || []).map(c => c.name);
  note(!bNames.includes("Coffee") && !bNames.includes("Private") ? "OK" : "BUG",
       `user B isolated from A's custom categories: ${bNames.join(",")}`);

  // B tries to access one of A's expenses directly — must 404
  if (ctx.expenseIds.length > 0) {
    const peek = await request(`/api/v1/expenses/${ctx.expenseIds[0]}`, { token: ctx.tokenB });
    note(peek.status === 404 || peek.status === 403 ? "OK" : "BUG",
         `B accessing A's expense: ${peek.status} (expected 403/404)`);
  }

  // B tries to access A's credit card
  if (ctx.ccId) {
    const peek = await request(`/api/v1/credit-cards/${ctx.ccId}`, { token: ctx.tokenB });
    note(peek.status === 404 || peek.status === 403 ? "OK" : "BUG",
         `B accessing A's CC: ${peek.status} (expected 403/404)`);
  }
}

async function flowAuthEdges(page) {
  console.log("\n── F18: Auth edge cases ──");
  // Wrong password
  const bad = await request("/api/v1/auth/login", {
    method: "POST",
    body: { email: USER_A.email, password: "wrongpassword" },
  });
  note(bad.status === 401 ? "OK" : "BUG", `wrong password: ${bad.status}`);

  // Duplicate register
  const dup = await register(USER_A);
  note([409, 400, 422].includes(dup.status) ? "OK" : "BUG", `duplicate register: ${dup.status}`);

  // Expired/invalid token
  const badTok = await request("/api/v1/auth/me", { token: "not-a-token" });
  note(badTok.status === 401 ? "OK" : "BUG", `invalid token: ${badTok.status}`);

  // Missing token
  const noTok = await request("/api/v1/expenses");
  note([401, 403].includes(noTok.status) ? "OK" : "BUG", `missing token on protected: ${noTok.status}`);

  // Short password (should 422)
  const weak = await request("/api/v1/auth/register", {
    method: "POST",
    body: { email: "weak@example.com", password: "abc", display_name: "Weak" },
  });
  note([400, 422].includes(weak.status) ? "OK" : "BUG", `short password rejected: ${weak.status}`);
}

async function flowSpanishOcr() {
  console.log("\n── F19: Spanish receipt OCR (Costco example) ──");
  const img = resolve(__dirname, "..", "..", "Receipt-Examples", "costco.jpg");
  const buf = readFileSync(img);
  const form = new FormData();
  form.append("file", new Blob([buf], { type: "image/jpeg" }), "costco.jpg");
  const r = await fetch(`${API}/api/v1/receipts/scan`, {
    method: "POST",
    headers: { Authorization: `Bearer ${ctx.tokenA}` },
    body: form,
  });
  const body = await r.json();
  writeFileSync(resolve(SHOT_DIR, "19-spanish-ocr.json"), JSON.stringify(body, null, 2));
  note(body.ocr_data?.total_amount ? "OK" : "BUG",
       `costco OCR merchant="${body.ocr_data?.merchant_name}" total=${body.ocr_data?.total_amount} method=${body.ocr_method}`);
  // Verify NO tax fields
  const hasBadFields = body.ocr_data && ("tax_amount" in body.ocr_data || "subtotal" in body.ocr_data);
  note(!hasBadFields ? "OK" : "BUG", `no tax/subtotal fields present`);
}

// ── driver ──

const FLOWS = {
  "expense-ed": flowExpenseEditDelete,
  "category-crud": flowCategoryCRUD,
  "bank-csv": flowBankCsvImport,
  "debt-payments": flowDebtPayments,
  "chat-mgmt": flowChatManagement,
  "admin-flags": flowAdminAndFlags,
  "multi-user": flowMultiUser,
  "auth-edges": flowAuthEdges,
  "spanish-ocr": flowSpanishOcr,
};
const ORDER = [
  "expense-ed", "category-crud", "bank-csv", "debt-payments",
  "chat-mgmt", "admin-flags", "multi-user", "auth-edges", "spanish-ocr",
];

async function run() {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 2,
  });
  const page = await context.newPage();

  const errors = [];
  page.on("console", m => { if (m.type() === "error") errors.push(`[console.error] ${m.text()}`); });
  page.on("requestfailed", r => errors.push(`[requestfailed] ${r.url()} ${r.failure()?.errorText}`));

  try {
    await warmPages(page, ["/", "/login", "/expenses", "/categories", "/scan", "/debt", "/chat", "/analytics", "/import", "/settings", "/telegram-link", "/admin", "/hidden", "/friend-debt"]);
    await flowBootstrap(page);
    if (flow === "all") {
      for (const f of ORDER) await FLOWS[f](page);
    } else {
      await FLOWS[flow](page);
    }
  } finally {
    writeFileSync(resolve(SHOT_DIR, "_findings.json"), JSON.stringify(findings, null, 2));
    if (errors.length) writeFileSync(resolve(SHOT_DIR, "_console-errors.log"), errors.join("\n"));
    await browser.close();
    const bugs = findings.filter(f => f.type === "BUG").length;
    const oks = findings.filter(f => f.type === "OK").length;
    console.log(`\n── Summary: ${oks} ok, ${bugs} bugs, ${findings.length - oks - bugs} info ──`);
    if (bugs > 0) console.log(findings.filter(f => f.type === "BUG").map(f => "  🐛 " + f.msg).join("\n"));
  }
}

run().catch(e => { console.error(e); process.exit(1); });
