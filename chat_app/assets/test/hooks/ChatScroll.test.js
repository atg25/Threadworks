import { describe, it, expect, vi, beforeEach } from "vitest";
import ChatScroll from "../../js/hooks/ChatScroll";

function makeScrollEl(scrollTop = 0, scrollHeight = 500, clientHeight = 500) {
  const el = document.createElement("div");
  Object.defineProperties(el, {
    scrollTop: { value: scrollTop, writable: true },
    scrollHeight: { value: scrollHeight, writable: true },
    clientHeight: { value: clientHeight, writable: true },
  });
  document.body.appendChild(el);
  return el;
}

function makeHook(el) {
  const hook = Object.create(ChatScroll);
  hook.el = el;
  hook.pushEvent = vi.fn();
  hook.isAtBottom = true;
  return hook;
}

describe("ChatScroll", () => {
  beforeEach(() => {
    document.body.innerHTML = "";
  });

  it("scrollToBottom sets el.scrollTop to el.scrollHeight", () => {
    const el = makeScrollEl(0, 800, 500);
    const hook = makeHook(el);
    hook.scrollToBottom();
    expect(el.scrollTop).toBe(800);
  });

  it("updated scrolls to bottom when isAtBottom is true", () => {
    const el = makeScrollEl(0, 800, 500);
    const hook = makeHook(el);
    hook.isAtBottom = true;
    hook.updated();
    expect(el.scrollTop).toBe(800);
  });

  it("updated does not scroll when isAtBottom is false", () => {
    const el = makeScrollEl(100, 800, 500);
    const hook = makeHook(el);
    hook.isAtBottom = false;
    hook.updated();
    expect(el.scrollTop).toBe(100);
  });

  it("onScroll sets isAtBottom true when near bottom (within 40px)", () => {
    const el = makeScrollEl(61, 600, 500);
    const hook = makeHook(el);
    hook.onScroll();
    expect(hook.isAtBottom).toBe(true);
  });

  it("onScroll sets isAtBottom false when far from bottom (> 40px)", () => {
    const el = makeScrollEl(0, 600, 500);
    const hook = makeHook(el);
    hook.onScroll();
    expect(hook.isAtBottom).toBe(false);
  });

  it("onScroll removes hidden class from scroll-cta-dock when not at bottom", () => {
    const dock = document.createElement("div");
    dock.id = "scroll-cta-dock";
    dock.classList.add("hidden");
    document.body.appendChild(dock);

    const el = makeScrollEl(0, 600, 500);
    const hook = makeHook(el);
    hook.onScroll();

    expect(dock.classList.contains("hidden")).toBe(false);
  });

  it("onScroll keeps hidden class on scroll-cta-dock when at bottom", () => {
    const dock = document.createElement("div");
    dock.id = "scroll-cta-dock";
    dock.classList.add("hidden");
    document.body.appendChild(dock);

    const el = makeScrollEl(61, 600, 500);
    const hook = makeHook(el);
    hook.onScroll();

    expect(dock.classList.contains("hidden")).toBe(true);
  });

  it("onScroll pushes scroll_position event with at_bottom value", () => {
    const el = makeScrollEl(0, 600, 500);
    const hook = makeHook(el);
    hook.onScroll();
    expect(hook.pushEvent).toHaveBeenCalledWith("scroll_position", {
      at_bottom: false,
    });
  });

  it("mounted attaches a single click listener to scroll-to-bottom", () => {
    const dock = document.createElement("div");
    dock.id = "scroll-cta-dock";
    dock.classList.add("hidden");
    document.body.appendChild(dock);

    const btn = document.createElement("button");
    btn.id = "scroll-to-bottom";
    document.body.appendChild(btn);

    const el = makeScrollEl(0, 800, 500);
    const hook = makeHook(el);
    hook.mounted();

    el.scrollTop = 0;
    btn.dispatchEvent(new Event("click"));
    expect(el.scrollTop).toBe(el.scrollHeight);
  });

  it("mounted sets initial dock visibility before any scroll event", () => {
    const dock = document.createElement("div");
    dock.id = "scroll-cta-dock";
    dock.classList.add("hidden");
    document.body.appendChild(dock);

    const btn = document.createElement("button");
    btn.id = "scroll-to-bottom";
    document.body.appendChild(btn);

    const el = makeScrollEl(0, 800, 500);
    const hook = makeHook(el);
    hook.mounted();

    expect(dock.classList.contains("hidden")).toBe(true);
  });

  it("_updateDockVisibility toggles based on isAtBottom without re-binding click", () => {
    const dock = document.createElement("div");
    dock.id = "scroll-cta-dock";
    dock.classList.add("hidden");
    document.body.appendChild(dock);

    const btn = document.createElement("button");
    btn.id = "scroll-to-bottom";
    const originalAddEventListener = btn.addEventListener.bind(btn);
    btn.addEventListener = vi.fn(originalAddEventListener);
    document.body.appendChild(btn);

    const el = makeScrollEl(0, 600, 500);
    const hook = makeHook(el);
    hook.mounted();

    // Simulate multiple scroll events; click listener must not multiply.
    for (let i = 0; i < 5; i++) hook.onScroll();

    const clickAdds = btn.addEventListener.mock.calls.filter(
      (call) => call[0] === "click",
    );
    expect(clickAdds.length).toBe(1);

    // And dock visibility should toggle with isAtBottom.
    el.scrollTop = 0;
    hook.onScroll();
    expect(dock.classList.contains("hidden")).toBe(false);

    el.scrollTop = 61;
    hook.onScroll();
    expect(dock.classList.contains("hidden")).toBe(true);
  });
});
