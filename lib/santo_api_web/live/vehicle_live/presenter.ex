defmodule SantoApiWeb.VehicleLive.Presenter do
  @moduledoc """
  Turns ledger rows into the sentences a person reads.

  Nothing here decides anything. Precedence, conflict, and the two projections
  are settled in `SantoApi.Registry`; this module only chooses words. The one
  rule it enforces is the doctrine one: never say more than the ledger supports.
  A gap is a gap, not a clean record.
  """

  alias SantoApi.Registry.Vehicle

  @trait_labels %{
    "state.engine" => "Engine",
    "state.transmission" => "Transmission",
    "state.wheels_tires" => "Wheels & tires",
    "state.suspension" => "Suspension",
    "state.brakes" => "Brakes",
    "state.exterior" => "Exterior",
    "observation.mileage" => "Odometer"
  }

  @fact_labels %{
    "identity.marque" => "Marque",
    "identity.model" => "Model",
    "identity.model_year" => "Year",
    "identity.market" => "Market",
    "build.plant" => "Built at",
    "build.variant" => "Body",
    "build.paint_code" => "Paint",
    "build.production_date" => "Produced",
    "provenance.delivery_dealer" => "Delivered by",
    "provenance.delivery_date" => "Delivered"
  }

  @entry_labels %{
    "event.fuel" => "Fill-up",
    "event.service" => "Service",
    "event.modification" => "Modification",
    "event.note" => "Note",
    "event.outing" => "Outing",
    "event.sale" => "Sale",
    "observation.mileage" => "Odometer"
  }

  def trait_label(predicate), do: Map.get(@trait_labels, predicate, humanize(predicate))
  def fact_label(predicate), do: Map.get(@fact_labels, predicate, humanize(predicate))
  def entry_label(predicate), do: Map.get(@entry_labels, predicate, humanize(predicate))

  @doc """
  The name of the car, from the factory record — the one place the decode still
  leads, because a car's year and model are what it was born as.
  """
  def title(%Vehicle{} = vehicle) do
    [
      fact(vehicle, "identity.model_year"),
      fact(vehicle, "identity.marque") |> titlecase(),
      fact(vehicle, "identity.model") |> model_name()
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
    |> case do
      "" -> "Unidentified chassis"
      name -> name
    end
  end

  @doc """
  The spec line — how an owner writes their car in a forum signature.

  Composed from `current_state`, not the decode (owner_surface §6): the living
  car leads. Falls back to the paint code, which is the other thing a collector
  says first. Empty when the ledger has nothing to say, and the page says so
  rather than inventing a description.
  """
  def spec_line(%Vehicle{} = vehicle) do
    traits =
      ["state.engine", "state.exterior", "state.wheels_tires", "state.suspension"]
      |> Enum.map(&summary(vehicle.current_state[&1]))
      |> Enum.reject(&is_nil/1)

    case traits do
      [] -> Enum.reject([paint_name(vehicle)], &is_nil/1)
      traits -> traits
    end
  end

  @doc """
  Odometer, as a number a person reads. `nil` when nobody has logged one —
  the page shows a gap, never a zero.
  """
  def odometer(%Vehicle{} = vehicle) do
    case vehicle.current_state["observation.mileage"] do
      %{"value" => miles} when is_integer(miles) -> %{miles: miles, as_of: as_of(vehicle)}
      _absent -> nil
    end
  end

  defp as_of(%Vehicle{} = vehicle) do
    get_in(vehicle.current_state, ["observation.mileage", "as_of"])
  end

  @doc """
  The current-spec rows, and where each one diverges from as-built.

  Divergence is computed here at render and never stored (owner_surface §2b).
  Only a factory claim we actually hold can produce one: with no factory value
  the row is simply current, because "we don't know what it left the factory
  with" is not the same statement as "it is unchanged."
  """
  def spec_rows(%Vehicle{} = vehicle) do
    vehicle.current_state
    |> Enum.reject(fn {predicate, _entry} -> predicate == "observation.mileage" end)
    |> Enum.sort_by(fn {predicate, _entry} -> trait_label(predicate) end)
    |> Enum.map(fn {predicate, entry} ->
      %{
        predicate: predicate,
        label: trait_label(predicate),
        current: summary(entry),
        as_of: entry["as_of"],
        source: entry["source"],
        as_built: as_built(vehicle, predicate)
      }
    end)
  end

  # The factory record only speaks to a few of the traits, and only where the
  # predicate genuinely corresponds. Guessing a mapping would manufacture
  # divergence out of nothing.
  defp as_built(%Vehicle{} = vehicle, "state.exterior"), do: paint_name(vehicle)
  defp as_built(_vehicle, _predicate), do: nil

  @doc """
  Factory and provenance facts for the record section, each with the status the
  ledger computed: verified, unverified, or conflicted. Sorted so identity
  reads before build reads before provenance — the order a document states them.
  """
  def record_rows(%Vehicle{} = vehicle) do
    vehicle.facts
    |> Enum.map(fn {predicate, %{"value" => value, "status" => status}} ->
      %{
        predicate: predicate,
        label: fact_label(predicate),
        value: fact_value(predicate, value),
        status: status
      }
    end)
    |> Enum.sort_by(&{namespace_rank(&1.predicate), &1.label})
  end

  defp namespace_rank("identity." <> _rest), do: 0
  defp namespace_rank("build." <> _rest), do: 1
  defp namespace_rank("provenance." <> _rest), do: 2
  defp namespace_rank(_predicate), do: 3

  @doc """
  How much of the record is document-backed — the sale-time pitch as a stat.

  Counts facts, not claims, so one heavily-evidenced fact cannot inflate it.
  `nil` when there are no facts at all, because 0% of nothing is a lie.
  """
  def record_strength(%Vehicle{} = vehicle) do
    rows = record_rows(vehicle)

    case length(rows) do
      0 ->
        nil

      total ->
        verified = Enum.count(rows, &(&1.status == "verified"))
        %{verified: verified, total: total, percent: round(verified / total * 100)}
    end
  end

  @doc """
  One entry's headline: what happened, in the entry's own words where it has
  them. Falls back to the claim type, never to filler.
  """
  def entry_headline(entry), do: entry_parts(entry).headline

  @doc """
  One entry, split into the line that says what happened and the details that
  add to it.

  A detail earns its place only if it is not already the headline: the
  performer on a service is worth a line, the odometer reading on an entry
  that *is* an odometer reading is not.
  """
  def entry_parts(entry) do
    ordered = Enum.sort_by(entry.claims, &headline_priority/1)
    lead = Enum.find(ordered, &claim_headline/1)

    details =
      ordered
      |> Enum.reject(&(&1 == lead))
      |> Enum.map(&%{label: entry_label(&1.predicate), value: claim_detail(&1)})
      |> Enum.reject(&is_nil(&1.value))

    headline =
      case lead do
        nil -> entry_label(hd(ordered).predicate)
        claim -> claim_headline(claim)
      end

    details =
      if lead && second_fact?(lead),
        do: [%{label: entry_label(lead.predicate), value: claim_detail(lead)} | details],
        else: details

    %{headline: headline, details: details}
  end

  # Whether a claim's detail is a *second* fact or the same one again. A
  # service's headline is what was done and its detail is who did it — two
  # facts. An odometer's detail is its reading, which the headline already was.
  defp second_fact?(%{predicate: "event.service"}), do: true
  defp second_fact?(%{predicate: "event.outing"}), do: true
  defp second_fact?(_claim), do: false

  @doc "The one extra fact an entry's claim carries beyond its headline."
  def claim_detail(%{predicate: "observation.mileage", value: miles}) when is_integer(miles),
    do: "#{delimit(miles)} mi"

  def claim_detail(%{predicate: "event.service", value: %{"performer" => performer}})
      when is_binary(performer),
      do: performer

  def claim_detail(%{predicate: "event.outing", value: %{"venue" => venue}})
      when is_binary(venue),
      do: venue

  def claim_detail(%{
        predicate: "event.sale",
        value: %{"price" => price, "currency" => currency}
      }),
      do: money(price, currency)

  def claim_detail(_claim), do: nil

  # What happened leads. The odometer on a fill-up is a detail of the fill-up,
  # so a reading only becomes the headline when it is the whole entry.
  defp headline_priority(%{predicate: "observation." <> _rest}), do: 1
  defp headline_priority(_claim), do: 0

  defp claim_headline(%{predicate: "event.service", value: %{"summary" => summary}}), do: summary
  defp claim_headline(%{predicate: "event.modification", value: %{"summary" => s}}), do: s
  defp claim_headline(%{predicate: "event.note", value: %{"text" => text}}), do: text

  defp claim_headline(%{predicate: "event.outing", value: value}),
    do: value["summary"] || value["result"] || outing_kind(value["kind"])

  defp claim_headline(%{predicate: "event.sale", value: value}), do: sale_headline(value)

  defp claim_headline(%{predicate: "event.fuel", value: %{"volume" => v, "unit" => unit}}),
    do: "#{v} #{unit} of fuel"

  defp claim_headline(%{predicate: "observation.mileage", value: miles}) when is_integer(miles),
    do: "#{delimit(miles)} miles"

  defp claim_headline(_claim), do: nil

  defp outing_kind(nil), do: "Outing"
  defp outing_kind(kind), do: String.capitalize(kind)

  defp sale_headline(%{"venue" => venue, "price" => price, "currency" => currency}) do
    "Sold at #{venue} for #{money(price, currency)}"
  end

  defp sale_headline(_value), do: "Sale"

  @doc """
  Money from integer minor units. Never floats — the arithmetic stays exact
  all the way to the screen.
  """
  def money(amount, "USD"), do: "$" <> delimit(amount)
  def money(amount, currency), do: "#{delimit(amount)} #{currency}"

  @doc "Thousands separators, the way an odometer or a hammer price reads."
  def delimit(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  @doc """
  A date as a person says it. Accepts the ISO strings that come back out of
  jsonb as readily as a `Date`.
  """
  def on_date(nil), do: nil
  def on_date(%Date{} = date), do: Calendar.strftime(date, "%-d %B %Y")

  def on_date(iso) when is_binary(iso) do
    case Date.from_iso8601(iso) do
      {:ok, date} -> on_date(date)
      {:error, _reason} -> iso
    end
  end

  def year_of(nil), do: nil
  def year_of(%Date{} = date), do: Integer.to_string(date.year)

  def year_of(iso) when is_binary(iso) do
    case Date.from_iso8601(iso) do
      {:ok, date} -> year_of(date)
      {:error, _reason} -> nil
    end
  end

  @doc "The VIN or chassis number, without the internal key prefix."
  def chassis(%Vehicle{identity_key: "vin:" <> vin}), do: vin
  def chassis(%Vehicle{identity_key: key}), do: key |> String.split(":") |> List.last()

  def identity_label(%Vehicle{identity_kind: :vin}), do: "VIN"
  def identity_label(%Vehicle{identity_kind: :chassis}), do: "Chassis"
  def identity_label(%Vehicle{identity_kind: :disputed}), do: "Disputed identity"

  defp paint_name(%Vehicle{} = vehicle) do
    case vehicle.facts["build.paint_code"] do
      %{"value" => %{"label" => label}} when is_binary(label) -> label
      %{"value" => %{"code" => code}} when is_binary(code) -> "Paint code #{code}"
      _absent -> nil
    end
  end

  def paint_code(%Vehicle{} = vehicle) do
    case vehicle.facts["build.paint_code"] do
      %{"value" => %{"code" => code}} when is_binary(code) -> code
      _absent -> nil
    end
  end

  defp summary(%{"value" => %{"summary" => summary}}) when is_binary(summary), do: summary
  defp summary(%{"value" => value}) when is_binary(value), do: value
  defp summary(_absent), do: nil

  defp fact_value("identity.model", value), do: model_name(value)
  defp fact_value("identity.market", "us"), do: "United States"
  defp fact_value("identity.market", "row"), do: "Rest of world"
  defp fact_value("identity.marque", value), do: titlecase(value)

  defp fact_value(_predicate, %{"label" => label, "code" => code}) when is_binary(label),
    do: if(is_binary(code), do: "#{label} (#{code})", else: label)

  defp fact_value(_predicate, %{"code" => code}) when is_binary(code), do: code

  defp fact_value(_predicate, %{"name" => name, "location" => location}) when is_binary(name),
    do: if(is_binary(location), do: "#{name}, #{location}", else: name)

  defp fact_value(predicate, value) when is_binary(value) do
    if String.ends_with?(predicate, "_date"), do: on_date(value), else: value
  end

  defp fact_value(_predicate, value) when is_integer(value), do: Integer.to_string(value)
  defp fact_value(_predicate, value), do: inspect(value)

  defp model_name(%{"label" => label}) when is_binary(label), do: label
  defp model_name(%{"code" => code}) when is_binary(code), do: humanize(code)
  defp model_name(_absent), do: nil

  defp titlecase(nil), do: nil
  defp titlecase(value) when is_binary(value), do: String.capitalize(value)

  defp fact(%Vehicle{} = vehicle, predicate) do
    case vehicle.facts[predicate] do
      %{"value" => value} -> value
      _absent -> nil
    end
  end

  defp humanize(term) do
    term
    |> String.split(~r/[._]/)
    |> List.last()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
