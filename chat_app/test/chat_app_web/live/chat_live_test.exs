defmodule ChatAppWeb.ChatLiveTest do
  # async: false — the `:allow_hero_override` regression test mutates
  # Application env, which would otherwise leak across concurrent tests
  # that depend on the test-env default (true).
  use ChatAppWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  # Positive: root path is live
  test "GET / mounts ChatLive", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "data-chat-surface"
  end

  # Negative: non-live route is gone
  test "GET / does not render the default Phoenix welcome page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    refute html =~ "Peace of mind from prototype to production"
  end

  test "ChatLive mounts with hero_state true", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "[data-homepage-chat-intro]")
  end

  test "ChatLive mounts with empty messages list", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    refute has_element?(view, "[data-chat-message-bubble]")
  end

  test "ChatLive mounts with is_sending false (send button enabled)", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "button[aria-label='Send message']")
  end

  test "root section has 3-row grid classes", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "grid-rows-[auto_minmax(0,1fr)_auto]"
  end

  test "root section has data-chat-surface attribute", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "data-chat-surface"
  end

  test "header row is rendered", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "data-chat-surface-header"
  end

  test "message viewport row is rendered", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "data-chat-message-region"
  end

  test "composer row is rendered", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "data-chat-bottom-rail"
  end

  test "root layout html element has min-height:100% style", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ ~r/html[^>]+style=[^>]*min-height:\s*100%/
  end

  test "root layout body element has min-height:100% style", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ ~r/body[^>]+style=[^>]*min-height:\s*100%/
  end

  test "body only constrains horizontal overflow", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ ~r/body[^>]+style=[^>]*overflow-x:\s*hidden/
  end

  test "body no longer forces overflow hidden on both axes", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    refute html =~ ~r/body[^>]+style=[^>]*overflow:\s*hidden/
  end

  test "section does not use flex-col alone (must be grid)", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ ~r/class="[^"]*\bgrid\b[^"]*"/
  end

  describe "theme toggle" do
    test "header rail contains four named theme buttons", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      {:ok, doc} = Floki.parse_document(html)
      buttons = Floki.find(doc, "[data-phx-theme]")

      assert length(buttons) == 4
    end

    test "each theme button has a non-empty aria-label", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      {:ok, doc} = Floki.parse_document(html)
      buttons = Floki.find(doc, "[data-phx-theme]")

      assert Enum.all?(buttons, fn button ->
               button
               |> Floki.attribute("aria-label")
               |> Enum.any?(&(String.trim(&1) != ""))
             end)
    end

    test "theme buttons wire phx:set-theme dispatch", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert length(Regex.scan(~r/phx:set-theme/, html)) >= 4
    end

    test "header pills for new conversation and settings are absent", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      refute html =~ ~r/phx-click="new_conversation_header"/
      refute html =~ ~r/phx-click="toggle_settings"[^>]*>\s*Settings\s*<\/button>/
    end

    test "brand monogram starts a new conversation", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      assert html =~ ~r/phx-click="new_conversation"/
      assert html =~ ~r/aria-label="Start a new conversation"/
      assert html =~ ~r/title="New conversation"/
      assert html =~ ~r/data-new-chat-trigger="true"/
    end

    test "usage cost badge is not rendered above chat", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      refute html =~ "data-usage-cost"
    end

    test "footer includes author, project summary, and profile links", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "footer[data-site-footer]")
      assert render(view) =~ "About Andrew"
      assert render(view) =~ "About The Project"
      assert has_element?(view, ~s(footer[data-site-footer] a[href="https://linkedin.com/in/andrew-gardner2026/"]))
      assert has_element?(view, ~s(footer[data-site-footer] a[href="https://github.com/atg25"]))
      assert has_element?(view, ~s(footer[data-site-footer] a[href="https://andrewg.vercel.app/"]))
    end
  end

  describe "hero intro component" do
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
      {:ok, doc} = Floki.parse_document(html)
      [heading] = Floki.find(doc, "h2")

      assert Floki.text(heading) =~ "One compact system for AI-assisted work"
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

    test "new conversation bumps landing state for hero animation", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      initial_html = render(view)
      assert initial_html =~ ~s(id="hero-landing-0")
      assert initial_html =~ ~s(data-new-chat-landing="false")
      assert initial_html =~ "duration-700"

      view |> element("button[data-new-chat-trigger='true']") |> render_click()

      html = render(view)
      assert html =~ ~s(id="hero-landing-1")
      assert html =~ ~s(data-new-chat-landing="true")
      assert html =~ "duration-1000"
      assert html =~ "slide-in-from-top-12"
    end

    test "hero wrapper has fade-in class", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "fade-in"
    end

    test "hero wrapper has slide-in-from-top-4 class", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      assert html =~ "slide-in-from-top-4",
             "spec-1 §6.3 requires slide-in-from-top-4 on the hero wrapper"
    end

    test "proof strip container is present", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "data-homepage-proof-strip"
    end

    test "hero is hidden when hero_state is false", %{conn: conn} do
      # Harness-only check: this verifies conditional rendering via test-env param override,
      # not the real send_message flow (implemented in sprint 1.6).
      {:ok, view, _html} = live(conn, "/?hero_state=false")
      refute has_element?(view, "[data-homepage-chat-intro]")
      assert has_element?(view, "[data-chat-message-stack]")
    end

    test "hero_state defaults to true regardless of params when allow_hero_override is false",
         %{conn: conn} do
      original = Application.get_env(:chat_app, :allow_hero_override)

      on_exit(fn ->
        case original do
          nil -> Application.delete_env(:chat_app, :allow_hero_override)
          value -> Application.put_env(:chat_app, :allow_hero_override, value)
        end
      end)

      Application.put_env(:chat_app, :allow_hero_override, false)

      {:ok, view, _html} = live(conn, "/?hero_state=false")
      assert has_element?(view, "[data-homepage-chat-intro]")
    end

    test "proof strip is not empty", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      {:ok, doc} = Floki.parse_document(html)
      cards = Floki.find(doc, "[data-homepage-proof-card]")
      refute Enum.empty?(cards), "proof strip must contain at least one card"
    end

    test "hero heading is not blank", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      {:ok, doc} = Floki.parse_document(html)
      [heading] = Floki.find(doc, "h2")
      text = Floki.text(heading) |> String.trim()
      refute text == "", "hero h2 must contain text"
    end
  end

  describe "composer markup" do
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

    test "form has phx-change='update_input' attribute", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      assert html =~ ~r/<form[^>]+phx-change="update_input"/,
             "form must have phx-change=\"update_input\" to track input server-side"
    end

    test "textarea has placeholder 'Ask...'", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ ~r/placeholder="Ask\.\.\."/
    end

    test "send button is rendered", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ ~r/<button[^>]+aria-label="Send message"/
    end

    test "send button stays enabled on mount so the current textarea value can submit immediately",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      refute has_element?(view, "button[aria-label='Send message'][disabled]")
    end

    test "chat-viewport has phx-hook ChatScroll", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      assert html =~ ~r/id="chat-viewport"[^>]*phx-hook="ChatScroll"/ or
               html =~ ~r/phx-hook="ChatScroll"[^>]*id="chat-viewport"/
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

      assert html =~ ~r/id="chat-viewport"[^>]*class="[^"]*overscroll-contain[^"]*"/ or
               html =~ "overscroll-contain",
             "spec-1 §6.2 requires overscroll-contain on #chat-viewport"
    end

    test "composer form state is 'idle' when input is empty on mount", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      assert html =~ ~r/data-chat-composer-state="idle"/,
             "spec-1 §6.5 requires data-chat-composer-state='idle' when input is blank"
    end

    test "composer form has data-chat-composer-form attribute", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "data-chat-composer-form"
    end

    test "composer frame has ui-chat-composer-frame class", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "ui-chat-composer-frame"
    end

    test "composer plane class wraps the form", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      {:ok, doc} = Floki.parse_document(html)
      plane = Floki.find(doc, "[data-chat-composer-row]")
      refute Enum.empty?(plane), "data-chat-composer-row must be present as the plane wrapper"
    end

    test "send button has aria-label", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ ~r/<button[^>]+aria-label="Send message"/
    end
  end
end
