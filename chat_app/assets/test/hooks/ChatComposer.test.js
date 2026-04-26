import { describe, it, expect, vi, beforeEach } from "vitest";
import ChatComposer from "../../js/hooks/ChatComposer";

function makeTextarea(value = "") {
  const el = document.createElement("textarea");
  el.value = value;
  el.style.height = "auto";
  document.body.appendChild(el);
  return el;
}

function makeHook(el) {
  const hook = Object.create(ChatComposer);
  hook.el = el;
  hook.pushEvent = vi.fn();
  return hook;
}

describe("ChatComposer", () => {
  beforeEach(() => {
    document.body.innerHTML = "";
  });

  it("resize sets el.style.height to scrollHeight (capped at 192px)", () => {
    const el = makeTextarea();
    Object.defineProperty(el, "scrollHeight", { value: 80 });
    const hook = makeHook(el);
    hook.resize();
    expect(el.style.height).toBe("80px");
  });

  it("resize caps height at 192px", () => {
    const el = makeTextarea();
    Object.defineProperty(el, "scrollHeight", { value: 300 });
    const hook = makeHook(el);
    hook.resize();
    expect(el.style.height).toBe("192px");
  });

  it("resize sets overflow-y to auto when scrollHeight > 192", () => {
    const el = makeTextarea();
    Object.defineProperty(el, "scrollHeight", { value: 300 });
    const hook = makeHook(el);
    hook.resize();
    expect(el.style.overflowY).toBe("auto");
  });

  it("resize sets overflow-y to hidden when scrollHeight <= 192", () => {
    const el = makeTextarea();
    Object.defineProperty(el, "scrollHeight", { value: 80 });
    const hook = makeHook(el);
    hook.resize();
    expect(el.style.overflowY).toBe("hidden");
  });

  it("Enter keydown calls requestSubmit on the parent form", () => {
    const form = document.createElement("form");
    const el = makeTextarea();
    form.appendChild(el);
    document.body.appendChild(form);

    const submitSpy = vi.fn();
    form.requestSubmit = submitSpy;

    const hook = makeHook(el);
    const event = new KeyboardEvent("keydown", {
      key: "Enter",
      shiftKey: false,
      bubbles: true,
    });
    hook.onKeyDown(event);

    expect(submitSpy).toHaveBeenCalledOnce();
  });

  it("Shift+Enter does NOT call requestSubmit", () => {
    const form = document.createElement("form");
    const el = makeTextarea();
    form.appendChild(el);
    document.body.appendChild(form);

    const submitSpy = vi.fn();
    form.requestSubmit = submitSpy;

    const hook = makeHook(el);
    const event = new KeyboardEvent("keydown", {
      key: "Enter",
      shiftKey: true,
      bubbles: true,
    });
    hook.onKeyDown(event);

    expect(submitSpy).not.toHaveBeenCalled();
  });

  it("non-Enter keydown does not submit", () => {
    const form = document.createElement("form");
    const el = makeTextarea();
    form.appendChild(el);
    document.body.appendChild(form);

    const submitSpy = vi.fn();
    form.requestSubmit = submitSpy;

    const hook = makeHook(el);
    const event = new KeyboardEvent("keydown", {
      key: "a",
      shiftKey: false,
      bubbles: true,
    });
    hook.onKeyDown(event);

    expect(submitSpy).not.toHaveBeenCalled();
  });

  it("Enter during IME composition does not submit", () => {
    const form = document.createElement("form");
    const el = makeTextarea();
    form.appendChild(el);
    document.body.appendChild(form);

    const submitSpy = vi.fn();
    form.requestSubmit = submitSpy;

    const hook = makeHook(el);
    const event = new KeyboardEvent("keydown", {
      key: "Enter",
      shiftKey: false,
      isComposing: true,
      bubbles: true,
    });
    hook.onKeyDown(event);

    expect(submitSpy).not.toHaveBeenCalled();
  });
});
