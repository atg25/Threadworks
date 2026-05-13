defmodule ChatAppWeb.Sprint17FoundationUpdatesIntegrationTest do
  use ChatAppWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component

  test "flash messages render without tailwind compilation errors" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <ChatAppWeb.CoreComponents.flash kind={:error} title="Error!">
        Boom
      </ChatAppWeb.CoreComponents.flash>
      """)

    refute html =~ "/35"
    assert html =~ "alert-error"
    assert html =~ "toast-top"
  end
end
