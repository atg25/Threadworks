defmodule ChatApp.Ecto.DecimalString do
  @moduledoc false
  # Custom Ecto type that stores Decimal values as TEXT in SQLite,
  # preserving trailing zeros (e.g. "12.00" reads back as Decimal.new("12.00")).
  use Ecto.Type

  def type, do: :string

  def cast(%Decimal{} = d), do: {:ok, d}

  def cast(value) when is_binary(value) do
    case Decimal.parse(value) do
      {d, ""} -> {:ok, d}
      _ -> :error
    end
  end

  def cast(value) when is_integer(value), do: {:ok, Decimal.new(value)}

  def cast(value) when is_float(value) do
    {:ok, Decimal.from_float(value)}
  end

  def cast(_), do: :error

  def load(value) when is_binary(value) do
    case Decimal.parse(value) do
      {d, ""} -> {:ok, d}
      _ -> :error
    end
  end

  def load(value) when is_integer(value), do: {:ok, Decimal.new(value)}

  def load(value) when is_float(value) do
    {:ok, Decimal.from_float(value)}
  end

  def load(nil), do: {:ok, nil}
  def load(_), do: :error

  def dump(%Decimal{} = d), do: {:ok, Decimal.to_string(d)}
  def dump(nil), do: {:ok, nil}
  def dump(_), do: :error

  def equal?(%Decimal{} = a, %Decimal{} = b), do: Decimal.equal?(a, b)
  def equal?(a, b), do: a == b
end
