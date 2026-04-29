defmodule ChatAppWeb.Sprint19ADesktopLayoutE2ETest do
  use ChatAppWeb.FeatureCase, async: false

  @moduletag :e2e

  feature "sidebar collapses and expands via header toggle on desktop", %{session: session} do
    session =
      session
      |> visit("/")
      |> execute_script("""
      (() => {
        const sidebar = document.querySelector('#chat-sidebar');
        const chatSurface = document.querySelector('[data-chat-surface="true"]');
        const collapsedAttr = sidebar?.dataset.sidebarCollapsed === "true";
        const collapsedStyle = (sidebar?.getAttribute("style") || "").includes("width: 0px");

        document.body.dataset.sidebarInitialCollapsed =
          collapsedAttr && collapsedStyle ? "true" : "false";
        document.body.dataset.chatWidthCollapsedInitial = chatSurface
          ? String(chatSurface.getBoundingClientRect().width)
          : "0";
      })();
      """)
      |> click(Query.css("button[data-sidebar-toggle='true']"))
      |> assert_has(
        Query.css("#chat-sidebar[data-sidebar-collapsed='false'][style*='width: 16rem']")
      )
      |> assert_has(
        Query.css("button[data-sidebar-toggle='true'][aria-label='Collapse sidebar']")
      )
      |> execute_script("""
      (() => {
        const sidebar = document.querySelector('#chat-sidebar');
        const chatSurface = document.querySelector('[data-chat-surface="true"]');
        const expandedAttr = sidebar?.dataset.sidebarCollapsed === "false";
        const expandedStyle = (sidebar?.getAttribute("style") || "").includes("width: 16rem");

        document.body.dataset.sidebarExpandedAfterToggle =
          expandedAttr && expandedStyle ? "true" : "false";
        document.body.dataset.chatWidthExpanded = chatSurface
          ? String(chatSurface.getBoundingClientRect().width)
          : "0";
      })();
      """)
      |> click(Query.css("button[data-sidebar-toggle='true']"))
      |> assert_has(Query.css("button[data-sidebar-toggle='true'][aria-label='Expand sidebar']"))
      |> execute_script("""
      (() => {
        const sidebar = document.querySelector('#chat-sidebar');
        const collapsedAttr = sidebar?.dataset.sidebarCollapsed === "true";
        const collapsedStyle = (sidebar?.getAttribute("style") || "").includes("width: 0px");

        document.body.dataset.sidebarCollapsedAfterSecondToggle =
          collapsedAttr && collapsedStyle ? "true" : "false";
      })();
      """)

    assert_has(session, Query.css("body[data-sidebar-initial-collapsed='true']"))
    assert_has(session, Query.css("body[data-sidebar-expanded-after-toggle='true']"))
    assert_has(session, Query.css("body[data-sidebar-collapsed-after-second-toggle='true']"))
  end

  feature "API cost tracker is completely removed from the DOM", %{session: session} do
    session =
      session
      |> visit("/")
      |> refute_has(Query.css("[data-usage-cost]"))

    assert_has(session, Query.css("button[data-sidebar-toggle='true']"))
  end

  feature "header icon buttons are keyboard accessible", %{session: session} do
    session =
      session
      |> visit("/")
      |> assert_has(Query.css("button[data-sidebar-toggle='true'].focus-ring"))
      |> assert_has(Query.css("button[data-new-chat-trigger='true'].focus-ring"))
      |> assert_has(Query.css("button[phx-click='toggle_settings'].focus-ring"))
      |> execute_script(
        "document.querySelector(\"button[phx-click='toggle_settings']\")?.focus();"
      )
      |> send_keys([:enter])
      |> assert_has(Query.css("[data-settings-drawer]"))
      |> execute_script(
        "document.querySelector(\"button[data-new-chat-trigger='true']\")?.focus();"
      )
      |> send_keys([:enter])

    assert_has(session, Query.css("[data-homepage-chat-intro='true']"))
  end

  feature "sidebar toggle does not vertically shift the transcript viewport", %{session: session} do
    session =
      session
      |> visit("/")
      |> execute_script("""
      (() => {
        const viewport = document.querySelector('#chat-viewport');
        const rect = viewport?.getBoundingClientRect();
        document.body.dataset.viewportTopBefore = rect ? String(Math.round(rect.top)) : "missing";
        document.body.dataset.viewportHeightBefore = rect ? String(Math.round(rect.height)) : "missing";
      })();
      """)
      |> click(Query.css("button[data-sidebar-toggle='true']"))
      |> assert_has(Query.css("#chat-sidebar[data-sidebar-collapsed='false']"))
      |> execute_script("""
      (() => {
        const viewport = document.querySelector('#chat-viewport');
        const rect = viewport?.getBoundingClientRect();
        const topBefore = document.body.dataset.viewportTopBefore;
        const heightBefore = document.body.dataset.viewportHeightBefore;
        const topAfter = rect ? String(Math.round(rect.top)) : "missing";
        const heightAfter = rect ? String(Math.round(rect.height)) : "missing";

        document.body.dataset.viewportDidNotJump =
          topBefore === topAfter && heightBefore === heightAfter ? "true" : "false";
      })();
      """)

    assert_has(session, Query.css("body[data-viewport-did-not-jump='true']"))
  end
end
