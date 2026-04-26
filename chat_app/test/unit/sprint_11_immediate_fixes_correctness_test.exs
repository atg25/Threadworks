defmodule ChatApp.Sprint11ImmediateFixesCorrectnessUnitTest do
  use ExUnit.Case, async: false

  alias ChatApp.Markdown
  alias ChatApp.OpenAI

  test "to_html/1 escapes embedded <script> tags" do
    result = Markdown.to_html("<script>alert('xss')</script>")

    assert result =~ "&lt;script&gt;"
    refute result =~ "<script>"
  end

  test "to_html/1 escapes & in plain text without doubling" do
    result = Markdown.to_html("AT&T")

    assert result =~ "AT&amp;T"
    refute result =~ "AT&amp;amp;T"
  end

  test "to_html/1 still emits <pre><code> for fenced blocks" do
    result = Markdown.to_html("```\nlet x = 1\n```")

    assert result =~ "<pre><code"
    assert result =~ "let x = 1"
  end

  test "to_html/1 escapes raw HTML inside fenced blocks" do
    result = Markdown.to_html("```\n<b>x</b>\n```")

    assert result =~ "&lt;b&gt;"
    refute result =~ "<b>"
  end

  test "openai_model/0 reads :openai_model with default fallback" do
    original = Application.get_env(:chat_app, :openai_model)
    on_exit(fn -> restore_env(:openai_model, original) end)

    Application.delete_env(:chat_app, :openai_model)
    assert request_model_from_stream() == "gpt-4o"

    Application.put_env(:chat_app, :openai_model, "gpt-test")
    assert request_model_from_stream() == "gpt-test"
  end

  defp request_model_from_stream do
    parent = self()

    Req.Test.stub(ChatApp.OpenAI, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:openai_request_model, Jason.decode!(body)["model"]})
      Req.Test.text(conn, "data: [DONE]\n\n")
    end)

    OpenAI.stream([%{role: :user, content: "Q"}], self())

    assert_received {:openai_request_model, model}
    model
  end

  defp restore_env(key, nil), do: Application.delete_env(:chat_app, key)
  defp restore_env(key, value), do: Application.put_env(:chat_app, key, value)
end
