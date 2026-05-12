defmodule ChatApp.AI.Embedder do
  @expected_dims 512

  @doc """
  Embeds a single text string. Returns `{:ok, vec}` where `vec` is a
  512-element L2-normalized float list, or `{:error, reason}`.
  """
  def embed(text) when is_binary(text) do
    case embed_batch([text]) do
      {:ok, [vec]} -> {:ok, vec}
      {:ok, _} -> {:error, :unexpected_batch_result}
      {:error, _} = err -> err
    end
  end

  @doc """
  Embeds a list of texts in a single API call. Returns `{:ok, [vec]}` where
  each `vec` is a 512-element L2-normalized float list, or `{:error, reason}`.
  """
  def embed_batch(texts) when is_list(texts) do
    url = Application.get_env(:chat_app, :openai_embeddings_url, "https://api.openai.com/v1/embeddings")
    api_key = Application.get_env(:chat_app, :openai_api_key)

    body = %{
      model: "text-embedding-3-small",
      input: texts,
      dimensions: @expected_dims
    }

    case Req.post(url,
           json: body,
           headers: [{"authorization", "Bearer #{api_key}"}]
         ) do
      {:ok, %{status: 200, body: %{"data" => data}}} ->
        embeddings =
          data
          |> Enum.sort_by(& &1["index"])
          |> Enum.map(& &1["embedding"])

        with :ok <- validate_dims(embeddings) do
          {:ok, Enum.map(embeddings, &l2_normalize/1)}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Returns :ok if every vector has exactly @expected_dims elements, else {:error, ...}.
  # Uses reduce_while to avoid the Enum.find nil-ambiguity (nil means both "not found"
  # and "found a nil element").
  defp validate_dims(embeddings) do
    Enum.reduce_while(embeddings, :ok, fn vec, _acc ->
      cond do
        not is_list(vec) ->
          {:halt, {:error, :invalid_embedding_type}}

        length(vec) != @expected_dims ->
          {:halt, {:error, {:dimension_mismatch, length(vec), @expected_dims}}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  # L2-normalizes a float list. Guards against near-zero norm to avoid Inf/NaN.
  defp l2_normalize(vec) do
    norm = :math.sqrt(Enum.sum(Enum.map(vec, &(&1 * &1))))

    if norm < 1.0e-10 do
      # Near-zero vector: return a unit vector in the first dimension
      [1.0 | List.duplicate(0.0, length(vec) - 1)]
    else
      Enum.map(vec, &(&1 / norm))
    end
  end
end
