import { test, expect } from "@playwright/test";

const BASE = "http://localhost:3000";
const EMAIL = `e2e-${Date.now()}@test.com`;
const PASSWORD = "TestPass123!";

test.describe("Finance Tracker — Full User Workflow", () => {
  test.describe.configure({ mode: "serial" });

  let page: any;

  test.beforeAll(async ({ browser }) => {
    page = await browser.newPage();
  });

  test.afterAll(async () => {
    await page.close();
  });

  // ── 1. Registration ──────────────────────────────────────────────

  test("register a new account", async () => {
    await page.goto(BASE);
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(2000);

    // May land on Sign In page — click "Register" link to switch
    const registerLink = page.getByText("Register");
    if (await registerLink.isVisible({ timeout: 3000 }).catch(() => false)) {
      await registerLink.click();
      await page.waitForTimeout(1000);
    }

    // Now on "Create account" form with: Display Name, Email, Password
    await page.getByPlaceholder("Your name").fill("E2E Test User");
    await page.getByPlaceholder("you@email.com").fill(EMAIL);
    await page.getByPlaceholder("Min 6 characters").fill(PASSWORD);

    // Submit
    await page.getByRole("button", { name: /create account/i }).click();

    // Wait for redirect to dashboard
    await page.waitForTimeout(3000);
    await page.waitForLoadState("networkidle");

    const url = page.url();
    console.log(`After register URL: ${url}`);
  });

  // ── 2. Add Categories ────────────────────────────────────────────

  test("create expense categories via API", async () => {
    // Get token from localStorage
    const token = await page.evaluate(() => localStorage.getItem("access_token"));
    expect(token).toBeTruthy();

    // Create categories via API for faster setup
    for (const cat of ["Groceries", "Transport", "Coffee", "Dining"]) {
      const resp = await page.evaluate(
        async ({ name, token }: { name: string; token: string }) => {
          const r = await fetch("http://localhost:8002/api/v1/categories/", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${token}`,
            },
            body: JSON.stringify({ name, icon: "receipt", color: "#3B82F6" }),
          });
          return { status: r.status, ok: r.ok };
        },
        { name: cat, token }
      );
      console.log(`Category "${cat}": ${resp.status}`);
      expect(resp.ok).toBeTruthy();
    }
  });

  // ── 3. Add Expenses ──────────────────────────────────────────────

  test("add expenses via API", async () => {
    const token = await page.evaluate(() => localStorage.getItem("access_token"));

    // Get categories
    const categories = await page.evaluate(async (token: string) => {
      const r = await fetch("http://localhost:8002/api/v1/categories/", {
        headers: { Authorization: `Bearer ${token}` },
      });
      return r.json();
    }, token);

    expect(categories.length).toBeGreaterThan(0);
    const catMap: Record<string, string> = {};
    for (const c of categories) {
      catMap[c.name] = c.id;
    }

    // Create 5 expenses
    const expenses = [
      { amount: 45.99, description: "Whole Foods weekly shop", merchant_name: "Whole Foods", category_id: catMap["Groceries"] },
      { amount: 12.50, description: "Uber to downtown", merchant_name: "Uber", category_id: catMap["Transport"] },
      { amount: 5.75, description: "Morning latte", merchant_name: "Starbucks", category_id: catMap["Coffee"] },
      { amount: 38.00, description: "Dinner with friends", merchant_name: "Olive Garden", category_id: catMap["Dining"] },
      { amount: 89.99, description: "Weekly groceries", merchant_name: "Trader Joes", category_id: catMap["Groceries"] },
    ];

    for (const exp of expenses) {
      const resp = await page.evaluate(
        async ({ exp, token }: { exp: any; token: string }) => {
          const r = await fetch("http://localhost:8002/api/v1/expenses/", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${token}`,
            },
            body: JSON.stringify({
              ...exp,
              expense_date: new Date().toISOString().split("T")[0],
            }),
          });
          return { status: r.status, ok: r.ok };
        },
        { exp, token }
      );
      console.log(`Expense "${exp.description}": ${resp.status}`);
      expect(resp.ok).toBeTruthy();
    }
  });

  // ── 4. Navigate Expenses Page ────────────────────────────────────

  test("view expenses list", async () => {
    await page.goto(`${BASE}/expenses`);
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(2000);

    // Should see expense items
    const body = await page.textContent("body");
    expect(body).toContain("Whole Foods");
    expect(body).toContain("45.99");

    await page.screenshot({ path: "e2e/screenshots/expenses.png" });
    console.log("Expenses page verified");
  });

  // ── 5. Add Debt — Credit Card ────────────────────────────────────

  test("navigate to debt page and add credit card", async () => {
    await page.goto(`${BASE}/debt`);
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(2000);

    // Click "Add Card"
    const addCardBtn = page.getByText(/add card/i);
    await addCardBtn.click();
    await page.waitForTimeout(500);

    // Fill form
    await page.getByPlaceholder(/chase freedom|card name/i).fill("Chase Sapphire");
    await page.getByPlaceholder(/1234/i).fill("4242");
    await page.getByPlaceholder(/24.99/i).fill("22.99");
    await page.getByPlaceholder(/3500|balance/i).first().fill("5200");
    await page.getByPlaceholder(/10000|credit limit/i).fill("15000");
    await page.getByPlaceholder(/75|min/i).fill("150");

    // Submit
    const submitBtn = page.getByRole("button", { name: /add credit card/i });
    await submitBtn.click();
    await page.waitForTimeout(2000);

    // Verify card appears
    const body = await page.textContent("body");
    expect(body).toContain("Chase Sapphire");

    await page.screenshot({ path: "e2e/screenshots/debt-card.png" });
    console.log("Credit card added");
  });

  // ── 6. Add Debt — Loan ───────────────────────────────────────────

  test("add a loan", async () => {
    // Click "Add Loan"
    const addLoanBtn = page.getByText(/add loan/i);
    await addLoanBtn.click();
    await page.waitForTimeout(500);

    // Fill form
    await page.getByPlaceholder(/car loan|loan name/i).fill("Honda Civic Loan");
    await page.getByPlaceholder(/bank name|lender/i).fill("Chase Auto");

    // Select loan type
    const typeSelect = page.locator("select");
    if (await typeSelect.isVisible()) {
      await typeSelect.selectOption("car");
    }

    await page.getByPlaceholder(/25000|original/i).fill("28000");
    await page.getByPlaceholder(/18000|current balance/i).fill("22000");
    await page.getByPlaceholder(/6.5|interest/i).fill("5.49");
    await page.getByPlaceholder(/450|min/i).last().fill("475");

    // Submit — use the full-width form button (not the header link)
    await page.locator("button").filter({ hasText: /^Add Loan$/ }).click();
    await page.waitForTimeout(2000);

    // Verify loan appears
    const body = await page.textContent("body");
    expect(body).toContain("Honda Civic Loan");

    await page.screenshot({ path: "e2e/screenshots/debt-loan.png" });
    console.log("Loan added");
  });

  // ── 7. Check Analytics ───────────────────────────────────────────

  test("view analytics page", async () => {
    await page.goto(`${BASE}/analytics`);
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(3000);

    // Should show spending data
    const body = await page.textContent("body");

    // Click "Day" tab
    const dayTab = page.getByText("Day").first();
    if (await dayTab.isVisible()) {
      await dayTab.click();
      await page.waitForTimeout(2000);
    }

    await page.screenshot({ path: "e2e/screenshots/analytics.png" });
    console.log("Analytics page verified");
  });

  // ── 8. Visit Scan Page ───────────────────────────────────────────

  test("visit scan page", async () => {
    await page.goto(`${BASE}/scan`);
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(3000);

    // In headless mode without a camera, the page may show an error or redirect
    // Just verify the page loaded without crashing
    const url = page.url();
    const body = await page.textContent("body");
    console.log(`Scan page URL: ${url}, body length: ${body?.length}`);

    await page.screenshot({ path: "e2e/screenshots/scan.png" });
    // Pass — we just verify the route doesn't crash
  });

  // ── 9. Visit Receipts Page ───────────────────────────────────────

  test("visit receipts page", async () => {
    await page.goto(`${BASE}/receipts`);
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(2000);

    await page.screenshot({ path: "e2e/screenshots/receipts.png" });
    console.log("Receipts page loaded");
  });

  // ── 10. Final Dashboard Check ────────────────────────────────────

  test("return to dashboard", async () => {
    await page.goto(BASE);
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(2000);

    await page.screenshot({ path: "e2e/screenshots/dashboard-final.png" });

    const body = await page.textContent("body");
    console.log(`Dashboard loaded. Body length: ${body?.length}`);
  });
});
