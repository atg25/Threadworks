import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

describe("Clipboard hook", () => {
  let writeText;

  beforeEach(() => {
    writeText = vi.fn();
    Object.defineProperty(global.navigator, "clipboard", {
      configurable: true,
      value: { writeText },
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("Clipboard hook writes the dispatched text", () => {
    window.dispatchEvent(
      new CustomEvent("phx:copy", { detail: { text: "hello" } }),
    );

    expect(writeText).toHaveBeenCalledTimes(1);
    expect(writeText).toHaveBeenCalledWith("hello");
  });

  it("Code-block copy delegated handler reads data-copy-text", () => {
    const button = document.createElement("button");
    button.className = "ui-code-block-copy";
    button.setAttribute("data-copy-text", "snippet");
    button.textContent = "Copy";
    document.body.appendChild(button);

    button.click();

    expect(writeText).toHaveBeenCalledTimes(1);
    expect(writeText).toHaveBeenCalledWith("snippet");
  });
});
