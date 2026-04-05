const API_BASE = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8002";

interface FetchOptions extends RequestInit {
  token?: string;
}

class ApiClient {
  private baseUrl: string;
  private token: string | null = null;

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl;
  }

  setToken(token: string | null) {
    this.token = token;
  }

  private async request<T>(path: string, options: FetchOptions = {}): Promise<T> {
    const { token, ...fetchOptions } = options;
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
      ...(options.headers as Record<string, string>),
    };

    const authToken = token || this.token;
    if (authToken) {
      headers["Authorization"] = `Bearer ${authToken}`;
    }

    const response = await fetch(`${this.baseUrl}${path}`, {
      ...fetchOptions,
      headers,
    });

    if (response.status === 401) {
      // Try refresh
      const refreshed = await this.refreshToken();
      if (refreshed) {
        headers["Authorization"] = `Bearer ${this.token}`;
        const retryResponse = await fetch(`${this.baseUrl}${path}`, {
          ...fetchOptions,
          headers,
        });
        if (!retryResponse.ok) {
          throw new ApiError(retryResponse.status, await retryResponse.text());
        }
        return retryResponse.json();
      }
      throw new ApiError(401, "Session expired");
    }

    if (!response.ok) {
      const errorText = await response.text();
      throw new ApiError(response.status, errorText);
    }

    if (response.status === 204) {
      return undefined as T;
    }

    return response.json();
  }

  private async refreshToken(): Promise<boolean> {
    const refreshToken = localStorage.getItem("refresh_token");
    if (!refreshToken) return false;

    try {
      const response = await fetch(`${this.baseUrl}/api/v1/auth/refresh`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ refresh_token: refreshToken }),
      });

      if (!response.ok) return false;

      const data = await response.json();
      this.token = data.access_token;
      localStorage.setItem("access_token", data.access_token);
      localStorage.setItem("refresh_token", data.refresh_token);
      return true;
    } catch {
      return false;
    }
  }

  // Auth
  async register(email: string, password: string, displayName?: string) {
    return this.request<{ access_token: string; refresh_token: string }>(
      "/api/v1/auth/register",
      { method: "POST", body: JSON.stringify({ email, password, display_name: displayName }) }
    );
  }

  async login(email: string, password: string) {
    return this.request<{ access_token: string; refresh_token: string }>(
      "/api/v1/auth/login",
      { method: "POST", body: JSON.stringify({ email, password }) }
    );
  }

  async getMe() {
    return this.request<any>("/api/v1/auth/me");
  }

  async logout() {
    return this.request<void>("/api/v1/auth/logout", { method: "POST" });
  }

  async getFeatureFlags() {
    const user = await this.getMe();
    // Feature flags are fetched from admin endpoint or embedded in user response
    return this.request<Record<string, boolean>>(`/api/v1/admin/users/${user.id}/features`).catch(
      () => ({})
    );
  }

  // Categories
  async getCategories() {
    return this.request<any[]>("/api/v1/categories");
  }

  async createCategory(data: any) {
    return this.request<any>("/api/v1/categories", {
      method: "POST",
      body: JSON.stringify(data),
    });
  }

  async reorderCategories(categoryIds: string[]) {
    return this.request<any>("/api/v1/categories/reorder", {
      method: "PUT",
      body: JSON.stringify({ category_ids: categoryIds }),
    });
  }

  // Expenses
  async getExpenses(params?: Record<string, string>) {
    const query = params ? "?" + new URLSearchParams(params).toString() : "";
    return this.request<any>(`/api/v1/expenses${query}`);
  }

  async quickAddExpense(amount: number, categoryId: string) {
    return this.request<any>("/api/v1/expenses/quick", {
      method: "POST",
      body: JSON.stringify({ amount, category_id: categoryId }),
    });
  }

  async createExpense(data: any) {
    return this.request<any>("/api/v1/expenses", {
      method: "POST",
      body: JSON.stringify(data),
    });
  }

  async deleteExpense(id: string) {
    return this.request<void>(`/api/v1/expenses/${id}`, { method: "DELETE" });
  }

  // Receipts — pending queue
  async queueReceipt(file: File) {
    const formData = new FormData();
    formData.append("file", file);
    const headers: Record<string, string> = {};
    if (this.token) headers["Authorization"] = `Bearer ${this.token}`;

    const response = await fetch(`${this.baseUrl}/api/v1/receipts/queue`, {
      method: "POST",
      headers,
      body: formData,
    });
    if (!response.ok) throw new ApiError(response.status, await response.text());
    return response.json();
  }

  async getPendingReceipts() {
    return this.request<any[]>("/api/v1/receipts/pending");
  }

  async deletePendingReceipt(id: string) {
    return this.request<void>(`/api/v1/receipts/pending/${id}`, { method: "DELETE" });
  }

  // Receipts — scan (OCR)
  async scanReceipt(file: File) {
    const formData = new FormData();
    formData.append("file", file);
    const headers: Record<string, string> = {};
    if (this.token) headers["Authorization"] = `Bearer ${this.token}`;

    const response = await fetch(`${this.baseUrl}/api/v1/receipts/scan`, {
      method: "POST",
      headers,
      body: formData,
    });
    if (!response.ok) throw new ApiError(response.status, await response.text());
    return response.json();
  }

  // Imports
  async uploadStatement(file: File) {
    const formData = new FormData();
    formData.append("file", file);
    const headers: Record<string, string> = {};
    if (this.token) headers["Authorization"] = `Bearer ${this.token}`;

    const response = await fetch(`${this.baseUrl}/api/v1/import/upload`, {
      method: "POST",
      headers,
      body: formData,
    });
    if (!response.ok) throw new ApiError(response.status, await response.text());
    return response.json();
  }

  async confirmImport(data: any) {
    return this.request<any>("/api/v1/import/confirm", {
      method: "POST",
      body: JSON.stringify(data),
    });
  }

  // Debt
  async getCreditCards() {
    return this.request<any[]>("/api/v1/credit-cards");
  }

  async createCreditCard(data: any) {
    return this.request<any>("/api/v1/credit-cards/", {
      method: "POST",
      body: JSON.stringify(data),
    });
  }

  async deleteCreditCard(id: string) {
    return this.request<void>(`/api/v1/credit-cards/${id}`, { method: "DELETE" });
  }

  async getLoans() {
    return this.request<any[]>("/api/v1/loans");
  }

  async createLoan(data: any) {
    return this.request<any>("/api/v1/loans/", {
      method: "POST",
      body: JSON.stringify(data),
    });
  }

  async deleteLoan(id: string) {
    return this.request<void>(`/api/v1/loans/${id}`, { method: "DELETE" });
  }

  async getDebtSummary() {
    return this.request<any>("/api/v1/debt/summary");
  }

  async getDebtStrategies(monthlyBudget: number) {
    return this.request<any>(`/api/v1/debt/strategies?monthly_budget=${monthlyBudget}`);
  }

  // Analytics
  async getAnalyticsDaily(startDate: string, endDate: string) {
    return this.request<any[]>(
      `/api/v1/analytics/daily?start_date=${startDate}&end_date=${endDate}`
    );
  }

  async getAnalyticsByCategory(startDate: string, endDate: string) {
    return this.request<any[]>(
      `/api/v1/analytics/by-category?start_date=${startDate}&end_date=${endDate}`
    );
  }

  async getBudgetStatus() {
    return this.request<any[]>("/api/v1/analytics/budget-status");
  }

  // Admin
  async getAdminUsers() {
    return this.request<any[]>("/api/v1/admin/users");
  }

  async toggleFeatureFlag(userId: string, featureName: string, isEnabled: boolean) {
    return this.request<any>(`/api/v1/admin/users/${userId}/features`, {
      method: "PATCH",
      body: JSON.stringify({ feature_name: featureName, is_enabled: isEnabled }),
    });
  }

  async getAdminStats() {
    return this.request<any>("/api/v1/admin/stats");
  }

  // Chat
  async createConversation(title?: string) {
    return this.request<any>("/api/v1/chat/conversations", {
      method: "POST",
      body: JSON.stringify({ title }),
    });
  }

  async getConversations() {
    return this.request<any[]>("/api/v1/chat/conversations");
  }

  async updateConversation(id: string, title: string) {
    return this.request<any>(`/api/v1/chat/conversations/${id}`, {
      method: "PUT",
      body: JSON.stringify({ title }),
    });
  }

  async deleteConversation(id: string) {
    return this.request<void>(`/api/v1/chat/conversations/${id}`, { method: "DELETE" });
  }

  async getMessages(conversationId: string, limit = 50, offset = 0) {
    return this.request<any>(
      `/api/v1/chat/conversations/${conversationId}/messages?limit=${limit}&offset=${offset}`
    );
  }

  async sendChatMessage(conversationId: string, content: string, model = "haiku") {
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
    };
    if (this.token) headers["Authorization"] = `Bearer ${this.token}`;

    const response = await fetch(
      `${this.baseUrl}/api/v1/chat/conversations/${conversationId}/messages`,
      {
        method: "POST",
        headers,
        body: JSON.stringify({ content, model }),
      }
    );

    if (!response.ok) throw new ApiError(response.status, await response.text());
    return response;
  }

  // Telegram
  async generateTelegramLink() {
    return this.request<{ code: string; expires_at: string }>("/api/v1/telegram/link", {
      method: "POST",
    });
  }

  async getTelegramStatus() {
    return this.request<{ linked: boolean; telegram_username: string | null; linked_at: string | null }>(
      "/api/v1/telegram/status"
    );
  }

  async unlinkTelegram() {
    return this.request<{ success: boolean }>("/api/v1/telegram/unlink", { method: "DELETE" });
  }
}

export class ApiError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
    this.name = "ApiError";
  }
}

export const api = new ApiClient(API_BASE);
