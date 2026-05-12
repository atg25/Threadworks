defmodule ChatApp.SP0003SearchInfraAndVectorCodecE2ETest do
  use ChatApp.DataCase, async: false

  @moduletag :e2e

  alias ChatApp.AI.VectorCodec

  # -- E1 ----------------------------------------------------------------------

  # E1
  # Literal acceptance criterion from the phase spec: encode then decode the
  # canonical spec vector (511 zeros followed by 1.0) and verify both the byte
  # size and round-trip precision constraints.
  test "acceptance — VectorCodec encode/decode on spec vector" do
    spec_vector = List.duplicate(0.0, 511) ++ [1.0]

    encoded = VectorCodec.encode(spec_vector)

    assert byte_size(encoded) == 2048,
           "Expected 2048 bytes (512 × 4), got #{byte_size(encoded)}"

    decoded = VectorCodec.decode(encoded)

    Enum.zip(spec_vector, decoded)
    |> Enum.each(fn {original_val, decoded_val} ->
      assert abs(original_val - decoded_val) < 0.0001,
             "Round-trip error: original=#{original_val}, decoded=#{decoded_val}"
    end)
  end

  # -- E2 ----------------------------------------------------------------------

  # E2
  # Verifies that the DB layer (sqlite_vec) enforces dimension constraints
  # independently of VectorCodec. A 1024-byte blob (256 float32s) must not be
  # silently accepted into a vec0(embedding float[512]) column.
  test "inserting a wrong-dimension binary into clothing_vec raises an Ecto error" do
    # 1024 bytes = 256 float32 elements — half the required 512 dimensions
    wrong_dimension_binary = :binary.copy(<<0>>, 1024)

    raised =
      try do
        Ecto.Adapters.SQL.query!(
          ChatApp.Repo,
          "INSERT INTO clothing_vec(rowid, embedding) VALUES (?, ?)",
          [1, {:blob, wrong_dimension_binary}]
        )

        false
      rescue
        Exqlite.Error -> true
        Ecto.QueryError -> true
      end

    assert raised,
           "Expected Exqlite.Error or Ecto.QueryError for wrong-dimension embedding, but no error was raised"
  end
end
