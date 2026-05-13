defmodule ChatApp.AI.EmbedderTest do
  use ExUnit.Case, async: false

  alias ChatApp.AI.Embedder

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp setup_bypass do
    original = Application.get_env(:chat_app, :openai_embeddings_url)
    bypass = Bypass.open()

    Application.put_env(
      :chat_app,
      :openai_embeddings_url,
      "http://localhost:#{bypass.port}/v1/embeddings"
    )

    on_exit(fn -> Application.put_env(:chat_app, :openai_embeddings_url, original) end)
    bypass
  end

  # Returns a list of `n` distinct 512-element float lists, all already L2-normalized.
  defp mock_normalized_embeddings(n) do
    Enum.map(0..(n - 1), fn i ->
      # Build a unit vector: 1.0 in position i mod 512, 0.0 elsewhere
      pos = rem(i, 512)
      Enum.map(0..511, fn j -> if j == pos, do: 1.0, else: 0.0 end)
    end)
  end

  defp mock_embeddings_response(vecs) do
    data =
      vecs
      |> Enum.with_index()
      |> Enum.map(fn {vec, idx} ->
        %{"object" => "embedding", "index" => idx, "embedding" => vec}
      end)

    Jason.encode!(%{"object" => "list", "model" => "text-embedding-3-small", "data" => data})
  end

  # A known non-unit vector: all elements equal to 2.0, 512 elements.
  # Norm = sqrt(512 * 4.0) = sqrt(2048) ≈ 45.25
  defp non_unit_vector, do: List.duplicate(2.0, 512)

  # A near-zero vector: all elements equal to 1.0e-38, 512 elements.
  defp near_zero_vector, do: List.duplicate(1.0e-38, 512)

  # A pre-normalized single-element vector (fixture_a stand-in for E-01).
  # 1.0 in position 0, rest 0.0 — already unit norm.
  defp fixture_a_vector do
    [1.0 | List.duplicate(0.0, 511)]
  end

  defp stub_single(bypass, vec) do
    body = mock_embeddings_response([vec])

    Bypass.stub(bypass, "POST", "/v1/embeddings", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, body)
    end)
  end

  defp stub_status(bypass, status, body) do
    Bypass.stub(bypass, "POST", "/v1/embeddings", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(status, body)
    end)
  end

  # ---------------------------------------------------------------------------
  # T-01 — embed/1 returns a 512-element list
  # ---------------------------------------------------------------------------

  test "T-01: embed/1 returns a 512-element list" do
    bypass = setup_bypass()
    stub_single(bypass, List.duplicate(1.0, 512))

    assert {:ok, vec} = Embedder.embed("test")
    assert length(vec) == 512
  end

  # ---------------------------------------------------------------------------
  # T-02 — embed/1 returns an L2-normalized vector
  # ---------------------------------------------------------------------------

  test "T-02: embed/1 returns an L2-normalized vector" do
    bypass = setup_bypass()
    # Non-unit vector — implementation must normalize it
    stub_single(bypass, non_unit_vector())

    assert {:ok, vec} = Embedder.embed("test")

    norm = :math.sqrt(Enum.sum(Enum.map(vec, &(&1 * &1))))

    assert abs(norm - 1.0) < 0.001,
           "expected L2 norm close to 1.0, got #{norm}"
  end

  # ---------------------------------------------------------------------------
  # T-03 — embed_batch/1 returns one normalized 512-dim vector per input, all distinct
  # ---------------------------------------------------------------------------

  test "T-03: embed_batch/1 returns one normalized 512-dim vector per input text, all distinct" do
    bypass = setup_bypass()
    vecs = mock_normalized_embeddings(3)
    body = mock_embeddings_response(vecs)

    Bypass.stub(bypass, "POST", "/v1/embeddings", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, body)
    end)

    assert {:ok, result} = Embedder.embed_batch(["alpha", "beta", "gamma"])

    assert length(result) == 3

    Enum.each(result, fn vec ->
      assert length(vec) == 512
      norm = :math.sqrt(Enum.sum(Enum.map(vec, &(&1 * &1))))
      assert abs(norm - 1.0) < 0.001, "expected unit norm, got #{norm}"
    end)

    [v1, v2, v3] = result
    refute v1 == v2, "expected distinct vectors but v1 == v2"
    refute v1 == v3, "expected distinct vectors but v1 == v3"
    refute v2 == v3, "expected distinct vectors but v2 == v3"
  end

  # ---------------------------------------------------------------------------
  # T-04 — embed_batch/1 normalizes every vector independently
  # ---------------------------------------------------------------------------

  test "T-04: embed_batch/1 normalizes every vector independently" do
    bypass = setup_bypass()
    # Non-parallel: first has 1.0 in position 0, second has 4.0 in position 1.
    # After normalization both are unit vectors but in different directions.
    raw_vecs = [
      [1.0 | List.duplicate(0.0, 511)],
      [0.0, 4.0 | List.duplicate(0.0, 510)]
    ]

    body = mock_embeddings_response(raw_vecs)

    Bypass.stub(bypass, "POST", "/v1/embeddings", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, body)
    end)

    assert {:ok, [v1, v2]} = Embedder.embed_batch(["text1", "text2"])

    norm1 = :math.sqrt(Enum.sum(Enum.map(v1, &(&1 * &1))))
    norm2 = :math.sqrt(Enum.sum(Enum.map(v2, &(&1 * &1))))

    assert abs(norm1 - 1.0) < 0.001, "v1 norm #{norm1} is not unit"
    assert abs(norm2 - 1.0) < 0.001, "v2 norm #{norm2} is not unit"
    refute v1 == v2, "expected distinct normalized vectors"
  end

  # ---------------------------------------------------------------------------
  # T-05 — embed/1 returns {:error, reason} on HTTP 5xx
  # ---------------------------------------------------------------------------

  test "T-05: embed/1 returns {:error, reason} on HTTP 5xx" do
    bypass = setup_bypass()
    stub_status(bypass, 500, "internal error")

    result = Embedder.embed("test")

    assert match?({:error, _}, result),
           "expected {:error, _}, got #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # T-06 — embed/1 returns {:error, reason} on network failure
  # ---------------------------------------------------------------------------

  test "T-06: embed/1 returns {:error, reason} on network failure" do
    # Point at a port with no server so the connection is refused
    Application.put_env(:chat_app, :openai_embeddings_url, "http://localhost:1/v1/embeddings")

    result = Embedder.embed("test")

    assert match?({:error, _}, result),
           "expected {:error, _} on network failure, got #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # T-07 — embed/1 returns {:error, _} when API returns wrong number of dimensions
  # ---------------------------------------------------------------------------

  test "T-07: embed/1 returns {:error, _} when API returns wrong number of dimensions" do
    bypass = setup_bypass()
    # Return 256-element vector instead of 512
    stub_single(bypass, List.duplicate(1.0, 256))

    result = Embedder.embed("test")

    assert match?({:error, _}, result) or
             (is_tuple(result) and elem(result, 0) == :error),
           "expected {:error, _} for wrong dimensions, got #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # I-01 — embed/1 with empty string propagates API rejection cleanly
  # ---------------------------------------------------------------------------

  test "I-01: embed/1 with empty string propagates API rejection cleanly" do
    bypass = setup_bypass()
    error_body = Jason.encode!(%{"error" => %{"message" => "empty input not allowed"}})
    stub_status(bypass, 400, error_body)

    result = Embedder.embed("")

    assert match?({:error, _}, result),
           "expected {:error, _} for empty string, got #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # I-02 — embed/1 normalizing a near-zero vector does not divide by zero
  # ---------------------------------------------------------------------------

  test "I-02: embed/1 normalizing a near-zero vector does not divide by zero" do
    bypass = setup_bypass()
    stub_single(bypass, near_zero_vector())

    assert {:ok, vec} = Embedder.embed("any")

    assert length(vec) == 512

    Enum.each(vec, fn val ->
      assert is_float(val), "expected float, got #{inspect(val)}"
      refute val == :infinity, "found :infinity in vector"
      refute val == :nan, "found :nan in vector"
      # In Elixir, NaN/Inf from IEEE 754 would show as floats; check finiteness
      assert val == val, "found NaN in vector (val != val)"
      assert abs(val) < 1.0e38, "found near-infinity value #{val}"
    end)

    norm = :math.sqrt(Enum.sum(Enum.map(vec, &(&1 * &1))))

    assert abs(norm - 1.0) < 0.001,
           "expected unit norm after near-zero normalization, got #{norm}"
  end

  # ---------------------------------------------------------------------------
  # E-01 — Positive: embed/1 round-trips through full pipeline with mocked API
  # ---------------------------------------------------------------------------

  test "E-01: embed/1 round-trips cleanly through full pipeline with mocked API" do
    bypass = setup_bypass()
    # fixture_a is already unit-normalized; normalization must be idempotent
    fa = fixture_a_vector()
    stub_single(bypass, fa)

    assert {:ok, vec} = Embedder.embed("vintage levi denim jacket")

    assert length(vec) == 512

    norm = :math.sqrt(Enum.sum(Enum.map(vec, &(&1 * &1))))
    assert abs(norm - 1.0) < 0.001, "expected unit norm, got #{norm}"

    # Idempotency: re-normalizing an already-normalized vector yields the same vector
    Enum.zip(fa, vec)
    |> Enum.each(fn {expected, actual} ->
      assert abs(expected - actual) < 0.0001,
             "expected idempotent normalization, diff at element: expected #{expected}, got #{actual}"
    end)
  end

  # ---------------------------------------------------------------------------
  # E-02 — Negative: HTTP 401 Unauthorized returns {:error, _}, not a crash
  # ---------------------------------------------------------------------------

  test "E-02: HTTP 401 Unauthorized returns {:error, _}, not a crash" do
    bypass = setup_bypass()
    error_body = Jason.encode!(%{"error" => %{"message" => "invalid api key"}})
    stub_status(bypass, 401, error_body)

    result = Embedder.embed("any query")

    assert match?({:error, _}, result),
           "expected {:error, _} for 401, got #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # E-03 — Negative: API response with mismatched dimensions is rejected before normalization
  # ---------------------------------------------------------------------------

  test "E-03: API response with mismatched dimensions is rejected before normalization" do
    bypass = setup_bypass()
    # Return 100-element list instead of 512
    stub_single(bypass, List.duplicate(1.0, 100))

    result = Embedder.embed("jacket")

    assert match?({:error, _}, result),
           "expected {:error, _} for mismatched dimensions (100-element vector), got #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # Extra coverage: out-of-order API response is correctly reordered by index
  # ---------------------------------------------------------------------------

  test "embed_batch/1 reorders results correctly when API returns embeddings out of order" do
    bypass = setup_bypass()

    # Build two distinct normalized vectors
    vec0 = [1.0 | List.duplicate(0.0, 511)]
    vec1 = [0.0, 1.0 | List.duplicate(0.0, 510)]

    # Return them with indices swapped: index 1 first, index 0 second
    body =
      Jason.encode!(%{
        "object" => "list",
        "model" => "text-embedding-3-small",
        "data" => [
          %{"object" => "embedding", "index" => 1, "embedding" => vec1},
          %{"object" => "embedding", "index" => 0, "embedding" => vec0}
        ]
      })

    Bypass.stub(bypass, "POST", "/v1/embeddings", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, body)
    end)

    assert {:ok, [r0, r1]} = Embedder.embed_batch(["first", "second"])

    assert Enum.at(r0, 0) == 1.0,
           "expected vec0 first (index 0), got #{inspect(Enum.take(r0, 2))}"

    assert Enum.at(r1, 1) == 1.0,
           "expected vec1 second (index 1), got #{inspect(Enum.take(r1, 2))}"
  end

  # ---------------------------------------------------------------------------
  # Extra coverage: malformed API response (nil embedding) returns {:error, _}
  # ---------------------------------------------------------------------------

  test "embed/1 returns {:error, _} when API returns null for embedding field" do
    bypass = setup_bypass()

    # A response where "embedding" key is absent — Req decodes it as nil
    body =
      Jason.encode!(%{
        "object" => "list",
        "model" => "text-embedding-3-small",
        "data" => [%{"object" => "embedding", "index" => 0}]
      })

    Bypass.stub(bypass, "POST", "/v1/embeddings", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, body)
    end)

    result = Embedder.embed("test")

    assert match?({:error, _}, result),
           "expected {:error, _} for null embedding, got #{inspect(result)}"
  end
end
