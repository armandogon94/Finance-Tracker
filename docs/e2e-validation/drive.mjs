/**
 * E2E validation driver. Drives the app as a real user would, taking a
 * screenshot at every meaningful state transition. PNGs go to
 * docs/e2e-validation/screenshots/.
 *
 * Run individual flows: node drive.mjs <flow>
 *   flows: register, categories, expenses, scan, analytics, debt, chat, rate, settings, logout, all
 */

import { chromium } from "playwright";
import { mkdirSync, writeFileSync, readFileSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SHOT_DIR = resolve(__dirname, "screenshots");
mkdirSync(SHOT_DIR, { recursive: true });

const BASE = "http://localhost:3040";
const API = "http://localhost:8040";
const USER = {
  email: "claude@example.com",
  password: "ClaudeTest2026!",
  display_name: "Claude Tester",
};

const flow = process.argv[2] || "all";

const ctx = {
  token: null,
  expenseIds: [],
};

// ── helpers ────────────────────────────────────────────────────────

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

async function apiFetch(path, opts = {}) {
  const url = path.startsWith("http") ? path : `${API}${path}`;
  const headers = { "Content-Type": "application/json", ...(opts.headers || {}) };
  if (ctx.token) headers["Authorization"] = `Bearer ${ctx.token}`;
  const r = await fetch(url, { ...opts, headers });
  const body = await r.text();
  let parsed = body;
  try { parsed = JSON.parse(body); } catch {}
  return { status: r.status, body: parsed, ok: r.ok };
}

// ── flows ─────────────────────────────────────────────────────────

async function flowRegister(page) {
  console.log("\n── F1: Register + Auth ──");
  await page.goto(BASE);
  await waitIdle(page);
  await shot(page, "01-landing");

  // Reset user if exists (idempotent re-run) — delete via direct DB later if needed.
  // Try register via API first to get the token path simpler.
  const reg = await apiFetch("/api/v1/auth/register", {
    method: "POST",
    body: JSON.stringify(USER),
  });
  console.log("  register:", reg.status, reg.ok ? "created" : reg.body);

  // Now log in through the UI so we exercise the real browser path
  await page.goto(`${BASE}/login`);
  await waitIdle(page);
  await shot(page, "02-login-page");

  await page.fill('input[type="email"], input[name="email"]', USER.email);
  await page.fill('input[type="password"], input[name="password"]', USER.password);
  await shot(page, "03-login-filled");

  await Promise.all([
    page.waitForURL(u => !u.toString().endsWith("/login"), { timeout: 10000 }).catch(() => {}),
    page.click('button[type="submit"], button:has-text("Sign in"), button:has-text("Log in")'),
  ]);
  await waitIdle(page);
  await shot(page, "04-post-login-home", true);

  // Capture token for API testing
  ctx.token = await page.evaluate(() => localStorage.getItem("access_token"));
  console.log("  token:", ctx.token ? `${ctx.token.slice(0, 24)}...` : "MISSING");
}

async function flowCategories(page) {
  console.log("\n── F2: Categories ──");
  await page.goto(`${BASE}/categories`);
  await waitIdle(page);
  await shot(page, "10-categories-list", true);

  const cats = await apiFetch("/api/v1/categories");
  const names = Array.isArray(cats.body) ? cats.body.map(c => c.name) : [];
  console.log("  categories:", names.join(", "));
  writeFileSync(resolve(SHOT_DIR, "10-categories.json"), JSON.stringify(cats.body, null, 2));
}

async function flowExpenses(page) {
  console.log("\n── F3: Manual expense entries ──");
  await page.goto(BASE);
  await waitIdle(page);
  await shot(page, "20-home-empty", true);

  // Resolve category ids
  const cats = await apiFetch("/api/v1/categories");
  const byName = Object.fromEntries((cats.body || []).map(c => [c.name.toLowerCase(), c.id]));

  const exps = [
    { amount: 5.50, description: "Coffee — Starbucks", category: "food & dining" },
    { amount: 43.21, description: "Whole Foods", category: "food & dining" },
    { amount: 89.00, description: "Netflix annual", category: "bills & utilities" },
  ];

  for (const e of exps) {
    const resp = await apiFetch("/api/v1/expenses", {
      method: "POST",
      body: JSON.stringify({
        amount: e.amount,
        description: e.description,
        category_id: byName[e.category],
        expense_date: new Date().toISOString().slice(0, 10),
      }),
    });
    console.log(`  add ${e.description}:`, resp.status);
    if (resp.ok) ctx.expenseIds.push(resp.body.id);
  }

  await page.goto(`${BASE}/expenses`);
  await waitIdle(page, 800);
  await shot(page, "21-expenses-list", true);
}

async function flowScan(page) {
  console.log("\n── F4: Receipt OCR scan (real Claude) ──");
  const img = resolve(__dirname, "..", "..", "Receipt-Examples", "dunkin-donuts.jpg");

  // Upload via multipart to backend
  const buf = readFileSync(img);
  const form = new FormData();
  form.append("file", new Blob([buf], { type: "image/jpeg" }), "dunkin-donuts.jpg");
  const r = await fetch(`${API}/api/v1/receipts/scan`, {
    method: "POST",
    headers: { Authorization: `Bearer ${ctx.token}` },
    body: form,
  });
  const scanBody = await r.json();
  console.log("  scan status:", r.status);
  console.log("  ocr method:", scanBody.ocr_method);
  console.log("  merchant:", scanBody.ocr_data?.merchant_name);
  console.log("  total:", scanBody.ocr_data?.total_amount);
  writeFileSync(resolve(SHOT_DIR, "30-scan-response.json"), JSON.stringify(scanBody, null, 2));

  // Visit /scan to see the UI
  await page.goto(`${BASE}/scan`);
  await waitIdle(page);
  await shot(page, "31-scan-page", true);

  // Persist the OCR result as an actual expense
  if (scanBody.ocr_data?.total_amount) {
    const cats = await apiFetch("/api/v1/categories");
    const byName = Object.fromEntries((cats.body || []).map(c => [c.name.toLowerCase(), c.id]));
    const catId = byName[String(scanBody.ocr_data.category_suggestion || "dining").toLowerCase()]
      || byName["dining"];

    const conf = await fetch(`${API}/api/v1/receipts/confirm`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${ctx.token}`,
      },
      body: JSON.stringify({
        temp_id: scanBody.temp_id,
        image_path: scanBody.image_path,
        thumbnail_path: scanBody.thumbnail_path,
        file_size: scanBody.file_size,
        category_id: catId,
        amount: scanBody.ocr_data.total_amount,
        currency: scanBody.ocr_data.currency || "USD",
        merchant_name: scanBody.ocr_data.merchant_name,
        expense_date: scanBody.ocr_data.date || new Date().toISOString().slice(0, 10),
        ocr_data: scanBody.ocr_data,
        ocr_method: scanBody.ocr_method,
      }),
    });
    console.log("  confirm status:", conf.status);
  }

  await page.goto(`${BASE}/expenses`);
  await waitIdle(page, 500);
  await shot(page, "32-expenses-after-scan", true);
}

async function flowAnalytics(page) {
  console.log("\n── F5: Analytics ──");
  await page.goto(`${BASE}/analytics`);
  await waitIdle(page, 1200);
  await shot(page, "40-analytics-month", true);

  // Direct API sanity-check
  const today = new Date();
  const start = new Date(today.getFullYear(), today.getMonth(), 1).toISOString().slice(0, 10);
  const end = today.toISOString().slice(0, 10);
  const cat = await apiFetch(`/api/v1/analytics/by-category?start_date=${start}&end_date=${end}`);
  writeFileSync(resolve(SHOT_DIR, "40-analytics-by-category.json"), JSON.stringify(cat.body, null, 2));
  console.log("  by-category entries:", cat.body?.data?.length ?? 0);
}

async function flowDebt(page) {
  console.log("\n── F6: Debt tracker ──");

  const cc = await apiFetch("/api/v1/credit-cards", {
    method: "POST",
    body: JSON.stringify({
      card_name: "Amex Gold",
      last_four: "0001",
      current_balance: 500,
      credit_limit: 5000,
      apr: 0.18,
      minimum_payment: 25,
    }),
  });
  console.log("  add CC:", cc.status);

  const loan = await apiFetch("/api/v1/loans", {
    method: "POST",
    body: JSON.stringify({
      loan_name: "Car Loan",
      lender: "Wells Fargo",
      loan_type: "car",
      original_principal: 18000,
      current_balance: 15000,
      interest_rate: 0.055,
      interest_rate_type: "yearly",
      minimum_payment: 350,
    }),
  });
  console.log("  add loan:", loan.status);

  await page.goto(`${BASE}/debt`);
  await waitIdle(page, 800);
  await shot(page, "50-debt-overview", true);

  const strat = await apiFetch("/api/v1/debt/strategies?monthly_budget=500");
  writeFileSync(resolve(SHOT_DIR, "50-debt-strategies.json"), JSON.stringify(strat.body, null, 2));
}

async function flowChat(page) {
  console.log("\n── F7: AI Finance Chat ──");
  await page.goto(`${BASE}/chat`);
  await waitIdle(page, 600);
  await shot(page, "60-chat-empty", true);

  // Create conversation via API and send message
  const conv = await apiFetch("/api/v1/chat/conversations", {
    method: "POST",
    body: JSON.stringify({ title: "Month overview" }),
  });
  console.log("  conversation:", conv.status, conv.body?.id);

  const msgRes = await fetch(`${API}/api/v1/chat/conversations/${conv.body.id}/messages`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${ctx.token}`,
    },
    body: JSON.stringify({
      content: "What did I spend the most on this month?",
      model: "haiku",
    }),
  });
  const reader = msgRes.body.getReader();
  const decoder = new TextDecoder();
  let full = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    full += decoder.decode(value);
  }
  console.log("  stream bytes:", full.length);
  writeFileSync(resolve(SHOT_DIR, "60-chat-stream.txt"), full);

  // Re-visit chat UI to see the persisted conversation
  await page.goto(`${BASE}/chat`);
  await waitIdle(page, 800);
  await shot(page, "61-chat-with-conversation", true);
}

async function flowRate() {
  console.log("\n── F8: Rate limits ──");

  // OCR: 3 rapid scans, expect the 3rd to 429
  const img = resolve(__dirname, "..", "..", "Receipt-Examples", "dunkin-donuts.jpg");
  const buf = readFileSync(img);
  const results = [];
  for (let i = 0; i < 3; i++) {
    const form = new FormData();
    form.append("file", new Blob([buf], { type: "image/jpeg" }), "dunkin-donuts.jpg");
    const r = await fetch(`${API}/api/v1/receipts/scan`, {
      method: "POST",
      headers: { Authorization: `Bearer ${ctx.token}` },
      body: form,
    });
    results.push(r.status);
  }
  console.log("  OCR burst statuses:", results);

  // Chat: 23 rapid sends with early cancel so we don't drain the asyncpg pool
  // Expect: first 20 = 200, then 429s kick in
  const conv = await apiFetch("/api/v1/chat/conversations", {
    method: "POST",
    body: JSON.stringify({ title: "rate-limit burst" }),
  });
  const chatStatuses = [];
  for (let i = 0; i < 23; i++) {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 1500); // kill stream after 1.5s
    try {
      const r = await fetch(`${API}/api/v1/chat/conversations/${conv.body.id}/messages`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${ctx.token}`,
        },
        body: JSON.stringify({ content: "ping " + i, model: "haiku" }),
        signal: ctl.signal,
      });
      chatStatuses.push(r.status);
      try { await r.body.cancel(); } catch {}
    } catch {
      chatStatuses.push("aborted");
    } finally {
      clearTimeout(timer);
    }
  }
  console.log("  Chat burst statuses:", chatStatuses.join(","));

  writeFileSync(resolve(SHOT_DIR, "70-rate-results.json"), JSON.stringify({
    ocr: results,
    chat: chatStatuses,
  }, null, 2));
}

async function flowSettings(page) {
  console.log("\n── F9: Settings / Telegram link ──");
  await page.goto(`${BASE}/settings`);
  await waitIdle(page, 600);
  await shot(page, "80-settings", true);

  await page.goto(`${BASE}/telegram-link`);
  await waitIdle(page, 600);
  await shot(page, "81-telegram-link", true);
}

async function flowLogout(page) {
  console.log("\n── F10: Logout ──");
  await page.evaluate(() => {
    localStorage.removeItem("access_token");
    localStorage.removeItem("refresh_token");
  });
  await page.goto(BASE);
  await waitIdle(page);
  await shot(page, "90-after-logout", true);
}

// ── driver ────────────────────────────────────────────────────────

const FLOWS = {
  register: flowRegister,
  categories: flowCategories,
  expenses: flowExpenses,
  scan: flowScan,
  analytics: flowAnalytics,
  debt: flowDebt,
  chat: flowChat,
  rate: flowRate,
  settings: flowSettings,
  logout: flowLogout,
};

const ORDER = ["register", "categories", "expenses", "scan", "analytics", "debt", "chat", "rate", "settings", "logout"];

async function run() {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 2,
  });
  const page = await context.newPage();
  const errors = [];
  page.on("console", m => {
    if (m.type() === "error") errors.push(`[${m.type()}] ${m.text()}`);
  });
  page.on("requestfailed", r => errors.push(`[requestfailed] ${r.url()} ${r.failure()?.errorText}`));

  try {
    if (flow === "all") {
      for (const f of ORDER) await FLOWS[f](page);
    } else {
      await FLOWS[flow](page);
    }
  } catch (err) {
    console.error("FAILED:", err);
    await shot(page, "ERROR-final");
    throw err;
  } finally {
    if (errors.length) {
      console.log("\n── Console/Network errors captured ──");
      errors.forEach(e => console.log("  " + e));
      writeFileSync(resolve(SHOT_DIR, "_console-errors.log"), errors.join("\n"));
    }
    await browser.close();
  }
}

run().catch(e => { console.error(e); process.exit(1); });
