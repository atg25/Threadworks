defmodule ChatApp.Search.HybridEngineBehaviour do
  alias ChatApp.Clothing.Item

  @callback search(String.t()) :: {:ok, [%Item{}]} | {:error, term()}
end
