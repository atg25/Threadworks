defmodule ChatApp.OpenAI.SSETest do
  use ExUnit.Case, async: true

  alias ChatApp.OpenAI.SSE

  # ── split_lines_and_remainder/1 ───────────────────────────────

  describe "split_lines_and_remainder/1" do
    test "returns complete lines and empty remainder for newline-terminated input" do
      parts = ["data: foo", "data: bar", ""]
      {complete, remainder} = SSE.split_lines_and_remainder(parts)
      assert complete == ["data: foo", "data: bar"]
      assert remainder == ""
    end

    test "returns partial line as remainder when not terminated" do
      parts = ["data: foo", "data: ba"]
      {complete, remainder} = SSE.split_lines_and_remainder(parts)
      assert complete == ["data: foo"]
      assert remainder == "data: ba"
    end

    test "handles single-element list (no complete lines)" do
      {complete, remainder} = SSE.split_lines_and_remainder(["partial"])
      assert complete == []
      assert remainder == "partial"
    end

    test "handles empty list" do
      {complete, remainder} = SSE.split_lines_and_remainder([])
      assert complete == []
      assert remainder == ""
    end

    test "filters empty strings from complete lines" do
      parts = ["data: foo", "", "data: bar", ""]
      {complete, _} = SSE.split_lines_and_remainder(parts)
      refute "" in complete
    end
  end

  # ── parse_sse_chunk/3 ─────────────────────────────────────────

  describe "parse_sse_chunk/3" do
    setup do
      pid = self()
      {:ok, pid: pid}
    end

    test "sends :stream_token for a valid data line", %{pid: pid} do
      json = Jason.encode!(%{choices: [%{delta: %{content: "Hello"}}]})
      chunk = "data: #{json}\n"
      {:cont, ""} = SSE.parse_sse_chunk(chunk, "", pid)
      assert_received {:stream_token, "Hello"}
    end

    test "sends multiple :stream_token for multiple data lines in one chunk", %{pid: pid} do
      j1 = Jason.encode!(%{choices: [%{delta: %{content: "Foo"}}]})
      j2 = Jason.encode!(%{choices: [%{delta: %{content: " bar"}}]})
      chunk = "data: #{j1}\ndata: #{j2}\n"
      {:cont, ""} = SSE.parse_sse_chunk(chunk, "", pid)
      assert_received {:stream_token, "Foo"}
      assert_received {:stream_token, " bar"}
    end

    test "does not crash on [DONE] line", %{pid: pid} do
      {:cont, _} = SSE.parse_sse_chunk("data: [DONE]\n", "", pid)
      refute_received {:stream_token, _}
    end

    test "accumulates partial line from prior chunk and completes on next chunk", %{pid: pid} do
      json = Jason.encode!(%{choices: [%{delta: %{content: "Split"}}]})
      half1 = "data: " <> String.slice(json, 0, div(byte_size(json), 2))
      half2 = String.slice(json, div(byte_size(json), 2), byte_size(json)) <> "\n"

      {:cont, leftover} = SSE.parse_sse_chunk(half1, "", pid)
      refute_received {:stream_token, _}

      {:cont, ""} = SSE.parse_sse_chunk(half2, leftover, pid)
      assert_received {:stream_token, "Split"}
    end

    test "handles empty chunk gracefully", %{pid: pid} do
      {:cont, ""} = SSE.parse_sse_chunk("", "", pid)
      refute_received {:stream_token, _}
    end

    test "handles blank-line event separator", %{pid: pid} do
      json = Jason.encode!(%{choices: [%{delta: %{content: "OK"}}]})
      chunk = "\n\ndata: #{json}\n\n"
      {:cont, _} = SSE.parse_sse_chunk(chunk, "", pid)
      assert_received {:stream_token, "OK"}
    end

    test "does not crash on malformed JSON", %{pid: pid} do
      chunk = "data: {not valid json}\n"
      {:cont, _} = SSE.parse_sse_chunk(chunk, "", pid)
      refute_received {:stream_token, _}
    end

    test "ignores delta without content key", %{pid: pid} do
      json = Jason.encode!(%{choices: [%{delta: %{role: "assistant"}}]})
      chunk = "data: #{json}\n"
      {:cont, _} = SSE.parse_sse_chunk(chunk, "", pid)
      refute_received {:stream_token, _}
    end

    test "ignores null content in delta", %{pid: pid} do
      json = Jason.encode!(%{choices: [%{delta: %{content: nil}}]})
      chunk = "data: #{json}\n"
      {:cont, _} = SSE.parse_sse_chunk(chunk, "", pid)
      refute_received {:stream_token, _}
    end

    test "ignores SSE comment lines", %{pid: pid} do
      chunk = ": keep-alive\n"
      {:cont, _} = SSE.parse_sse_chunk(chunk, "", pid)
      refute_received {:stream_token, _}
    end

    test "correctly accumulates leftover across three partial chunks", %{pid: pid} do
      json = Jason.encode!(%{choices: [%{delta: %{content: "Three"}}]})
      third = div(byte_size(json), 3)
      p1 = "data: " <> binary_part(json, 0, third)
      p2 = binary_part(json, third, third)
      p3 = binary_part(json, third * 2, byte_size(json) - third * 2) <> "\n"

      {:cont, lo1} = SSE.parse_sse_chunk(p1, "", pid)
      {:cont, lo2} = SSE.parse_sse_chunk(p2, lo1, pid)
      {:cont, _} = SSE.parse_sse_chunk(p3, lo2, pid)
      assert_received {:stream_token, "Three"}
    end

    test "handles CRLF line endings", %{pid: pid} do
      json = Jason.encode!(%{choices: [%{delta: %{content: "CRLF"}}]})
      chunk = "data: #{json}\r\n"
      {:cont, _} = SSE.parse_sse_chunk(chunk, "", pid)
      assert_received {:stream_token, "CRLF"}
    end

    test "handles empty chunk with nil accumulator", %{pid: pid} do
      {:cont, ""} = SSE.parse_sse_chunk("", nil, pid)
      refute_received {:stream_token, _}
    end
  end
end
