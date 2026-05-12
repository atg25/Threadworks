defmodule ChatApp.AI.VectorCodec do
  @moduledoc """
  Encodes and decodes 512-element float32 vectors to/from a 2048-byte binary.

  Wire format: 512 × IEEE 754 single-precision floats, little-endian.
  sqlite_vec's vec0 virtual table reads BLOB columns as little-endian float32;
  using any other byte order produces silently wrong KNN distances.
  """

  @dims 512
  @byte_size @dims * 4

  @doc """
  Encodes a list of exactly 512 floats into a 2048-byte little-endian binary.

  Raises `ArgumentError` if the list does not have exactly 512 elements.
  Raises `FunctionClauseError` if any element is not a float or integer.
  """
  def encode(floats) when is_list(floats) do
    unless length(floats) == @dims do
      raise ArgumentError,
            "VectorCodec.encode/1 requires exactly #{@dims} elements, got #{length(floats)}"
    end

    for f <- floats, into: <<>>, do: encode_element(f)
  end

  # Guard ensures non-numeric elements raise FunctionClauseError (not ArgumentError from
  # the bit-syntax constructor) — consistent with the documented contract above.
  defp encode_element(f) when is_number(f), do: <<f::little-float-32>>

  @doc """
  Decodes a 2048-byte little-endian binary into a list of 512 floats.

  Raises `ArgumentError` if the binary is not exactly 2048 bytes.
  """
  def decode(binary) when is_binary(binary) do
    unless byte_size(binary) == @byte_size do
      raise ArgumentError,
            "VectorCodec.decode/1 requires exactly #{@byte_size} bytes, got #{byte_size(binary)}"
    end

    decode_chunks(binary, [])
  end

  defp decode_chunks(<<>>, acc), do: Enum.reverse(acc)

  defp decode_chunks(<<f::little-float-32, rest::binary>>, acc) do
    decode_chunks(rest, [f | acc])
  end
end
