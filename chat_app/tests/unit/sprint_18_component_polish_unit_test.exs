defmodule ChatApp.Sprint18ComponentPolishUnitTest do
  use ExUnit.Case, async: false

  test "utilities.css defines prose color inheritance overrides" do
    css = File.read!("/Users/agard/NJIT/IS322/Final/chat_app/assets/css/utilities.css")

    assert css =~ ".prose"
    assert css =~ "inherit"
    assert css =~ "--foreground"
  end

  test "utilities.css defines semantic icon button styles" do
    css = File.read!("/Users/agard/NJIT/IS322/Final/chat_app/assets/css/utilities.css")

    assert css =~ ".icon-btn"
    assert css =~ "inline-flex"
  end

  test "utilities.css defines three-line skeleton loading styles" do
    css = File.read!("/Users/agard/NJIT/IS322/Final/chat_app/assets/css/utilities.css")

    assert css =~ ".typing-skeleton"
    assert css =~ ".typing-skeleton-line"
    assert css =~ "animate-pulse"
  end

  test "chat_live renders Heroicons for sidebar controls" do
    live_text = File.read!("/Users/agard/NJIT/IS322/Final/chat_app/lib/chat_app_web/live/chat_live.ex")

    assert live_text =~ "heroicon"
    assert live_text =~ "data-sidebar-action-icon"
  end

  test "chat_live no longer renders feedback up/down actions" do
    live_text = File.read!("/Users/agard/NJIT/IS322/Final/chat_app/lib/chat_app_web/live/chat_live.ex")

    refute live_text =~ "phx-click=\"feedback\""
    refute live_text =~ "phx-value-rating=\"up\""
    refute live_text =~ "phx-value-rating=\"down\""
  end

  test "chat_live uses a skeleton indicator marker instead of typing dots" do
    live_text = File.read!("/Users/agard/NJIT/IS322/Final/chat_app/lib/chat_app_web/live/chat_live.ex")

    assert live_text =~ "data-typing-skeleton"
    refute live_text =~ "data-typing-dots"
  end
end
