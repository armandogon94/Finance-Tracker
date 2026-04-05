import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";
import { ApiError } from "@/lib/api";

// We re-import the module fresh for each test so the ApiClient picks up our mock
// The singleton `api` is the only exported client instance.

describe("ApiError", () => {
  it("has correct status and message", () => {
    const err = new ApiError(404, "Not found");
    expect(err.status).toBe(404);
    expect(err.message).toBe("Not found");
    expect(err.name).toBe("ApiError");
  });

  it("is an instance of Error", () => {
    const err = new ApiError(500, "Server error");
    expect(err).toBeInstanceOf(Error);
    expect(err).toBeInstanceOf(ApiError);
  });
});

describe("api client (singleton)", () => {
  const mockFetch = vi.fn();

  beforeEach(() => {
    vi.stubGlobal("fetch", mockFetch);
    // Provide localStorage for refreshToken path
    vi.stubGlobal("localStorage", {
      getItem: vi.fn(() => null),
      setItem: vi.fn(),
      removeItem: vi.fn(),
    });
    mockFetch.mockReset();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("constructs the correct URL for a GET request", async () => {
    // Dynamic import so the module picks up our stubbed fetch
    const { api } = await import("@/lib/api");

    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => [{ id: "1", name: "Food" }],
    });

    await api.getCategories();

    expect(mockFetch).toHaveBeenCalledOnce();
    const [url] = mockFetch.mock.calls[0];
    expect(url).toMatch(/\/api\/v1\/categories$/);
  });

  it("adds Authorization header when token is set", async () => {
    const { api } = await import("@/lib/api");

    api.setToken("test-jwt-token");

    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ id: "u1", email: "a@b.com" }),
    });

    await api.getMe();

    const [, options] = mockFetch.mock.calls[0];
    expect(options.headers["Authorization"]).toBe("Bearer test-jwt-token");

    // Clean up
    api.setToken(null);
  });

  it("throws ApiError on non-ok response", async () => {
    const { api, ApiError: AE } = await import("@/lib/api");

    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 422,
      text: async () => "Validation error",
    });

    await expect(api.getCategories()).rejects.toThrow(AE);
    await expect(
      // Need fresh mock for second assertion
      (async () => {
        mockFetch.mockResolvedValueOnce({
          ok: false,
          status: 422,
          text: async () => "Validation error",
        });
        return api.getCategories();
      })()
    ).rejects.toMatchObject({ status: 422 });
  });

  it("sends JSON body for POST requests", async () => {
    const { api } = await import("@/lib/api");

    api.setToken("tok");

    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ access_token: "a", refresh_token: "r" }),
    });

    await api.login("user@test.com", "pass123");

    const [url, options] = mockFetch.mock.calls[0];
    expect(url).toMatch(/\/api\/v1\/auth\/login$/);
    expect(options.method).toBe("POST");
    expect(JSON.parse(options.body)).toEqual({
      email: "user@test.com",
      password: "pass123",
    });

    api.setToken(null);
  });

  it("returns undefined for 204 No Content responses", async () => {
    const { api } = await import("@/lib/api");

    api.setToken("tok");

    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 204,
      json: async () => null,
    });

    const result = await api.deleteExpense("exp-1");
    expect(result).toBeUndefined();

    api.setToken(null);
  });
});
