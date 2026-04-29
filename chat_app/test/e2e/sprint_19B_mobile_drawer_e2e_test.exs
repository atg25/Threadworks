defmodule ChatAppWeb.Sprint19BMobileDrawerE2ETest do
  use ChatAppWeb.FeatureCase, async: false

  @moduletag :e2e

  feature "sidebar behaves as off-canvas drawer on mobile viewports", %{session: session} do
    session =
      session
      |> resize_window(390, 844)
      |> visit("/")
      |> assert_has(Query.css(".phx-connected"))
      |> execute_script("""
      (() => {
        const chatSurface = document.querySelector('[data-chat-surface="true"]');
        document.body.dataset.chatWidthBeforeMobileDrawer = chatSurface
          ? String(Math.round(chatSurface.getBoundingClientRect().width))
          : "missing";
      })();
      """)
      |> assert_has(Query.css("button[data-sidebar-toggle='true']"))
      |> execute_script("""
      document.querySelector("button[data-sidebar-toggle='true']")?.click();
      """)
      |> assert_has(Query.css("#chat-sidebar[data-sidebar-collapsed='false']"))
      |> execute_script("""
      (() => {
        const sidebar = document.querySelector('#chat-sidebar');
        const chatSurface = document.querySelector('[data-chat-surface="true"]');
        const computed = sidebar ? window.getComputedStyle(sidebar) : null;
        const rect = sidebar ? sidebar.getBoundingClientRect() : null;
        const widthBefore = document.body.dataset.chatWidthBeforeMobileDrawer;
        const widthAfter = chatSurface
          ? String(Math.round(chatSurface.getBoundingClientRect().width))
          : "missing";

        const isMobileDrawer =
          sidebar &&
          sidebar.classList.contains('absolute') &&
          sidebar.classList.contains('z-30') &&
          sidebar.classList.contains('md:relative') &&
          computed &&
          computed.position === 'absolute' &&
          computed.display !== 'none' &&
          rect &&
          Math.round(rect.width) > 0;

        document.body.dataset.mobileDrawerReady = isMobileDrawer ? "true" : "false";
        document.body.dataset.chatWidthStableOnMobileDrawer = widthBefore === widthAfter ? "true" : "false";
      })();
      """)

    assert_has(session, Query.css("body[data-mobile-drawer-ready='true']"))
    assert_has(session, Query.css("body[data-chat-width-stable-on-mobile-drawer='true']"))
  end

  feature "clicking the mobile backdrop overlay closes the sidebar", %{session: session} do
    session =
      session
      |> resize_window(390, 844)
      |> visit("/")
      |> assert_has(Query.css(".phx-connected"))
      |> assert_has(Query.css("button[data-sidebar-toggle='true']"))
      |> execute_script("""
      document.querySelector("button[data-sidebar-toggle='true']")?.click();
      """)
      |> assert_has(Query.css("#chat-sidebar[data-sidebar-collapsed='false']"))
      |> assert_has(Query.css("[data-mobile-backdrop='true']"))
      |> execute_script("""
      document.querySelector("[data-mobile-backdrop='true']")?.click();
      """)
      |> refute_has(Query.css("[data-mobile-backdrop='true']"))

    assert_has(session, Query.css("#chat-sidebar[data-sidebar-collapsed='true']", visible: false))
  end

  feature "open drawer transitions from mobile overlay to desktop column on resize", %{
    session: session
  } do
    session =
      session
      |> resize_window(390, 844)
      |> visit("/")
      |> assert_has(Query.css(".phx-connected"))
      |> assert_has(Query.css("button[data-sidebar-toggle='true']"))
      |> execute_script("""
      document.querySelector("button[data-sidebar-toggle='true']")?.click();
      """)
      |> assert_has(Query.css("#chat-sidebar[data-sidebar-collapsed='false']"))
      |> execute_script("""
      (() => {
        const sidebar = document.querySelector('#chat-sidebar');
        const computed = sidebar ? window.getComputedStyle(sidebar) : null;
        document.body.dataset.sidebarMobilePosition = computed ? computed.position : "missing";
      })();
      """)
      |> resize_window(1024, 844)
      |> execute_script("""
      (() => {
        const sidebar = document.querySelector('#chat-sidebar');
        const computed = sidebar ? window.getComputedStyle(sidebar) : null;
        document.body.dataset.sidebarDesktopPosition = computed ? computed.position : "missing";
        document.body.dataset.sidebarDesktopDisplay = computed ? computed.display : "missing";
      })();
      """)

    assert_has(session, Query.css("body[data-sidebar-mobile-position='absolute']"))
    assert_has(session, Query.css("body[data-sidebar-desktop-position='relative']"))
    assert_has(session, Query.css("body[data-sidebar-desktop-display='flex']"))
  end
end
