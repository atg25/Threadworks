---
status: complete
---

# Sprint 1.2 — CSS Architecture & Font Setup

**Spec:** spec-1 §2, §3  
**Goal:** Copy the four reference CSS files, wire them into `app.css` in the correct import order, and bind the three Google Fonts families to CSS custom properties. The design system tokens must resolve correctly in the browser.  
**Depends on:** sprint-1.1 (project scaffolded, Node deps installed)  
**Delivers:** A compilable CSS bundle with the full `foundation.css` token system, `chat.css` component classes, and correct font families applied.

---

## TDD Approach

CSS cannot be unit-tested by ExUnit. Testing strategy:

| Layer                          | Tool                         | What we assert                                      |
| ------------------------------ | ---------------------------- | --------------------------------------------------- |
| File presence                  | ExUnit shell assertion       | The four CSS files exist at their destination paths |
| Import order                   | ExUnit regex on file content | `app.css` imports files in the required sequence    |
| CSS custom property resolution | Wallaby E2E (sprint 1.10)    | `--background` resolves to expected oklch value     |
| Font loading                   | Wallaby E2E (sprint 1.10)    | Computed font-family includes IBM Plex Sans         |

For this sprint, write the file-presence and import-order tests now (Red), then implement (Green).

---

## Prerequisite — Configure Vite for Tailwind CSS v4

Spec-1 uses `@tailwindcss/vite` (not the Tailwind CLI hex package or a PostCSS plugin). Before writing any CSS, wire the plugin into the Phoenix-generated `assets/vite.config.js`:

```js
import { defineConfig } from "vite";
import tailwindcss from "@tailwindcss/vite";

// Keep any existing Phoenix-generated settings (HMR, watcher, etc.)
// and add tailwindcss() to the plugins array:
export default defineConfig({
  plugins: [
    tailwindcss(),
    // ... existing Phoenix plugins
  ],
});
```

> **Note:** `mix phx.new` scaffolds a `vite.config.js` with Phoenix-specific HMR and watcher entries. Do not replace it entirely — only add the `tailwindcss` import and prepend `tailwindcss()` to the `plugins` array.

Verify Vite picks up Tailwind without errors:

```bash
cd chat_app/assets && npx vite build --mode development 2>&1 | head -30 && cd ../..
```

---

## Step 1 — Write tests FIRST (Red)

### `test/chat_app_web/css_architecture_test.exs`

```elixir
defmodule ChatAppWeb.CSSArchitectureTest do
  use ExUnit.Case, async: true

  @css_dir Path.join([File.cwd!(), "assets", "css"])
  @app_css Path.join(@css_dir, "app.css")

  # --- File presence (positive) ---

  test "foundation.css exists in assets/css" do
    assert File.exists?(Path.join(@css_dir, "foundation.css"))
  end

  test "shell.css exists in assets/css" do
    assert File.exists?(Path.join(@css_dir, "shell.css"))
  end

  test "utilities.css exists in assets/css" do
    assert File.exists?(Path.join(@css_dir, "utilities.css"))
  end

  test "chat.css exists in assets/css" do
    assert File.exists?(Path.join(@css_dir, "chat.css"))
  end

  test "app.css exists in assets/css" do
    assert File.exists?(@app_css)
  end

  # --- Import order (positive) ---

  test "app.css imports tailwindcss before foundation" do
    content = File.read!(@app_css)
    tw_pos  = :binary.match(content, "@import \"tailwindcss\"") |> elem(0)
    fn_pos  = :binary.match(content, "./foundation.css")       |> elem(0)
    assert tw_pos < fn_pos, "tailwindcss must be imported before foundation.css"
  end

  test "app.css imports foundation before shell" do
    content = File.read!(@app_css)
    fn_pos  = :binary.match(content, "./foundation.css") |> elem(0)
    sh_pos  = :binary.match(content, "./shell.css")      |> elem(0)
    assert fn_pos < sh_pos, "foundation.css must be imported before shell.css"
  end

  test "app.css imports shell before utilities" do
    content = File.read!(@app_css)
    sh_pos  = :binary.match(content, "./shell.css")      |> elem(0)
    ut_pos  = :binary.match(content, "./utilities.css")  |> elem(0)
    assert sh_pos < ut_pos, "shell.css must be imported before utilities.css"
  end

  test "app.css imports utilities before chat" do
    content = File.read!(@app_css)
    ut_pos  = :binary.match(content, "./utilities.css") |> elem(0)
    ch_pos  = :binary.match(content, "./chat.css")      |> elem(0)
    assert ut_pos < ch_pos, "utilities.css must be imported before chat.css"
  end

  # --- Font var binding (positive) ---

  test "app.css declares --font-ibm-plex-sans custom property" do
    content = File.read!(@app_css)
    assert content =~ "--font-ibm-plex-sans"
  end

  test "app.css declares --font-ibm-plex-mono custom property" do
    content = File.read!(@app_css)
    assert content =~ "--font-ibm-plex-mono"
  end

  test "app.css declares --font-fraunces custom property" do
    content = File.read!(@app_css)
    assert content =~ "--font-fraunces"
  end

  # --- Dark mode variant (positive) ---

  test "app.css declares @custom-variant dark" do
    content = File.read!(@app_css)
    assert content =~ "@custom-variant dark"
  end

  # --- Negative: wrong import order would be caught ---

  test "chat.css is NOT imported before utilities.css in app.css" do
    content = File.read!(@app_css)
    # If chat appears before utilities, the order is wrong
    case {:binary.match(content, "./chat.css"), :binary.match(content, "./utilities.css")} do
      {{ch_pos, _}, {ut_pos, _}} ->
        assert ut_pos < ch_pos,
               "chat.css must not appear before utilities.css — it depends on .focus-ring from utilities"
      _ ->
        flunk("One or both of chat.css / utilities.css import lines not found in app.css")
    end
  end

  # --- Negative: foundation.css must contain --background token ---

  test "foundation.css defines --background token" do
    content = File.read!(Path.join(@css_dir, "foundation.css"))
    assert content =~ "--background", "foundation.css must define the --background design token"
  end

  test "foundation.css defines --foreground token" do
    content = File.read!(Path.join(@css_dir, "foundation.css"))
    assert content =~ "--foreground"
  end

  test "foundation.css defines --glass-sublayer token" do
    content = File.read!(Path.join(@css_dir, "foundation.css"))
    assert content =~ "--glass-sublayer"
  end

  # --- Negative: chat.css must define ui-chat-composer-plane ---

  test "chat.css defines .ui-chat-composer-plane" do
    content = File.read!(Path.join(@css_dir, "chat.css"))
    assert content =~ "ui-chat-composer-plane",
           "chat.css must define the composer plane class — required for gradient background"
  end

  test "chat.css defines .ui-chat-composer-seam" do
    content = File.read!(Path.join(@css_dir, "chat.css"))
    assert content =~ "ui-chat-composer-seam"
  end

  test "chat.css defines .ui-chat-header-surface" do
    content = File.read!(Path.join(@css_dir, "chat.css"))
    assert content =~ "ui-chat-header-surface"
  end

  # --- Tailwind v4 plugin declarations (positive) ---

  test "app.css declares @plugin for @tailwindcss/typography" do
    content = File.read!(@app_css)
    assert content =~ ~r/@plugin\s+"@tailwindcss\/typography"/,
           "app.css must use @plugin syntax (Tailwind v4) — not tailwind.config.js"
  end

  test "app.css declares @plugin for tailwindcss-animate" do
    content = File.read!(@app_css)
    assert content =~ ~r/@plugin\s+"tailwindcss-animate"/,
           "app.css must use @plugin syntax (Tailwind v4) — not tailwind.config.js"
  end

  # --- Root layout: Google Fonts link tag (spec-1 §2, §15 checklist item 2) ---

  test "root.html.heex contains Google Fonts preconnect links" do
    heex = File.read!(Path.join([File.cwd!(), "lib", "chat_app_web",
                                  "components", "layouts", "root.html.heex"]))
    assert heex =~ "fonts.googleapis.com",
           "root.html.heex must include Google Fonts preconnect link (spec-1 §2, §15 item 2)"
    assert heex =~ "fonts.gstatic.com"
    assert heex =~ "IBM+Plex+Sans"
  end
end
```

Run:

```bash
mix test test/chat_app_web/css_architecture_test.exs
```

All tests fail — the CSS files do not exist yet. That is the expected Red state.

---

## Step 2 — Copy the four CSS files (Green)

From the workspace root (`/Users/agard/NJIT/IS322/Final/`):

```bash
REF=docs/_references/ai_mcp_chat_ordo/src/app/styles
DST=chat_app/assets/css

cp "$REF/foundation.css" "$DST/foundation.css"
cp "$REF/shell.css"      "$DST/shell.css"
cp "$REF/utilities.css"  "$DST/utilities.css"
cp "$REF/chat.css"       "$DST/chat.css"
```

Verify no truncation:

```bash
wc -l $DST/foundation.css $DST/shell.css $DST/utilities.css $DST/chat.css
```

Each file must have more than 10 lines (they are all substantial). If any show 0 lines, the copy failed.

---

## Step 3 — Write `assets/css/app.css`

Replace the scaffolded `app.css` entirely:

```css
/* ─── Tailwind base ─────────────────────────────────────────── */
@import "tailwindcss";

/* ─── Tailwind v4 plugins (use @plugin, not tailwind.config.js) */
@plugin "@tailwindcss/typography";
@plugin "tailwindcss-animate";

/* ─── Design system (order is load-order-sensitive) ─────────── */
@import "./foundation.css";
@import "./shell.css";
@import "./utilities.css";
@import "./chat.css";

/* ─── Font family custom property bindings ───────────────────
   Must be declared so foundation.css --font-body/display/mono
   can resolve. Google Fonts link tag loads the actual faces.   */
:root {
  --font-ibm-plex-sans: "IBM Plex Sans", sans-serif;
  --font-ibm-plex-mono: "IBM Plex Mono", monospace;
  --font-fraunces: "Fraunces", serif;
}

/* ─── Dark mode: class-based (not prefers-color-scheme) ─────── */
@custom-variant dark (&:where(.dark, .dark *));
```

---

## Step 4 — Add Google Fonts link to root layout

Open `lib/chat_app_web/components/layouts/root.html.heex` and add inside `<head>`, **before** the `<link rel="stylesheet">` tag:

```heex
<%!-- Google Fonts: IBM Plex Sans, IBM Plex Mono, Fraunces --%>
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link
  href="https://fonts.googleapis.com/css2?family=Fraunces:ital,opsz,wght@0,9..144,400;0,9..144,560;1,9..144,400&family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@400;500;600;700&display=swap"
  rel="stylesheet"
/>
```

---

## Step 5 — Run tests (Red → Green)

```bash
mix test test/chat_app_web/css_architecture_test.exs
```

All 23 tests should now pass. If any fail, the most likely causes are:

| Failure                            | Fix                                                          |
| ---------------------------------- | ------------------------------------------------------------ |
| File not found                     | `cp` command did not run from the right directory            |
| Import order assertion fails       | Check `app.css` — one import line is out of order            |
| `--glass-sublayer` not found       | The `foundation.css` copy is the wrong file (check ref path) |
| `ui-chat-composer-plane` not found | The `chat.css` copy is wrong — verify the ref path           |

---

## Step 6 — Verify CSS bundle compiles

```bash
cd chat_app
mix assets.build
```

No Tailwind / PostCSS errors. If `tailwindcss-animate` is missing, run:

```bash
cd assets && npm install && cd ..
```

---

## Acceptance Criteria

- [ ] All 23 `CSSArchitectureTest` tests pass
- [ ] `mix assets.build` exits 0
- [ ] `priv/static/assets/app.css` is generated and is non-empty
- [ ] `foundation.css`, `shell.css`, `utilities.css`, `chat.css` all present in `assets/css/`
- [ ] Google Fonts `<link>` tags present in `root.html.heex`
- [ ] `app.css` declares all three `--font-*` custom properties

---

## Out of Scope for This Sprint

- Height propagation on `<html>`/`<body>` (sprint 1.3)
- Any LiveView or component markup
- Browser-level visual verification (sprint 1.10)
