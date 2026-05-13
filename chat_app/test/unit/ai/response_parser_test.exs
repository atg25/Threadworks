defmodule ChatApp.AI.ResponseParserTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias ChatApp.AI.ResponseParser

  # ---------------------------------------------------------------------------
  # E2E — Full parse behavior (tagged :e2e but no external I/O)
  # ---------------------------------------------------------------------------

  @tag :e2e
  test "E1: single-chunk complete parse; item_id is integer type" do
    {cards, buffer} =
      ResponseParser.parse(~s({"cards": [{"item_id": 5, "reason": "Great fit"}]}), "")

    assert length(cards) == 1
    card = hd(cards)
    assert card.item_id == 5
    assert is_integer(card.item_id)
    assert card.reason == "Great fit"
    assert buffer == ""
  end

  @tag :e2e
  test "E2: trailing text after JSON block preserved in remaining_buffer" do
    chunk = ~s(Here are picks: {"cards": [{"item_id": 3, "reason": "Bold"}]} enjoy!)
    {cards, remaining} = ResponseParser.parse(chunk, "")
    assert length(cards) == 1
    assert hd(cards).item_id == 3
    assert remaining == " enjoy!"
  end

  # ---------------------------------------------------------------------------
  # describe "parse/2" — Unit tests
  # ---------------------------------------------------------------------------

  describe "parse/2" do
    test "U1: empty chunk on empty buffer returns empty result without crash" do
      assert {[], ""} = ResponseParser.parse("", "")
    end

    test "U2: incomplete JSON accumulates in buffer without premature decode" do
      chunk = ~s({"cards": [{"item_id": 2,)
      {cards, buffer} = ResponseParser.parse(chunk, "")
      assert cards == []
      assert buffer == chunk
    end

    test "U3: split mid-closing-brace assembles correctly across two chunks" do
      chunk_1 = ~s({"cards": [{"item_id": 7, "reason": "Great)
      chunk_2 = ~s( fit"}]})

      {cards_1, buf_1} = ResponseParser.parse(chunk_1, "")
      assert cards_1 == []
      assert buf_1 == chunk_1

      {cards_2, buf_2} = ResponseParser.parse(chunk_2, buf_1)
      assert length(cards_2) == 1
      assert hd(cards_2).item_id == 7
      assert hd(cards_2).reason == "Great fit"
      assert buf_2 == ""
    end

    test "U4: plain text with no JSON returns text in buffer, no crash" do
      {cards, buffer} = ResponseParser.parse("Some text with no JSON.", "")
      assert cards == []
      assert buffer == "Some text with no JSON."
    end

    test "U5: malformed JSON after complete-looking brace discards buffer without crash" do
      {cards, buffer} = ResponseParser.parse(~s({"cards": [BROKEN}), "")
      assert cards == []
      assert buffer == ""
    end

    test "U6: empty cards array in valid JSON clears buffer, returns no cards" do
      {cards, buffer} = ResponseParser.parse(~s({"cards": []}), "")
      assert cards == []
      assert buffer == ""
    end

    test "U7: non-JSON text prefix in existing buffer does not prevent extraction" do
      buffer_with_prefix = "I suggest these items for you: "
      chunk = ~s({"cards": [{"item_id": 2, "reason": "Casual"}]})
      {cards, remaining} = ResponseParser.parse(chunk, buffer_with_prefix)
      assert length(cards) == 1
      assert hd(cards).item_id == 2
      assert remaining == ""
    end

    test "U8: multiple cards in a single chunk are all extracted" do
      chunk =
        ~s({"cards": [{"item_id": 1, "reason": "A"}, {"item_id": 2, "reason": "B"}]})

      {cards, buffer} = ResponseParser.parse(chunk, "")
      assert length(cards) == 2
      ids = Enum.map(cards, & &1.item_id)
      assert 1 in ids
      assert 2 in ids
      assert buffer == ""
    end

    test "M1: string item_id from LLM is coerced to integer" do
      chunk = ~s({"cards": [{"item_id": "5", "reason": "Great fit"}]})
      {cards, _buffer} = ResponseParser.parse(chunk, "")
      assert length(cards) == 1
      card = hd(cards)
      assert card.item_id == 5
      assert is_integer(card.item_id)
    end

    test "M2: non-integer item_id (float or non-numeric string) drops the card" do
      chunk_float = ~s({"cards": [{"item_id": 5.5, "reason": "Float ID"}]})
      {cards_f, _} = ResponseParser.parse(chunk_float, "")
      assert cards_f == []

      chunk_str = ~s({"cards": [{"item_id": "abc", "reason": "String ID"}]})
      {cards_s, _} = ResponseParser.parse(chunk_str, "")
      assert cards_s == []
    end

    test "M3: poisoned-buffer recovery: non-JSON prefix accumulated, then valid JSON arrives" do
      {[], buf_1} = ResponseParser.parse("I recommend the following: ", "")
      assert buf_1 == "I recommend the following: "

      {cards, buf_2} =
        ResponseParser.parse(
          ~s({"cards": [{"item_id": 9, "reason": "Warm"}]}),
          buf_1
        )

      assert length(cards) == 1
      assert hd(cards).item_id == 9
      assert buf_2 == ""
    end
  end
end
