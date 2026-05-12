defmodule ChatApp.AI.VectorCodecTest do
  use ExUnit.Case, async: true

  alias ChatApp.AI.VectorCodec

  # -- U1 -- encode/1 returns binary of exactly 2048 bytes for a 512-element list
  test "U1: encode/1 returns binary of exactly 2048 bytes for a 512-element list" do
    input = List.duplicate(0.0, 511) ++ [1.0]
    result = VectorCodec.encode(input)
    assert byte_size(result) == 2048
  end

  # -- U2 -- encode/1 last element encodes as little-endian float32 1.0
  test "U2: encode/1 last element encodes as little-endian float32 1.0" do
    input = List.duplicate(0.0, 511) ++ [1.0]
    result = VectorCodec.encode(input)
    last_4_bytes = binary_part(result, byte_size(result), -4)
    # Little-endian IEEE 754 representation of 1.0; big-endian would be <<63, 128, 0, 0>>
    assert last_4_bytes == <<0, 0, 128, 63>>
  end

  # -- U3 -- decode/1 round-trips encode output within float32 precision
  test "U3: decode/1 round-trips encode output within float32 precision" do
    original = List.duplicate(0.0, 511) ++ [1.0]
    encoded = VectorCodec.encode(original)
    decoded = VectorCodec.decode(encoded)

    Enum.zip(original, decoded)
    |> Enum.each(fn {original_val, decoded_val} ->
      assert abs(original_val - decoded_val) < 0.0001
    end)
  end

  # -- U4 -- decode/1 returns a list of exactly 512 floats
  test "U4: decode/1 returns a list of exactly 512 floats" do
    binary = VectorCodec.encode(List.duplicate(0.0, 512))
    result = VectorCodec.decode(binary)
    assert length(result) == 512
    assert Enum.all?(result, &is_float/1)
  end

  # -- U5 -- encode/1 raises ArgumentError on list shorter than 512 elements
  test "U5: encode/1 raises ArgumentError on list shorter than 512 elements" do
    input = List.duplicate(0.0, 511)
    assert_raise ArgumentError, fn -> VectorCodec.encode(input) end
  end

  # -- U6 -- encode/1 raises ArgumentError on list longer than 512 elements
  test "U6: encode/1 raises ArgumentError on list longer than 512 elements" do
    input = List.duplicate(0.0, 513)
    assert_raise ArgumentError, fn -> VectorCodec.encode(input) end
  end

  # -- U7 -- encode/1 handles all-zeros correctly
  test "U7: encode/1 handles all-zeros correctly" do
    input = List.duplicate(0.0, 512)
    result = VectorCodec.encode(input)
    assert byte_size(result) == 2048
    # Verify all bytes are 0
    assert result == String.duplicate(<<0>>, 2048)
  end

  # -- U8 -- decode/1 raises ArgumentError on binary with wrong byte length
  test "U8: decode/1 raises ArgumentError on binary with wrong byte length" do
    invalid_binary = <<0::24>>
    assert_raise ArgumentError, fn -> VectorCodec.decode(invalid_binary) end
  end

  # -- U9 -- encode/1 raises on non-float, non-numeric elements
  test "U9: encode/1 raises on non-float, non-numeric elements" do
    input = ["not_a_float"] ++ List.duplicate(0.0, 511)

    # Raises ArgumentError or FunctionClauseError depending on implementation
    try do
      VectorCodec.encode(input)
      flunk("Expected ArgumentError or FunctionClauseError")
    rescue
      ArgumentError -> :ok
      FunctionClauseError -> :ok
    end
  end
end
