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

  # What each predicate has room for — the second half of `normalize/2`, which
  # keeps what a predicate holds and hands back the rest as words rather than
  # swallowing it (Greg, 2026-08-04: no key for it, keep it as text anyway).
  #
  # Written by hand because it cannot be derived. Each `validate_value/2` clause
  # is a pattern match with guards, not a list a machine can read back, so the
  # keys exist twice and the two copies have to be kept honest by hand.
  #
  # **Both directions of drift are bugs, and they fail differently.** A key here
  # the validator rejects survives normalization and then fails validation — the
  # whole claim drops to the note, and a good fill-up arrives as prose. A key
  # the validator accepts but that is missing here gets lifted out of a claim it
  # belonged in, so the ledger quietly holds less than the owner said and the
  # difference reads as a stray fragment in a note. The first is loud, the
  # second is not, which makes the second the one to watch.
  #
  # The guard: `vocabulary_test.exs` walks every predicate below with a value
  # carrying all of its keys and asserts nothing was lifted. That catches the
  # quiet direction. The loud one is caught by any test that logs an entry.
  #
  # Listed only for predicates a person states in their own words. A predicate
  # absent from this map keeps its value whole — `known_keys/1` returning nil
  # means "lift nothing," not "lift everything" — which is why the factory
  # namespaces can stay out of it: they arrive from providers and the bench
  # already shaped, and inventing key sets for them would be guesses guarding
  # a door nobody uses.
  @known_keys %{
    "event.fuel" => ~w(volume unit total_cents currency grade station partial),
    "event.service" => ~w(summary performer),
    "event.modification" => ~w(summary area detail sets),
    "event.note" => ~w(text),
    "event.plan" => ~w(text area),
    "event.outing" => ~w(kind venue result summary sets)
  }

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
                "event.plan" => :event,
                "event.outing" => :event,
                # The build thread's opening post (owner_surface §7b): the one
                # entry origination writes, carrying the sentence the owner
                # typed. Written by the origination path only, never offered by
                # the composer — a record starts once.
                "event.origination" => :event,
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
  Split a stated value into what this predicate can hold and what it cannot.

  Returns `{value, leftover}`. Per-predicate knowledge lives here beside
  `validate/2` and `equivalent?/3`, so a caller that speaks a dialect of one
  predicate is understood in exactly one place rather than at every door.

  **Nothing is discarded.** A key this predicate has no room for — and a value
  it cannot read — comes back in `leftover` for the caller to keep as text.
  The alternative is a claim that silently holds less than the owner said, and
  the entry is still logged as what it is: a fill-up with an unreadable price
  is a fill-up, not a note.

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
  what lands in the ledger is a total they can check.
  """
  def normalize(predicate, value) when is_map(value) do
    value
    |> canonical(predicate)
    |> split_known(predicate)
  end

  def normalize(_predicate, value), do: {value, %{}}

  # Only the key actually read is removed. A price that lost to an explicit
  # total, or one nothing could parse, stays in the map — `split_known/2` lifts
  # it into the leftover a moment later, which is how it survives as words.
  defp canonical(%{"volume" => _volume} = value, "event.fuel") do
    case fuel_total_cents(value) do
      :none -> value
      {cents, read} -> value |> Map.put("total_cents", cents) |> Map.drop(List.wrap(read))
    end
  end

  defp canonical(value, _predicate), do: value

  # Precedence: an explicit total, then a stated one, then a unit price to
  # multiply out.
  defp fuel_total_cents(value) do
    cond do
      is_integer(value["total_cents"]) -> {value["total_cents"], nil}
      cents = money_to_cents(value["cost"]) -> {cents, "cost"}
      cents = multiply_out(value["unit_price"], value["volume"]) -> {cents, "unit_price"}
      true -> :none
    end
  end

  # Unlisted means keep the value whole. The default has to be the harmless one:
  # a predicate nobody wrote a key set for should hold everything it was given,
  # not have every field lifted into a note.
  defp split_known(value, predicate) do
    case known_keys(predicate) do
      nil -> {value, %{}}
      keys -> Map.split(value, keys)
    end
  end

  # A family rather than a predicate, so it cannot live in the map above: every
  # `state.*` trait shares one validator and therefore one key set.
  defp known_keys("state." <> _rest), do: ~w(summary code detail)
  defp known_keys(predicate), do: Map.get(@known_keys, predicate)

  @doc """
  The predicates `normalize/2` splits keys for, so the test that guards the key
  sets against drift can require a fixture for each rather than trusting a
  hand-kept list to have stayed complete.
  """
  def normalizing_predicates, do: Map.keys(@known_keys)

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

  defp validate_value("event.plan", %{"text" => text} = value) when is_binary(text) do
    if valid_optional_string?(Map.get(value, "area")),
      do: :ok,
      else: {:error, {:invalid_value, "event.plan"}}
  end

  defp validate_value("event.origination", %{"text" => text}) when is_binary(text), do: :ok

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
