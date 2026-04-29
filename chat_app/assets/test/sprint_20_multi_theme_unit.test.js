import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { initThemeController } from "../js/theme";

const renderThemeButtons = () => {
  document.body.innerHTML = `
    <div role="group" aria-label="Theme" data-theme-source="js">
      <button type="button" data-phx-theme="editorial" aria-pressed="true">ED</button>
      <button type="button" data-phx-theme="swiss" aria-pressed="false">SW</button>
      <button type="button" data-phx-theme="mid-century" aria-pressed="false">MC</button>
      <button type="button" data-phx-theme="techno-brutalist" aria-pressed="false">TB</button>
    </div>
  `;
};

const RealMutationObserver = globalThis.MutationObserver;

describe("SP-03-20 multi-theme unit", () => {
  beforeEach(() => {
    globalThis.MutationObserver = class {
      observe() {}
      disconnect() {}
    };

    localStorage.clear();
    document.documentElement.className = "theme-editorial";
    document.documentElement.dataset.theme = "editorial";
    document.documentElement.dataset.themeSource = "js";
    renderThemeButtons();
  });

  afterEach(() => {
    globalThis.MutationObserver = RealMutationObserver;
  });

  it("theme JS hook sets localStorage and DOM attributes correctly", () => {
    initThemeController();

    document
      .querySelector("[data-phx-theme='swiss']")
      .dispatchEvent(new Event("phx:set-theme", { bubbles: true }));

    expect(localStorage.getItem("chat_app:theme")).toBe("swiss");
    expect(document.documentElement.dataset.theme).toBe("swiss");
    expect(document.documentElement.dataset.themeSource).toBe("js");
    expect(document.documentElement.classList.contains("theme-swiss")).toBe(true);
    expect(
      document.querySelector("[data-phx-theme='swiss']").getAttribute("aria-pressed"),
    ).toBe("true");
    expect(
      document.querySelector("[data-phx-theme='editorial']").getAttribute("aria-pressed"),
    ).toBe("false");
  });
});
