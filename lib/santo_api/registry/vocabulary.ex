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
    "build.variant" => :factory,
    "build.paint_code" => :factory,
    "build.production_date" => :factory,
    "provenance.delivery_dealer" => :factory,
    "provenance.delivery_date" => :factory,
    "event.service" => :event,
    "observation.mileage" => :observed
  }

  def predicates, do: Map.keys(@predicates)

  def scope_kind(predicate), do: Map.get(@predicates, predicate, :error)

  @doc """
  Are two values of this predicate the same fact? `identity.model`
  compares codes only — the label is presentation, and sources differ on
  it without disagreeing about the car.
  """
  def equivalent?("identity.model", %{"code" => a}, %{"code" => b}), do: a == b

  # Documents differ on which half they state: a CoA prints code and label, a
  # window sticker only the label. Codes settle it when both sides have one.
  def equivalent?("build.paint_code", %{"code" => a}, %{"code" => b})
      when is_binary(a) and is_binary(b),
      do: a == b

  def equivalent?("build.paint_code", %{"label" => a}, %{"label" => b}), do: a == b

  def equivalent?(_predicate, a, b), do: a == b

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

  defp validate_value("build.paint_code", %{"code" => code, "label" => label})
       when is_binary(code) or is_binary(label) do
    if valid_optional_string?(code) and valid_optional_string?(label),
      do: :ok,
      else: {:error, {:invalid_value, "build.paint_code"}}
  end

  defp validate_value("build.production_date", value), do: validate_iso_date(value)
  defp validate_value("provenance.delivery_date", value), do: validate_iso_date(value)

  defp validate_value("provenance.delivery_dealer", %{"name" => name, "location" => location})
       when is_binary(name) do
    if valid_optional_string?(location),
      do: :ok,
      else: {:error, {:invalid_value, "provenance.delivery_dealer"}}
  end

  defp validate_value("event.service", %{"summary" => summary, "performer" => performer})
       when is_binary(summary) do
    if valid_optional_string?(performer),
      do: :ok,
      else: {:error, {:invalid_value, "event.service"}}
  end

  defp validate_value("observation.mileage", value) when is_integer(value) and value >= 0,
    do: :ok

  defp validate_value(predicate, _value), do: {:error, {:invalid_value, predicate}}

  defp valid_optional_string?(value), do: is_binary(value) or is_nil(value)

  defp validate_iso_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, _date} -> :ok
      {:error, _reason} -> {:error, :invalid_date}
    end
  end

  defp validate_iso_date(_value), do: {:error, :invalid_date}
end
