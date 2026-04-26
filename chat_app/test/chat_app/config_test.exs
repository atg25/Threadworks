defmodule ChatApp.ConfigTest do
  use ExUnit.Case, async: true

  # Positive: API key is configured in test env
  test "openai_api_key is present in application env" do
    key = Application.get_env(:chat_app, :openai_api_key)
    assert is_binary(key)
    assert String.length(key) > 0
  end

  # Negative: key must not be nil
  test "openai_api_key is not nil" do
    key = Application.get_env(:chat_app, :openai_api_key)
    refute is_nil(key)
  end
end
