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
  # Completed sales keep the legacy canonical shape with no outcome key.
  # Only the exceptional result is encoded, avoiding two hashes for one fact.
  @sale_outcomes [nil, "not_sold"]

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

  @doc """
  The canonical value for a predicate, from the shapes a caller may state it in.

  Per-predicate knowledge lives here beside `validate/2` and `equivalent?/3`,
  so a caller that speaks a dialect of one predicate is understood in exactly
  one place rather than at every door.

  **Store the measured, derive the ratio.** A fill-up's gallons and the amount
  paid are both measured and both storable exactly; the price per gallon
  between them is a quotient, and the good ones do not terminate — $67.45 over
  13.1 gallons is $5.148854…, which no fixed number of decimal places holds.
  So the ledger keeps the two measurements and the ratio is computed at read
  time, where rounding is free because nobody reconciles a price per gallon.
  A total is reconciled — against a receipt, against a card statement — so it
  is the number stored, exactly, in integer cents. `event.sale` already holds
  money this way.

  An owner who states a price per gallon has it multiplied out once, here, and
  what lands in the ledger is a total they can check. A price nobody can read
  is dropped rather than guessed at: a fill-up with no money on it is a fact,
  and an invented total is not.
  """
  def normalize("event.fuel", %{"volume" => volume} = value) when is_map(value) do
    stripped = Map.drop(value, ["cost", "unit_price"])

    case fuel_total_cents(value, volume) do
      nil -> stripped
      cents -> Map.put(stripped, "total_cents", cents)
    end
  end

  def normalize(_predicate, value), do: value

  defp fuel_total_cents(%{"total_cents" => cents}, _volume) when is_integer(cents), do: cents
  defp fuel_total_cents(%{"cost" => cost}, _volume), do: money_to_cents(cost)
  defp fuel_total_cents(%{"unit_price" => price}, volume), do: multiply_out(price, volume)
  defp fuel_total_cents(_value, _volume), do: nil

  defp money_to_cents(stated) do
    with %Decimal{} = amount <- to_decimal(stated),
         false <- Decimal.negative?(amount) do
      to_cents(amount)
    else
      _unreadable -> nil
    end
  end

  # The one rounding this shape ever does, and it happens on the way in rather
  # than on every read: half a cent, once, against a number the owner can check.
  defp multiply_out(stated_price, stated_volume) do
    with %Decimal{} = price <- to_decimal(stated_price),
         %Decimal{} = volume <- to_decimal(stated_volume),
         false <- Decimal.negative?(price) or Decimal.negative?(volume) do
      price |> Decimal.mult(volume) |> to_cents()
    else
      _unreadable -> nil
    end
  end

  defp to_cents(%Decimal{} = dollars) do
    dollars |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer()
  end

  # A JSON number from an assistant is rounded to the cent rather than refused.
  # The float is gone by the time anything stores it, which is what the money
  # rule is actually protecting.
  defp to_decimal(value) when is_binary(value) do
    case value |> String.trim() |> String.trim_leading("$") |> Decimal.parse() do
      {decimal, ""} -> decimal
      _unparseable -> nil
    end
  end

  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp to_decimal(_value), do: nil

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

  defp validate_value(
         "event.sale",
         %{"venue" => venue, "price" => price, "currency" => currency} = value
       )
       when is_binary(venue) and is_integer(price) and price >= 0 and is_binary(currency) do
    if Map.get(value, "outcome") in @sale_outcomes,
      do: :ok,
      else: {:error, {:invalid_value, "event.sale"}}
  end

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
