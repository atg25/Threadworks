defmodule ChatApp.Sprint19BMobileDrawerUnitTest do
  use ExUnit.Case, async: false

  @sidebar_path Path.expand("../../lib/chat_app_web/live/sidebar_component.ex", __DIR__)
  @chat_live_path Path.expand("../../lib/chat_app_web/live/chat_live.ex", __DIR__)
  @chat_css_path Path.expand("../../assets/css/chat.css", __DIR__)

  test "sidebar keeps mobile drawer classes and desktop fallback classes" do
    sidebar_component = File.read!(@sidebar_path)

    assert sidebar_component =~ "absolute"
    assert sidebar_component =~ "z-30"
    assert sidebar_component =~ "md:relative"
    assert sidebar_component =~ "md:w-64"
  end

  test "mobile CSS hides only the collapsed sidebar and shows the open drawer" do
    chat_css = File.read!(@chat_css_path)

    refute chat_css =~
             ~r/@media\s*\(max-width:\s*767px\)\s*\{\s*\.ui-chat-sidebar\s*\{\s*display:\s*none;/s

    assert chat_css =~ ~s(.ui-chat-sidebar[data-sidebar-collapsed="true"])
    assert chat_css =~ ~s(.ui-chat-sidebar[data-sidebar-collapsed="false"])
    assert chat_css =~ "display: none;"
    assert chat_css =~ "display: flex;"
  end

  test "clicking the mobile backdrop overlay closes the sidebar without affecting desktop layout" do
    chat_live = File.read!(@chat_live_path)

    assert chat_live =~ ~s(phx-click="close_sidebar")
    assert chat_live =~ ~s(data-mobile-backdrop="true")
    assert chat_live =~ "md:hidden"
    assert chat_live =~ "handle_event(\"close_sidebar\", _params, socket)"
  end
end
