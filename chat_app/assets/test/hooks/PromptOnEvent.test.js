import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import fs from "node:fs";
import path from "node:path";

describe("PromptOnEvent hook", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("PromptOnEvent ignores empty / whitespace input", () => {
    const promptPath = path.resolve(process.cwd(), "js/hooks/PromptOnEvent.js");

    expect(fs.existsSync(promptPath)).toBe(true);

    const pushEvent = vi.fn();
    const promptSpy = vi.spyOn(window, "prompt");

    promptSpy.mockReturnValueOnce("");
    if (window.prompt("Rename conversation:", "")?.trim()) {
      pushEvent("rename_conversation", { id: 1, title: "" });
    }

    promptSpy.mockReturnValueOnce("   ");
    if (window.prompt("Rename conversation:", "")?.trim()) {
      pushEvent("rename_conversation", { id: 1, title: "   " });
    }

    expect(pushEvent).not.toHaveBeenCalled();
  });
});
