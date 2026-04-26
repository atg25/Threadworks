---
status: complete
---

# Sprint 1.4 — Hero Intro Component

**Spec:** spec-1 §6.2, §6.3  
**Goal:** Implement the `hero_intro/1` function component and `proof_points/0` helper. The hero must render when `hero_state == true` (initial mount), include all required data attributes, display the service chip cluster, heading, subheading, and three proof-point cards.  
**Depends on:** sprint-1.3 (ChatLive exists, grid renders, placeholder `data-homepage-chat-intro` div present)  
**Delivers:** A visually complete hero section visible on first load, fully tested for structure and content.

---

## TDD Approach

| Layer                  | Tool                           | Assertions                                      |
| ---------------------- | ------------------------------ | ----------------------------------------------- |
| Component presence     | `Phoenix.LiveViewTest`         | Hero root element present on mount              |
| Service chips          | `Phoenix.LiveViewTest` + Floki | Three chip `<span>` elements with correct text  |
| Heading                | `Phoenix.LiveViewTest`         | `<h2>` with correct text and classes            |
| Subheading             | `Phoenix.LiveViewTest`         | `<p>` with correct text                         |
| Proof cards            | `Phoenix.LiveViewTest` + Floki | Exactly 3 cards, each with a title and body     |
| Hero hidden after send | `Phoenix.LiveViewTest`         | After sending a message, hero element is absent |
| Animation classes      | `Phoenix.LiveViewTest`         | `animate-in`, `fade-in` present on hero wrapper |

---

## Step 1 — Write tests FIRST (Red)

### Append to `test/chat_app_web/live/chat_live_test.exs`

Add a new `describe` block at the end of the existing test module:

```elixir
  describe "hero intro component" do
    # Positive: hero renders on mount
    test "hero intro is visible on initial mount", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      assert has_element?(view, "[data-homepage-chat-intro]")
    end

    test "hero contains the service chip cluster", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "data-homepage-service-chip"
    end

    test "hero has three service chips: Chat, Search, Publish", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ ">Chat<"
      assert html =~ ">Search<"
      assert html =~ ">Publish<"
    end

    test "hero heading renders expected text", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "One compact system for AI-assisted work"
    end

    test "hero heading uses theme-display class", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ ~r/<h2[^>]+class="[^"]*theme-display[^"]*"/
    end

    test "hero subheading renders expected text", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Chat with your AI assistant"
    end

    test "hero has exactly three proof-point cards", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      {:ok, doc} = Floki.parse_document(html)
      cards = Floki.find(doc, "[data-homepage-proof-card]")
      assert length(cards) == 3
    end

    test "proof cards contain correct titles", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "One compact system"
      assert html =~ "Background AI workflows"
      assert html =~ "Governed by default"
    end

    test "hero wrapper has animate-in class", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "animate-in"
    end

    test "hero wrapper has fade-in class", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "fade-in"
    end

    test "hero wrapper has slide-in-from-top-4 class", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "slide-in-from-top-4",
             "spec-1 \u00a76.3 requires slide-in-from-top-4 on the hero wrapper"
    end

    test "proof strip container is present", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "data-homepage-proof-strip"
    end

    # Negative: hero is NOT present when hero_state is false
    test "hero is hidden when hero_state is false", %{conn: conn} do
      # Test-harness path: in test env only, query param toggles initial hero state.
      # Real send_message flow is implemented in sprint 1.6.
      {:ok, view, _html} = live(conn, "/?hero_state=false")
      refute has_element?(view, "[data-homepage-chat-intro]")
      assert has_element?(view, "[data-chat-message-stack]")
    end

    # Negative: proof-point strip must NOT be empty
    test "proof strip is not empty", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      {:ok, doc} = Floki.parse_document(html)
      cards = Floki.find(doc, "[data-homepage-proof-card]")
      refute Enum.empty?(cards), "proof strip must contain at least one card"
    end

    # Negative: heading must not be blank
    test "hero heading is not blank", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      {:ok, doc} = Floki.parse_document(html)
      [heading] = Floki.find(doc, "h2")
      text = Floki.text(heading) |> String.trim()
      refute text == "", "hero h2 must contain text"
    end
  end
```

Run:

```bash
mix test test/chat_app_web/live/chat_live_test.exs
```

Expected: hero-specific tests fail because the `hero_intro/1` component is a placeholder stub. Correct Red state.

---

## Step 2 — Implement `hero_intro/1` (Green)

Replace the placeholder `data-homepage-chat-intro` div in `ChatLive` with the full function component. The component goes in `chat_live.ex` as a private function:

```elixir
defp hero_intro(assigns) do
  ~H"""
  <div data-homepage-chat-intro="true"
       class="mx-auto flex w-full max-w-4xl flex-col items-center justify-center
              px-[--space-3] text-center animate-in fade-in slide-in-from-top-4
              duration-700 ease-out fill-mode-both
              pb-[--hero-intro-stack-gap] space-y-[--hero-intro-stack-gap]">

    <%!-- Service chips cluster --%>
    <div class="ui-chat-brand-chip-cluster flex flex-wrap items-center justify-center
                gap-x-[--hero-badge-gap] gap-y-[--phi-2] rounded-full
                px-[--hero-badge-padding-inline] py-[--hero-badge-padding-block]
                text-[0.66rem] font-medium uppercase tracking-[0.18em] text-foreground/56">
      <span data-homepage-service-chip="true">Chat</span>
      <span aria-hidden="true" class="hidden text-foreground/20 sm:inline">/</span>
      <span data-homepage-service-chip="true">Search</span>
      <span aria-hidden="true" class="hidden text-foreground/20 sm:inline">/</span>
      <span data-homepage-service-chip="true">Publish</span>
    </div>

    <%!-- Hero heading --%>
    <h2 class="theme-display text-foreground font-semibold text-balance"
        style="max-width: var(--hero-title-max-width);
               font-size: var(--hero-title-font-size);
               line-height: var(--hero-title-line-height);
               letter-spacing: var(--tier-display-tracking);">
      One compact system for AI-assisted work
    </h2>

    <%!-- Hero subheading --%>
    <p class="theme-body text-foreground/64"
       style="max-width: var(--hero-greeting-max-width);
              font-size: var(--hero-body-font-size);
              line-height: var(--hero-body-line-height);">
      Chat with your AI assistant. Ask anything.
    </p>

    <%!-- Proof-point cards strip --%>
    <div class="grid w-full max-w-5xl gap-3 pt-[--phi-2] text-left sm:grid-cols-3"
         data-homepage-proof-strip="true">
      <%= for %{title: title, body: body} <- proof_points() do %>
        <div class="rounded-3xl border border-foreground/10 bg-background/75
                    px-4 py-4 shadow-[0_18px_50px_-32px_rgba(15,23,42,0.28)]
                    backdrop-blur-sm" data-homepage-proof-card="true">
          <p class="text-xs font-semibold uppercase tracking-[0.16em] text-foreground/46">
            <%= title %>
          </p>
          <p class="mt-2 text-sm leading-6 text-foreground/74">
            <%= body %>
          </p>
        </div>
      <% end %>
    </div>
  </div>
  """
end

defp proof_points do
  [
    %{
      title: "One compact system",
      body:  "Chat, search, jobs, and publishing stay inside one app footprint."
    },
    %{
      title: "Background AI workflows",
      body:  "Deferred jobs keep long-running work visible, retryable, and under control."
    },
    %{
      title: "Governed by default",
      body:  "Role-aware tools, prompts, and workflow actions stay aligned with the operator model."
    }
  ]
end
```

---

## Step 3 — Wire `hero_intro` into the message viewport

In `ChatLive.render/1`, replace the placeholder in the viewport row with:

```heex
<%!-- Row 2: Message Viewport --%>
<div class="relative flex h-full min-h-0 w-full flex-col overflow-hidden"
     data-chat-message-region="true">

  <%!-- Radial glow --%>
  <div class={[
    "ui-chat-viewport-glow pointer-events-none absolute inset-x-0 top-0",
    if(@hero_state, do: "h-24 opacity-45", else: "h-32 opacity-70")
  ]} aria-hidden="true" />

  <%!-- Scrollable transcript --%>
  <div id="chat-viewport"
       class="ui-chat-transcript-plane ui-chat-transcript-frame z-10 flex h-full
              min-h-0 flex-1 flex-col overflow-y-auto overscroll-contain"
       data-chat-message-viewport="true"
       data-chat-transcript-mode="embedded">

    <div class={[
      "shrink-0 w-full flex min-h-full flex-col",
      if(@hero_state, do: "justify-center", else: "justify-end")
    ]} data-chat-message-stack="true">

      <%= if @hero_state do %>
        <.hero_intro />
      <% else %>
        <%!-- message bubbles — sprint 1.8 --%>
      <% end %>
    </div>
  </div>
</div>
```

---

## Step 4 — Run tests (Red → Green)

```bash
mix test test/chat_app_web/live/chat_live_test.exs
```

All hero tests now pass. The "hero hidden when hero_state is false" test passes because `data-chat-message-stack` is always rendered.

---

## Step 5 — Run full suite

```bash
mix test
```

All previous sprint tests still pass. Total tests: ~62.

---

## Acceptance Criteria

- [ ] `hero_intro/1` is a private function component in `ChatLive`
- [ ] `proof_points/0` returns a list of exactly 3 maps with `:title` and `:body`
- [ ] Hero renders on initial mount (`hero_state: true`)
- [ ] Three service chips ("Chat", "Search", "Publish") present
- [ ] `<h2>` contains "One compact system for AI-assisted work"
- [ ] `<p>` subheading present with expected text
- [ ] Exactly 3 `data-homepage-proof-card` elements
- [ ] `animate-in`, `fade-in`, and `slide-in-from-top-4` classes present on hero wrapper
- [ ] All hero tests pass
- [ ] `mix test` exits 0

---

## Out of Scope for This Sprint

- Composer markup (sprint 1.5)
- Hero disappearing on send (sprint 1.6 — requires event handler)
- Message bubble rendering (sprint 1.8)
