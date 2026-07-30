defmodule SantoApi.Registry.Vocabulary do
  @moduledoc """
  The closed claim-predicate vocabulary (evidence contract §3, fork B).

  Only predicates listed here exist; adding one is a code change, like
  santo's compiled data. Each predicate carries its scope kind and a
  value validator. `Registry` refuses to persist a claim the vocabulary
  rejects.
  """

  @markets ~w(us row)

  @predicates %{
    "identity.marque" => :factory,
    "identity.model" => :factory,
    "identity.model_year" => :factory,
    "identity.market" => :factory,
    "build.plant" => :factory,
    "build.variant" => :factory
  }

  def predicates, do: Map.keys(@predicates)

  def scope_kind(predicate), do: Map.get(@predicates, predicate, :error)

  def validate(predicate, value) do
    case Map.fetch(@predicates, predicate) do
      {:ok, _scope} -> validate_value(predicate, value)
      :error -> {:error, :unknown_predicate}
    end
  end

  defp validate_value("identity.marque", value) when is_binary(value), do: :ok

  defp validate_value("identity.model", %{"code" => code, "label" => label})
       when is_binary(code) and (is_binary(label) or is_nil(label)),
       do: :ok

  defp validate_value("identity.model_year", value) when is_integer(value), do: :ok

  defp validate_value("identity.market", value) when value in @markets, do: :ok

  defp validate_value("build.plant", value) when is_binary(value), do: :ok

  defp validate_value("build.variant", value) when is_binary(value), do: :ok

  defp validate_value(predicate, _value), do: {:error, {:invalid_value, predicate}}
end
