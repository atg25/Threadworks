# Generates test/fixtures/embeddings.exs with three pre-computed, L2-normalized
# 512-element embedding vectors from the real OpenAI API.
#
# Run once manually (requires a live API key):
#
#   OPENAI_API_KEY=sk-... mix run scripts/gen_fixtures.exs
#
# Commit the output file. Do not re-run unless intentionally regenerating.

inputs = [
  "vintage levi denim jacket secondhand",
  "pink silk evening gown formal wear",
  "denim jacket indigo blue worn preloved"
]

keys = [:fixture_a, :fixture_b, :fixture_c]

IO.puts("Requesting embeddings from OpenAI...")

{:ok, vecs} = ChatApp.AI.Embedder.embed_batch(inputs)

fixtures =
  keys
  |> Enum.zip(vecs)
  |> Map.new()

# Validate before writing
Enum.each(keys, fn k ->
  vec = fixtures[k]
  len = length(vec)
  norm = :math.sqrt(Enum.sum(Enum.map(vec, &(&1 * &1))))
  IO.puts("#{k}: #{len} elements, norm=#{Float.round(norm, 6)}")
  if len != 512, do: raise("#{k} has #{len} elements, expected 512")
  if abs(norm - 1.0) > 0.001, do: raise("#{k} norm #{norm} is not unit")
end)

[a, b, c] = Enum.map(keys, &fixtures[&1])
if a == b or a == c or b == c, do: raise("fixture vectors are not mutually distinct")

out_path = Path.join([File.cwd!(), "test", "fixtures", "embeddings.exs"])
File.mkdir_p!(Path.dirname(out_path))

content =
  "%{\n" <>
    Enum.map_join(keys, ",\n", fn k ->
      vec_str = inspect(fixtures[k], limit: :infinity, printable_limit: :infinity)
      "  #{k}: #{vec_str}"
    end) <>
    "\n}\n"

File.write!(out_path, content)
IO.puts("Wrote #{out_path}")
