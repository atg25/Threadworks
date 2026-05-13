defmodule ChatApp.ETL.Embedder do
  @doc """
  Sends a batch of texts to the OpenAI embeddings endpoint and returns a list
  of 512-element float lists, one per input text.

  Request body includes `"dimensions": 512` to force text-embedding-3-small to
  return 512-element vectors compatible with VectorCodec and clothing_vec.
  """
  def embed_batch(texts) when is_list(texts) do
    url =
      Application.get_env(
        :chat_app,
        :openai_embeddings_url,
        "https://api.openai.com/v1/embeddings"
      )

    api_key = Application.get_env(:chat_app, :openai_api_key)

    body = %{
      model: "text-embedding-3-small",
      input: texts,
      dimensions: 512
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

        {:ok, embeddings}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
