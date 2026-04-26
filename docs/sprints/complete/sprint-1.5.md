---
status: complete
---

# Sprint 1.5 — Composer Plane, Frame & JS Hooks

**Spec:** spec-1 §6.5, §10  
**Goal:** Implement the full composer markup (plane → seam → frame → textarea → send button) and both JS hooks (`ChatComposer` and `ChatScroll`). The input must auto-resize, Enter must submit, Shift+Enter must insert a newline, and the scroll-to-bottom pill must show/hide correctly.  
**Depends on:** sprint-1.3 (grid skeleton with empty composer row), sprint-1.4 (hero renders)  
**Delivers:** A fully rendered, interactive composer that passes all structural and JS-behavior tests.

---

## TDD Approach

| Layer                       | Tool                           | Assertions                                                                |
| --------------------------- | ------------------------------ | ------------------------------------------------------------------------- |
| Composer HTML structure     | `Phoenix.LiveViewTest` + Floki | Required wrapper elements, form, textarea, button present                 |
| Button disabled state       | `Phoenix.LiveViewTest`         | Button disabled when input empty, enabled otherwise                       |
| Scroll pill structure       | `Phoenix.LiveViewTest`         | `#scroll-cta-dock` and `#scroll-to-bottom` present                        |
| `phx-hook` attributes       | `Phoenix.LiveViewTest`         | `phx-hook="ChatScroll"` and `phx-hook="ChatComposer"` on correct elements |
| `ChatComposer` Enter submit | Vitest (JS unit)               | `requestSubmit()` called on Enter, not on Shift+Enter                     |
| `ChatComposer` resize       | Vitest (JS unit)               | `style.height` updates on `input` event                                   |
| `ChatScroll` pin-to-bottom  | Vitest (JS unit)               | `scrollTop = scrollHeight` on `updated()` when `isAtBottom`               |
| `ChatScroll` pill toggle    | Vitest (JS unit)               | `scroll-cta-dock` loses `hidden` class when not at bottom                 |

---

## Step 1 — Write Elixir tests FIRST (Red)

### Append to `test/chat_app_web/live/chat_live_test.exs`

```elixir
  describe "composer markup" do
    # Positive: structural elements
    test "composer plane wrapper is present", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "ui-chat-composer-plane"
    end

    test "composer seam hairline div is present", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "ui-chat-composer-seam"
    end

    test "composer form is rendered", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ ~r/<form[^>]+phx-submit="send_message"/
    end

    test "textarea is rendered with phx-hook ChatComposer", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ ~r/<textarea[^>]+phx-hook="ChatComposer"/
    end

    test "textarea has phx-keydown='handle_keydown' attribute", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ ~r/<textarea[^>]+phx-keydown="handle_keydown"/,
             "textarea must have phx-keydown=\"handle_keydown\" per spec-1 §6.5"
    end

    test "textarea has placeholder 'Ask...'", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ ~r/placeholder="Ask\.\.\."/
    end

    test "send button is rendered", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ ~r/<button[^>]+aria-label="Send message"/
    end

    test "send button is disabled when input is empty on mount", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      assert has_element?(view, "button[aria-label='Send message'][disabled]")
    end

    test "chat-viewport has phx-hook ChatScroll", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ ~r/id="chat-viewport"[^>]*phx-hook="ChatScroll"/
        or html =~ ~r/phx-hook="ChatScroll"[^>]*id="chat-viewport"/
    end

    test "scroll-cta-dock is present", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ ~r/id="scroll-cta-dock"/
    end

    test "scroll-to-bottom button is present", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ ~r/id="scroll-to-bottom"/
    end

    test "scroll-cta-dock starts hidden", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ ~r/id="scroll-cta-dock"[^>]*class="[^"]*hidden[^"]*"/
    end

    test "chat-viewport has overscroll-contain class", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ ~r/id="chat-viewport"[^>]*class="[^"]*overscroll-contain[^"]*"/
        or html =~ "overscroll-contain",
             "spec-1 \u00a76.2 requires overscroll-contain on #chat-viewport"
    end

    test "composer form state is 'idle' when input is empty on mount", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ ~r/data-chat-composer-state="idle"/,
             "spec-1 \u00a76.5 requires data-chat-composer-state='idle' when input is blank"
    end

    test "composer form has data-chat-composer-form attribute", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "data-chat-composer-form"
    end

    test "composer frame has ui-chat-composer-frame class", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "ui-chat-composer-frame"
    end

    # Negative: textarea must NOT be in a plain <div> without the plane wrapper
    test "composer plane class wraps the form", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      {:ok, doc} = Floki.parse_document(html)
      plane = Floki.find(doc, "[data-chat-composer-row]")
      refute Enum.empty?(plane), "data-chat-composer-row must be present as the plane wrapper"
    end

    # Negative: send button must NOT be missing aria-label
    test "send button has aria-label", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ ~r/<button[^>]+aria-label="Send message"/
    end
  end
```

---

## Step 2 — Write JS unit tests FIRST (Red)

### Setup Vitest

```bash
cd assets
npm install --save-dev vitest @vitest/coverage-v8 jsdom
```

Add to `assets/package.json`:

```json
{
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest"
  }
}
```

Create `assets/vitest.config.js`:

```js
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "jsdom",
    globals: true,
  },
});
```

### `assets/test/hooks/ChatComposer.test.js`

```js
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

  // Positive: resize sets height
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

  // Positive: Enter submits
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

  // Negative: Shift+Enter does NOT submit
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

  // Negative: non-Enter key does NOT submit
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

  // Negative: composing IME input does NOT submit
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
```

### `assets/test/hooks/ChatScroll.test.js`

```js
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

  // Positive: scrollToBottom sets scrollTop = scrollHeight
  it("scrollToBottom sets el.scrollTop to el.scrollHeight", () => {
    const el = makeScrollEl(0, 800, 500);
    const hook = makeHook(el);
    hook.scrollToBottom();
    expect(el.scrollTop).toBe(800);
  });

  // Positive: updated() scrolls when isAtBottom is true
  it("updated scrolls to bottom when isAtBottom is true", () => {
    const el = makeScrollEl(0, 800, 500);
    const hook = makeHook(el);
    hook.isAtBottom = true;
    hook.updated();
    expect(el.scrollTop).toBe(800);
  });

  // Negative: updated() does NOT scroll when user scrolled up
  it("updated does not scroll when isAtBottom is false", () => {
    const el = makeScrollEl(100, 800, 500);
    const hook = makeHook(el);
    hook.isAtBottom = false;
    hook.updated();
    expect(el.scrollTop).toBe(100); // unchanged
  });

  // Positive: onScroll sets isAtBottom true when within 40px of bottom
  // delta = scrollHeight - scrollTop - clientHeight = 600 - 580 - 500 = ... no
  // delta = scrollHeight - scrollTop - clientHeight
  // With scrollHeight=600, clientHeight=500, scrollTop=60: delta = 600-60-500 = 40 (boundary — NOT < 40)
  // Use scrollTop=61: delta = 600-61-500 = 39 < 40 → isAtBottom=true
  it("onScroll sets isAtBottom true when near bottom (within 40px)", () => {
    const el = makeScrollEl(61, 600, 500); // delta = 600-61-500 = 39 < 40
    const hook = makeHook(el);
    hook.onScroll();
    expect(hook.isAtBottom).toBe(true);
  });

  // Negative: onScroll sets isAtBottom false when far from bottom
  it("onScroll sets isAtBottom false when far from bottom (> 40px)", () => {
    // delta = scrollHeight - scrollTop - clientHeight = 600 - 0 - 500 = 100 > 40
    const el = makeScrollEl(0, 600, 500);
    const hook = makeHook(el);
    hook.onScroll();
    expect(hook.isAtBottom).toBe(false);
  });

  // Positive: scroll pill hidden class toggled off when not at bottom
  it("onScroll removes hidden class from scroll-cta-dock when not at bottom", () => {
    const dock = document.createElement("div");
    dock.id = "scroll-cta-dock";
    dock.classList.add("hidden");
    document.body.appendChild(dock);

    const el = makeScrollEl(0, 600, 500); // far from bottom
    const hook = makeHook(el);
    hook.onScroll();

    expect(dock.classList.contains("hidden")).toBe(false);
  });

  // Negative: scroll pill stays hidden when at bottom
  it("onScroll keeps hidden class on scroll-cta-dock when at bottom", () => {
    const dock = document.createElement("div");
    dock.id = "scroll-cta-dock";
    dock.classList.add("hidden");
    document.body.appendChild(dock);

    // at bottom: scrollHeight=600, clientHeight=500, scrollTop=61 -> delta=39 < 40
    const el = makeScrollEl(61, 600, 500);
    const hook = makeHook(el);
    hook.onScroll();

    expect(dock.classList.contains("hidden")).toBe(true);
  });

  // Positive: pushEvent sends scroll_position
  it("onScroll pushes scroll_position event with at_bottom value", () => {
    const el = makeScrollEl(0, 600, 500);
    const hook = makeHook(el);
    hook.onScroll();
    expect(hook.pushEvent).toHaveBeenCalledWith("scroll_position", {
      at_bottom: false,
    });
  });
});
```

Run:

```bash
cd assets && npm test
```

All JS tests fail — hooks do not exist yet. Correct Red state.

---

## Step 3 — Implement `ChatComposer.js` (Green)

`assets/js/hooks/ChatComposer.js`:

```js
const ChatComposer = {
  mounted() {
    this.resize();
    this.el.addEventListener("input", () => this.resize());
    this.el.addEventListener("keydown", (e) => this.onKeyDown(e));
  },

  updated() {
    this.resize();
  },

  resize() {
    const el = this.el;
    el.style.height = "0px";
    const next = Math.min(el.scrollHeight, 192);
    el.style.height = next + "px";
    el.style.overflowY = el.scrollHeight > 192 ? "auto" : "hidden";
  },

  onKeyDown(e) {
    if (e.key === "Enter" && !e.shiftKey && !e.isComposing) {
      e.preventDefault();
      this.el.closest("form")?.requestSubmit();
    }
  },
};

export default ChatComposer;
```

---

## Step 4 — Implement `ChatScroll.js` (Green)

`assets/js/hooks/ChatScroll.js`:

```js
const ChatScroll = {
  mounted() {
    this.isAtBottom = true;
    this.el.addEventListener("scroll", () => this.onScroll(), {
      passive: true,
    });
    this.scrollToBottom();
  },

  updated() {
    if (this.isAtBottom) this.scrollToBottom();
  },

  onScroll() {
    const { scrollTop, scrollHeight, clientHeight } = this.el;
    this.isAtBottom = scrollHeight - scrollTop - clientHeight < 40;
    this.pushEvent("scroll_position", { at_bottom: this.isAtBottom });

    const dock = document.getElementById("scroll-cta-dock");
    if (dock) dock.classList.toggle("hidden", this.isAtBottom);

    const btn = document.getElementById("scroll-to-bottom");
    if (btn) btn.onclick = () => this.scrollToBottom();
  },

  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight;
  },
};

export default ChatScroll;
```

---

## Step 5 — Register hooks in `app.js`

`assets/js/app.js` — add after existing imports:

```js
import ChatScroll from "./hooks/ChatScroll";
import ChatComposer from "./hooks/ChatComposer";

// Update the LiveSocket instantiation:
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: { ChatScroll, ChatComposer },
});
```

---

## Step 6 — Implement the composer markup in `ChatLive.render/1`

Replace the empty `data-chat-bottom-rail` div with the full spec markup from spec-1 §6.5:

```heex
<%!-- Row 3: Composer Plane --%>
<div class="flex flex-col gap-[--space-2]" data-chat-bottom-rail="true">
  <div class="ui-chat-composer-plane relative flex-none
              px-[--space-3] pt-[--space-1] pb-[--space-2]"
       data-chat-composer-row="true">

    <div aria-hidden="true"
         class="ui-chat-composer-seam pointer-events-none absolute
                inset-x-[--space-16] top-0 h-px" />

    <div class="mx-auto w-full max-w-3xl" data-chat-composer-shell="true">
      <form phx-submit="send_message"
            class={[
              "ui-chat-composer-frame ui-chat-composer-frame-hover",
              "relative flex min-h-[--chat-composer-min-height] items-stretch",
              "gap-[--space-2] overflow-hidden rounded-[--chat-composer-radius]",
              "transition-all duration-300",
              "focus-within:ui-chat-composer-frame-focus"
            ]}
            data-chat-composer-form="true"
            data-chat-composer-state={if String.trim(@input) != "", do: "ready", else: "idle"}>

        <textarea id="chat-input"
                  name="input"
                  phx-hook="ChatComposer"
                  phx-keydown="handle_keydown"
                  rows="1"
                  placeholder="Ask..."
                  value={@input}
                  class="flex-1 resize-none bg-transparent
                         px-[--chat-composer-field-padding-inline]
                         py-[--chat-composer-field-padding-block]
                         text-sm outline-none"
                  style="max-height: 192px; overflow-y: hidden;"
                  disabled={@is_sending} />

        <button type="submit"
                disabled={@is_sending || String.trim(@input) == ""}
                class="ui-chat-send-button shrink-0 self-center
                       rounded-[--fva-shell-radius-control]
                       p-[--space-2] mr-[--space-2]
                       transition-all active:scale-95
                       disabled:opacity-40 disabled:cursor-not-allowed"
                aria-label="Send message">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none"
               stroke="currentColor" stroke-width="2.5"
               stroke-linecap="round" stroke-linejoin="round">
            <line x1="22" y1="2" x2="11" y2="13"/>
            <polygon points="22 2 15 22 11 13 2 9 22 2"/>
          </svg>
        </button>
      </form>
    </div>
  </div>
</div>
```

Also add the scroll pill to the viewport row (before the closing `</div>`):

```heex
<div id="scroll-cta-dock"
     class="ui-chat-scroll-cta-dock absolute left-0 right-0 z-10 flex
            justify-center pointer-events-none hidden"
     style={"bottom: calc(var(--chat-scroll-cta-offset) + var(--safe-area-inset-bottom))"}>
  <button id="scroll-to-bottom"
          class="ui-chat-scroll-cta pointer-events-auto focus-ring min-h-11
                 rounded-full px-[--space-4] py-[--space-2] text-[11px]
                 font-bold transition-all hover:scale-[1.03]"
          aria-label="Scroll to bottom">
    ↓ Scroll to bottom
  </button>
</div>
```

And add `phx-hook="ChatScroll"` to the `#chat-viewport` div.

---

## Step 7 — Run all tests (Red → Green)

```bash
# Elixir
mix test test/chat_app_web/live/chat_live_test.exs

# JS
cd assets && npm test && cd ..
```

All tests pass.

---

## Acceptance Criteria

- [ ] All composer markup tests pass (Elixir)
- [ ] All `ChatComposer` JS unit tests pass (8 tests)
- [ ] All `ChatScroll` JS unit tests pass (8 tests)
- [ ] `ChatComposer.js` and `ChatScroll.js` exist in `assets/js/hooks/`
- [ ] Both hooks registered in `app.js` LiveSocket `hooks` object
- [ ] `phx-hook="ChatComposer"` on `<textarea id="chat-input">`
- [ ] `phx-keydown="handle_keydown"` on `<textarea id="chat-input">` (spec-1 §6.5)
- [ ] `phx-hook="ChatScroll"` on `<div id="chat-viewport">`
- [ ] `#scroll-cta-dock` starts with `hidden` class
- [ ] `#chat-viewport` has `overscroll-contain` class (spec-1 §6.2)
- [ ] Composer form has `data-chat-composer-state="idle"` on mount (spec-1 §6.5)
- [ ] `mix test` exits 0
- [ ] `cd assets && npm test` exits 0
