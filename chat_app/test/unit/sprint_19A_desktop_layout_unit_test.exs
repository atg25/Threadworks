defmodule ChatApp.Sprint19ADesktopLayoutUnitTest do
  use ExUnit.Case, async: false

  @sidebar_path Path.expand("../../lib/chat_app_web/live/sidebar_component.ex", __DIR__)
  @chat_live_path Path.expand("../../lib/chat_app_web/live/chat_live.ex", __DIR__)

  test "sidebar collapses and expands via header toggle on desktop" do
    sidebar_component = File.read!(@sidebar_path)

    assert sidebar_component =~ ~s(id="chat-sidebar")

    assert sidebar_component =~
             ~s(style={if @collapsed, do: "width: 0px;", else: "width: 16rem;"})

    assert sidebar_component =~ "transition-[width,opacity,border-color]"
    assert sidebar_component =~ "data-sidebar-collapsed={to_string(@collapsed)}"
  end

  test "API cost tracker is completely removed from the DOM" do
    live_text = File.read!(@chat_live_path)

    refute live_text =~ "data-usage-cost"
  end

  test "header icon buttons are keyboard accessible" do
    live_text = File.read!(@chat_live_path)

    assert live_text =~
             ~s(aria-label={if @sidebar_open, do: "Collapse sidebar", else: "Expand sidebar"})

    assert live_text =~ ~s(aria-label="Start a new conversation")
    assert live_text =~ ~s(aria-label="Conversation settings")

    assert live_text =~
             ~s(class="icon-btn focus-ring inline-flex size-10 shrink-0 text-foreground/70 hover:text-foreground")
  end
end
