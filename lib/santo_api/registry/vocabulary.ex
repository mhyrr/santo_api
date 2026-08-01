defmodule SantoApi.Registry.Vocabulary do
  @moduledoc """
  The closed claim-predicate vocabulary (evidence contract §3, fork B).

  Only predicates listed here exist; adding one is a code change, like
  santo's compiled data. Each predicate carries its scope kind and a
  value validator. `Registry` refuses to persist a claim the vocabulary
  rejects.
  """

  @markets ~w(us row)
  @fuel_units ~w(gal l)
  @outing_kinds ~w(autocross track show drive other)

  # The current-state seed traits (owner_surface.md §2b). These are the only
  # predicates an event's `sets` deltas may target — the fold's input surface.
  @trait_predicates ~w(
    state.engine
    state.transmission
    state.wheels_tires
    state.suspension
    state.brakes
    state.exterior
  )

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
                "event.sale" => :event,
                "event.fuel" => :event,
                "event.modification" => :event,
                "event.note" => :event,
                "event.outing" => :event,
                "observation.mileage" => :observed
              }
              |> Map.merge(Map.new(@trait_predicates, &{&1, :observed}))

  def trait_predicates, do: @trait_predicates

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

  defp validate_value("event.sale", %{"venue" => venue, "price" => price, "currency" => currency})
       when is_binary(venue) and is_integer(price) and price >= 0 and is_binary(currency),
       do: :ok

  defp validate_value("event.service", %{"summary" => summary, "performer" => performer})
       when is_binary(summary) do
    if valid_optional_string?(performer),
      do: :ok,
      else: {:error, {:invalid_value, "event.service"}}
  end

  defp validate_value("observation.mileage", value) when is_integer(value) and value >= 0,
    do: :ok

  defp validate_value("event.fuel", %{"volume" => volume, "unit" => unit} = value)
       when is_binary(volume) and unit in @fuel_units do
    valid? =
      valid_decimal_string?(volume) and
        valid_optional_non_neg_int?(Map.get(value, "total_cents")) and
        valid_optional_string?(Map.get(value, "currency")) and
        valid_optional_string?(Map.get(value, "grade")) and
        valid_optional_string?(Map.get(value, "station")) and
        Map.get(value, "partial") in [nil, true, false]

    if valid?, do: :ok, else: {:error, {:invalid_value, "event.fuel"}}
  end

  defp validate_value("event.modification", %{"summary" => summary} = value)
       when is_binary(summary) do
    if valid_optional_string?(Map.get(value, "area")) and
         valid_optional_string?(Map.get(value, "detail")) do
      validate_sets(Map.get(value, "sets"), "event.modification")
    else
      {:error, {:invalid_value, "event.modification"}}
    end
  end

  defp validate_value("event.note", %{"text" => text}) when is_binary(text), do: :ok

  defp validate_value("event.outing", %{"kind" => kind} = value) when kind in @outing_kinds do
    if valid_optional_string?(Map.get(value, "venue")) and
         valid_optional_string?(Map.get(value, "result")) and
         valid_optional_string?(Map.get(value, "summary")) do
      validate_sets(Map.get(value, "sets"), "event.outing")
    else
      {:error, {:invalid_value, "event.outing"}}
    end
  end

  defp validate_value("state." <> _ = predicate, %{"summary" => summary} = value)
       when is_binary(summary) do
    if valid_optional_string?(Map.get(value, "code")) and
         valid_optional_string?(Map.get(value, "detail")),
       do: :ok,
       else: {:error, {:invalid_value, predicate}}
  end

  defp validate_value(predicate, _value), do: {:error, {:invalid_value, predicate}}

  # Deltas may target only the state.* traits — never observations or factory
  # facts — and each delta's value must satisfy its trait's own validator.
  defp validate_sets(nil, _event), do: :ok

  defp validate_sets(sets, event) when is_list(sets) do
    valid? =
      Enum.all?(sets, fn
        %{"predicate" => predicate, "value" => value} ->
          predicate in @trait_predicates and validate(predicate, value) == :ok

        _other ->
          false
      end)

    if valid?, do: :ok, else: {:error, {:invalid_value, event}}
  end

  defp validate_sets(_sets, event), do: {:error, {:invalid_value, event}}

  defp valid_optional_string?(value), do: is_binary(value) or is_nil(value)

  defp valid_optional_non_neg_int?(value),
    do: is_nil(value) or (is_integer(value) and value >= 0)

  defp valid_decimal_string?(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> not Decimal.negative?(decimal)
      _other -> false
    end
  end

  defp validate_iso_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, _date} -> :ok
      {:error, _reason} -> {:error, :invalid_date}
    end
  end

  defp validate_iso_date(_value), do: {:error, :invalid_date}
end
