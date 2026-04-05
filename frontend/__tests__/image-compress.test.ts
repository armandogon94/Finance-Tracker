import { describe, expect, it } from "vitest";
import { fileToBase64 } from "@/lib/image-compress";

describe("fileToBase64", () => {
  it("converts a blob to base64 string", async () => {
    const text = "hello world";
    const blob = new Blob([text], { type: "text/plain" });
    const result = await fileToBase64(blob);
    expect(result).toContain("data:text/plain;base64,");
    expect(typeof result).toBe("string");
  });

  it("handles empty blob", async () => {
    const blob = new Blob([], { type: "application/octet-stream" });
    const result = await fileToBase64(blob);
    expect(result).toContain("data:");
  });
});
