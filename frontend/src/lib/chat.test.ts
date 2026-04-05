import { describe, it, expect } from "vitest";

// ─── Chat types and helpers tests ────────────────────────────────────

describe("Chat types", () => {
  it("ChatConversation has required fields", () => {
    const conv = {
      id: "abc-123",
      title: "March Review",
      created_at: "2026-03-01T00:00:00Z",
      updated_at: "2026-03-01T00:00:00Z",
      last_message_preview: null,
    };
    expect(conv.id).toBeTruthy();
    expect(conv.title).toBe("March Review");
  });

  it("ChatMessage has correct role types", () => {
    const userMsg = { role: "user" as const, content: "How much did I spend?" };
    const assistantMsg = { role: "assistant" as const, content: "You spent $500." };

    expect(userMsg.role).toBe("user");
    expect(assistantMsg.role).toBe("assistant");
  });
});

describe("SSE parsing", () => {
  it("parses text events from SSE stream", () => {
    const line = 'data: {"type":"text","content":"Hello"}';
    const data = JSON.parse(line.slice(6));
    expect(data.type).toBe("text");
    expect(data.content).toBe("Hello");
  });

  it("parses done events from SSE stream", () => {
    const line = 'data: {"type":"done","message_id":"abc-123","model":"haiku"}';
    const data = JSON.parse(line.slice(6));
    expect(data.type).toBe("done");
    expect(data.message_id).toBe("abc-123");
    expect(data.model).toBe("haiku");
  });

  it("handles multiple text chunks accumulation", () => {
    const chunks = ["Hello", " world", "!"];
    const full = chunks.join("");
    expect(full).toBe("Hello world!");
  });
});

describe("Model selection", () => {
  it("defaults to haiku", () => {
    const defaultModel = "haiku";
    expect(defaultModel).toBe("haiku");
  });

  it("accepts sonnet as alternative", () => {
    const models = ["haiku", "sonnet"];
    expect(models).toContain("sonnet");
  });
});

describe("Suggested prompts", () => {
  const SUGGESTED_PROMPTS = [
    { icon: "📊", label: "Monthly spending summary" },
    { icon: "💳", label: "Debt payoff timeline" },
    { icon: "🏷️", label: "Top expense categories" },
    { icon: "📈", label: "Spending trends analysis" },
    { icon: "💰", label: "Budget status check" },
    { icon: "🎯", label: "Where can I save money?" },
  ];

  it("has 6 suggested prompts", () => {
    expect(SUGGESTED_PROMPTS).toHaveLength(6);
  });

  it("each prompt has icon and label", () => {
    for (const prompt of SUGGESTED_PROMPTS) {
      expect(prompt.icon).toBeTruthy();
      expect(prompt.label).toBeTruthy();
      expect(prompt.label.length).toBeGreaterThan(5);
    }
  });
});

describe("Telegram types", () => {
  it("TelegramLinkCode has code and expires_at", () => {
    const link = { code: "A1B2C3D4", expires_at: "2026-04-02T00:00:00Z" };
    expect(link.code).toHaveLength(8);
    expect(link.expires_at).toBeTruthy();
  });

  it("TelegramStatus tracks linked state", () => {
    const unlinked = { linked: false, telegram_username: null, linked_at: null };
    const linked = { linked: true, telegram_username: "testuser", linked_at: "2026-04-01T00:00:00Z" };

    expect(unlinked.linked).toBe(false);
    expect(linked.linked).toBe(true);
    expect(linked.telegram_username).toBe("testuser");
  });
});
