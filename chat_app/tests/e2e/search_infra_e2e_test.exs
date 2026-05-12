defmodule ChatApp.E2E.SearchInfraE2ETest do
  use ChatApp.DataCase, async: false

  alias ChatApp.AI.VectorCodec

  # -- E1 -- acceptance — VectorCodec encode/decode on spec vector
  test "E1: VectorCodec encode/decode on spec vector" do
    # Create the spec vector: 511 zeros followed by 1.0
    spec_vector = List.duplicate(0.0, 511) ++ [1.0]

    # Encode it
    encoded = VectorCodec.encode(spec_vector)

    # Verify binary is exactly 2048 bytes
    assert byte_size(encoded) == 2048

    # Decode it
    decoded = VectorCodec.decode(encoded)

    # Verify round-trip within float32 precision
    Enum.zip(spec_vector, decoded)
    |> Enum.each(fn {original_val, decoded_val} ->
      assert abs(original_val - decoded_val) < 0.0001,
             "Decoded value #{decoded_val} differs from original #{original_val} by more than 0.0001"
    end)
  end

  # -- E2 -- inserting a wrong-dimension binary into clothing_vec raises an Ecto error
  test "E2: inserting a wrong-dimension binary into clothing_vec raises an Ecto error" do
    # Create a 256-element vector (half the required 512) = 1024 bytes
    wrong_dimension_binary = <<0::binary-size(1024)>>

    # Attempt to insert via Ecto.Adapters.SQL.query
    assert_raise(
      fn ->
        Ecto.Adapters.SQL.query(
          ChatApp.Repo,
          "INSERT INTO clothing_vec(rowid, embedding) VALUES (?, ?)",
          [1, wrong_dimension_binary]
        )
      end,
      [Ecto.QueryError, Exqlite.Error],
      "Should raise Ecto.QueryError or Exqlite.Error for dimension mismatch"
    )
  end
end
