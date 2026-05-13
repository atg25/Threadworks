defmodule ChatApp.AI.StyleAdvisorBehaviour do
  @callback augment(String.t(), keyword()) :: {:ok, String.t(), list()}
end
