defmodule SantoApi.Logbook.EntryDraft do
  @moduledoc """
  The deterministic grammar of the web entry composer.

  Both structured typing and natural-language extraction end here. The model
  may suggest a mode and values; this module parses numbers, computes money,
  and emits the closed claim vocabulary that `SantoApi.Owners` authorizes and
  persists.
  """

  alias SantoApi.Registry.Vocabulary

  @modes [:fuel, :service, :modification, :outing, :note]

  def modes, do: @modes

  @doc "Turn an extracted reading into ordinary, editable composer params."
  def from_reading(reading, original, today \\ Date.utc_today()) do
    mode = if reading.mode in @modes, do: reading.mode, else: :note

    params = %{
      "date" => Date.to_iso8601(reading.date || today),
      "odometer" => integer_string(reading.odometer),
      "volume" => reading.volume || "",
      "unit" => reading.unit || "gal",
      "price" => total_price(reading),
      "currency" => reading.currency || "USD",
      "summary" => reading.summary || "",
      "performer" => reading.performer || "",
      "area" => reading.area || "",
      "outing_kind" => reading.outing_kind || "drive",
      "venue" => reading.venue || "",
      "result" => reading.result || "",
      "text" => reading.note || reading.summary || original
    }

    {mode, params}
  end

  @doc "The no-loss fallback when extraction is unavailable or unreadable."
  def note_fallback(original, today \\ Date.utc_today()) do
    {:note, %{"date" => Date.to_iso8601(today), "text" => String.trim(original)}}
  end

  @doc "Map editable form params onto the reviewed claim vocabulary."
  def claims(:fuel, params) do
    with {:ok, volume} <-
           required_decimal(params["volume"], "A fill-up needs to know how much fuel went in."),
         {:ok, cents} <- optional_cents(params["price"]),
         {:ok, currency} <- fuel_currency(params["currency"]),
         {:ok, odometer} <-
           optional_integer(params["odometer"], "That odometer reading is not a number.") do
      fuel =
        %{"volume" => volume, "unit" => fuel_unit(params["unit"])}
        |> put_unless_nil("total_cents", cents)
        |> put_unless_nil("currency", cents && currency)

      {:ok, [%{predicate: "event.fuel", value: fuel}] ++ mileage(odometer)}
    end
  end

  def claims(:service, params) do
    with {:ok, summary} <- required_text(params["summary"], "Say what was done."),
         {:ok, odometer} <-
           optional_integer(params["odometer"], "That odometer reading is not a number.") do
      service = %{"summary" => summary, "performer" => trimmed(params["performer"])}
      {:ok, [%{predicate: "event.service", value: service}] ++ mileage(odometer)}
    end
  end

  def claims(:modification, params) do
    with {:ok, summary} <- required_text(params["summary"], "Say what changed."),
         {:ok, sets} <- trait_delta(params) do
      modification =
        %{"summary" => summary}
        |> put_unless_nil("area", trimmed(params["area"]))
        |> put_unless_nil("sets", sets)

      {:ok, [%{predicate: "event.modification", value: modification}]}
    end
  end

  def claims(:outing, params) do
    with {:ok, summary} <- required_text(params["summary"], "Say something about the drive."),
         {:ok, odometer} <-
           optional_integer(params["odometer"], "That odometer reading is not a number.") do
      outing =
        %{"kind" => outing_kind(params["outing_kind"]), "summary" => summary}
        |> put_unless_nil("venue", trimmed(params["venue"]))
        |> put_unless_nil("result", trimmed(params["result"]))

      {:ok, [%{predicate: "event.outing", value: outing}] ++ mileage(odometer)}
    end
  end

  def claims(:note, params) do
    with {:ok, text} <- required_text(params["text"], "Nothing to log yet — say something first.") do
      {:ok, [%{predicate: "event.note", value: %{"text" => text}}]}
    end
  end

  def claims(_unknown, params), do: claims(:note, params)

  defp trait_delta(params) do
    case {trimmed(params["trait"]), trimmed(params["trait_summary"])} do
      {nil, _summary} ->
        {:ok, nil}

      {trait, nil} when is_binary(trait) ->
        {:error, "Say what that part of the car is now."}

      {trait, summary} ->
        if trait in Vocabulary.trait_predicates() do
          {:ok, [%{"predicate" => trait, "value" => %{"summary" => summary}}]}
        else
          {:error, "That part of the car is not available here."}
        end
    end
  end

  defp total_price(%{total_price: price}) when is_binary(price), do: price

  defp total_price(%{unit_price: unit_price, volume: volume})
       when is_binary(unit_price) and is_binary(volume) do
    with {price, ""} <- Decimal.parse(String.trim_leading(unit_price, "$")),
         {amount, ""} <- Decimal.parse(volume),
         false <- Decimal.negative?(price) or Decimal.negative?(amount) do
      price |> Decimal.mult(amount) |> Decimal.round(2) |> Decimal.to_string(:normal)
    else
      _unreadable -> ""
    end
  end

  defp total_price(_reading), do: ""

  defp integer_string(value) when is_integer(value), do: Integer.to_string(value)
  defp integer_string(_value), do: ""

  defp fuel_unit("l"), do: "l"
  defp fuel_unit(_unit), do: "gal"

  defp fuel_currency(value) do
    currency = String.upcase(trimmed(value) || "USD")

    if Regex.match?(~r/^[A-Z]{3}$/, currency),
      do: {:ok, currency},
      else: {:error, "Use a three-letter currency code, such as USD or EUR."}
  end

  defp outing_kind(value) when value in ~w(autocross track show drive other), do: value
  defp outing_kind(_value), do: "drive"

  defp mileage(nil), do: []
  defp mileage(odometer), do: [%{predicate: "observation.mileage", value: odometer}]

  defp required_text(value, message) do
    case trimmed(value) do
      nil -> {:error, message}
      text -> {:ok, text}
    end
  end

  defp required_decimal(value, message) do
    case trimmed(value) do
      nil ->
        {:error, message}

      text ->
        case Decimal.parse(text) do
          {decimal, ""} ->
            if Decimal.negative?(decimal),
              do: {:error, "A volume cannot be negative."},
              else: {:ok, Decimal.to_string(decimal, :normal)}

          _unparseable ->
            {:error, "That volume is not a number."}
        end
    end
  end

  defp optional_cents(value) do
    case trimmed(value) do
      nil ->
        {:ok, nil}

      text ->
        case Decimal.parse(String.trim_leading(text, "$")) do
          {decimal, ""} ->
            if Decimal.negative?(decimal),
              do: {:error, "A price cannot be negative."},
              else:
                {:ok, decimal |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer()}

          _unparseable ->
            {:error, "That price is not a number."}
        end
    end
  end

  defp optional_integer(value, message) do
    case trimmed(value) do
      nil ->
        {:ok, nil}

      text ->
        case Integer.parse(String.replace(text, ",", "")) do
          {integer, ""} when integer >= 0 -> {:ok, integer}
          _unparseable -> {:error, message}
        end
    end
  end

  defp trimmed(nil), do: nil

  defp trimmed(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp put_unless_nil(map, _key, nil), do: map
  defp put_unless_nil(map, key, value), do: Map.put(map, key, value)
end
