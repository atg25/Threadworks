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
    tw_pos = :binary.match(content, "@import \"tailwindcss\"") |> elem(0)
    fn_pos = :binary.match(content, "./foundation.css") |> elem(0)
    assert tw_pos < fn_pos, "tailwindcss must be imported before foundation.css"
  end

  test "app.css imports foundation before shell" do
    content = File.read!(@app_css)
    fn_pos = :binary.match(content, "./foundation.css") |> elem(0)
    sh_pos = :binary.match(content, "./shell.css") |> elem(0)
    assert fn_pos < sh_pos, "foundation.css must be imported before shell.css"
  end

  test "app.css imports shell before utilities" do
    content = File.read!(@app_css)
    sh_pos = :binary.match(content, "./shell.css") |> elem(0)
    ut_pos = :binary.match(content, "./utilities.css") |> elem(0)
    assert sh_pos < ut_pos, "shell.css must be imported before utilities.css"
  end

  test "app.css imports utilities before chat" do
    content = File.read!(@app_css)
    ut_pos = :binary.match(content, "./utilities.css") |> elem(0)
    ch_pos = :binary.match(content, "./chat.css") |> elem(0)
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

    case {:binary.match(content, "./chat.css"), :binary.match(content, "./utilities.css")} do
      {{ch_pos, _}, {ut_pos, _}} ->
        assert ut_pos < ch_pos,
               "chat.css must not appear before utilities.css - it depends on .focus-ring from utilities"

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
           "chat.css must define the composer plane class - required for gradient background"
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
           "app.css must use @plugin syntax (Tailwind v4) - not tailwind.config.js"
  end

  test "app.css declares @plugin for tailwindcss-animate" do
    content = File.read!(@app_css)

    assert content =~ ~r/@plugin\s+"tailwindcss-animate"/,
           "app.css must use @plugin syntax (Tailwind v4) - not tailwind.config.js"
  end

  # --- Root layout: Google Fonts link tag (spec-1 §2, §15 checklist item 2) ---

  test "root.html.heex contains Google Fonts preconnect links" do
    heex =
      File.read!(
        Path.join([File.cwd!(), "lib", "chat_app_web", "components", "layouts", "root.html.heex"])
      )

    assert heex =~ "fonts.googleapis.com",
           "root.html.heex must include Google Fonts preconnect link (spec-1 §2, §15 item 2)"

    assert heex =~ "fonts.gstatic.com"
    assert heex =~ "IBM+Plex+Sans"
  end
end
