defmodule ChatApp.OpenAI.DemoStub do
  @moduledoc false

  def stream(messages, pid, _opts \\ %{}) do
    user_message = last_user_message(messages)
    downcased = String.downcase(user_message)

    if String.contains?(downcased, "how do you work") do
      Process.sleep(4000)
      how_it_works()
      |> chunk_words()
      |> Enum.each(fn token ->
        send(pid, {:stream_token, token})
        Process.sleep(55)
      end)
    else
      response =
        cond do
          String.contains?(downcased, "vintage") and String.contains?(downcased, "jeans") ->
            recommendation(
              user_message,
              "Vintage jeans are a wardrobe essential—they work with almost everything and have character that new denim can't match. Here's a piece that fits the vintage look you're after. The worn-in fabric and classic cut make it perfect for casual styling, layering, or as the foundation of a more put-together outfit."
            )

          String.contains?(downcased, "minimal") or String.contains?(downcased, "dinner") ->
            recommendation(
              user_message,
              "For a minimal dinner look, I would keep the silhouette clean and let texture do the work. Start with the strongest elevated piece, then add one polished layer or shoe so the outfit reads intentional without feeling overbuilt."
            )

          true ->
            recommendation(
              user_message,
              "For vintage streetwear under budget, I would anchor the outfit with denim, then add one relaxed piece that makes it feel current. These picks are pulled from the local catalog because they match the vintage, denim, and streetwear signals in your request."
            )
        end

      Process.sleep(2500)

      response
      |> chunk_words()
      |> Enum.each(fn token ->
        send(pid, {:stream_token, token})
        Process.sleep(45)
      end)
    end

    send(pid, :stream_done)
  end

  defp how_it_works do
    """
    Threadworks AI is a prototype shopping and styling assistant for second-hand fashion.

    Here is the core loop:

    1. You ask in natural language.
    2. The app searches a local clothing catalog before the model answers.
    3. Retrieval uses hybrid search: vector similarity for meaning plus FTS keyword search for exact terms like brands, sizes, and prices.
    4. The assistant streams back styling advice and attaches product cards for recommended items.
    5. You can save or unsave cards, revisit saved items, and manage preferences for sizes, brands, budget, and style keywords.

    Under the hood, Phoenix LiveView handles the real-time chat flow, SQLite stores conversations, catalog items, saved items, and preferences, and the refresh workflow is ready to pull new listings in the background.
    """
  end

  defp recommendation(user_message, prose) do
    cards =
      user_message
      |> ChatApp.Demo.scripted_card_ids(1)
      |> Enum.map(fn id ->
        %{
          "item_id" => id,
          "reason" => reason_for(id)
        }
      end)

    json = Jason.encode!(%{"cards" => cards})
    prose <> "\n\n<!-- #{json} -->"
  end

  defp reason_for(item_id) do
    case ChatApp.Clothing.get_item(item_id) do
      %{title: title, price: price} ->
        "#{title} is a strong match and stays in the demo budget at #{ChatAppWeb.ProductCard.format_price(price)}."

      _ ->
        "Strong match from the retrieved catalog."
    end
  end

  defp last_user_message(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value("", fn
      %{role: :user, content: content} when is_binary(content) -> content
      %{"role" => "user", "content" => content} when is_binary(content) -> content
      _ -> nil
    end)
  end

  defp chunk_words(text) do
    Regex.scan(~r/\S+\s*/s, text) |> List.flatten()
  end
end
