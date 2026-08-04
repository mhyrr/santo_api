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
    # Built from the record only. A marque inferred from the identity key is
    # not a name for the car, so it belongs in the fallback, not here.
    [
      fact(vehicle, "identity.model_year"),
      fact(vehicle, "identity.marque") |> titlecase(),
      fact(vehicle, "identity.model") |> model_name()
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
    |> case do
      "" -> untitled(vehicle)
      name -> name
    end
  end

  # A pre-standard chassis we cannot decode is not unidentified — we know
  # exactly which car it is, we just do not know what to call it. Saying
  # "unidentified" would understate the record.
  defp untitled(%Vehicle{identity_kind: :chassis} = vehicle) do
    [marque(vehicle), "chassis", chassis(vehicle)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp untitled(%Vehicle{} = vehicle), do: marque(vehicle) || "Undecoded chassis"

  @doc """
  The marque, from the factory record where we have one and from the identity
  key otherwise — a pre-standard chassis carries its marque in the key.
  """
  def marque(%Vehicle{} = vehicle) do
    case fact(vehicle, "identity.marque") do
      marque when is_binary(marque) -> titlecase(marque)
      _absent -> marque_from_key(vehicle.identity_key)
    end
  end

  defp marque_from_key("chassis:" <> rest),
    do: rest |> String.split(":") |> hd() |> titlecase()

  defp marque_from_key(_key), do: nil

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
  def record_rows(%Vehicle{} = vehicle, provenance \\ %{}) do
    vehicle.facts
    |> Enum.map(fn {predicate, %{"value" => value, "status" => status}} ->
      receipts = Map.get(provenance, predicate, %{claims: [], sources: []})
      dom_id = fact_dom_id(predicate)

      %{
        predicate: predicate,
        label: fact_label(predicate),
        value: fact_value(predicate, value),
        status: status,
        dom_id: dom_id,
        claims: Enum.map(receipts.claims, &record_claim(predicate, &1)),
        sources: Enum.map(receipts.sources, &record_source(dom_id, &1))
      }
    end)
    |> Enum.sort_by(&{namespace_rank(&1.predicate), &1.label})
  end

  defp record_claim(predicate, claim) do
    claim
    |> Map.put(:dom_id, "claim-#{claim.claim_id}")
    |> Map.update!(:value, &fact_value(predicate, &1))
  end

  defp record_source(fact_dom_id, source) do
    source
    |> Map.put(:label, Enum.join(source.parties, ", "))
    |> Map.put(:dom_id, "#{fact_dom_id}-source-#{source_key(source.url)}")
  end

  defp fact_dom_id(predicate) do
    "fact-" <> String.replace(predicate, ~r/[^a-zA-Z0-9_-]/, "-")
  end

  defp source_key(url) do
    :sha256
    |> :crypto.hash(url)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
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

    if Enum.all?(ordered, &trait_claim?/1),
      do: spec_parts(ordered),
      else: event_parts(ordered)
  end

  # An entry made only of trait claims is the spec panel's work (§2b), not an
  # event. It has no "what happened" to lead with, so every trait reads as a
  # labelled line instead of one of them being promoted into a headline.
  defp spec_parts(claims) do
    %{
      headline: "Spec recorded",
      details:
        Enum.map(claims, &%{label: trait_label(&1.predicate), value: trait_summary(&1.value)})
    }
  end

  defp trait_claim?(%{predicate: "state." <> _rest}), do: true
  defp trait_claim?(_claim), do: false

  defp trait_summary(%{"summary" => summary}) when is_binary(summary), do: summary
  defp trait_summary(value), do: inspect(value)

  defp event_parts(ordered) do
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

    %{headline: headline, details: lead_details(lead) ++ details}
  end

  # The facts a lead claim carries beyond its own headline. A service's
  # headline is what was done and its detail is who did it — two facts. An
  # odometer's detail is its reading, which the headline already was, so it
  # contributes nothing.
  #
  # A list rather than a flag, because "this claim has a second fact" and "this
  # particular claim actually stated it" are different questions. A service with
  # no performer answers yes to the first and no to the second, and the answer
  # has to be no line at all — an empty labelled chip reads as a fact we are
  # withholding rather than one nobody gave us.
  defp lead_details(%{predicate: "event.service"} = claim), do: own_detail(claim)
  defp lead_details(%{predicate: "event.outing"} = claim), do: own_detail(claim)
  defp lead_details(_claim), do: []

  defp own_detail(claim) do
    case claim_detail(claim) do
      nil -> []
      value -> [%{label: entry_label(claim.predicate), value: value}]
    end
  end

  @doc "The one extra fact an entry's claim carries beyond its headline."
  def claim_detail(%{predicate: "observation.mileage", value: miles}) when is_integer(miles),
    do: "#{delimit(miles)} mi"

  # The words an entry kept because no key fit them. They read as an ordinary
  # note (Greg, 2026-08-04) — the ledger is honest about how they got here and
  # the page does not need to be, because a line saying we failed to parse
  # something is not the owner's news to publish to everyone reading the car.
  def claim_detail(%{predicate: "event.note", value: %{"text" => text}}) when is_binary(text),
    do: text

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
  #
  # A note ranks between the two, and the rank is what makes a residual safe to
  # show. The salvaged fragment of a fill-up is an `event.note` sharing its
  # entry with the fill-up, and a note that outranked it would take the
  # headline and drop the structured claim entirely — the entry would read as
  # "pump: 4" and the 13.1 gallons would be nowhere. Ordering by what the claim
  # is rather than by the order it arrived in settles that for every caller:
  # an assistant may send its claims in any order, and the entry reads the same.
  # A note still leads when it is the most specific thing in the entry, which is
  # exactly the case where it is the whole entry.
  defp headline_priority(%{predicate: "event.note"}), do: 1
  defp headline_priority(%{predicate: "observation." <> _rest}), do: 2
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

  defp sale_headline(%{
         "venue" => venue,
         "price" => price,
         "currency" => currency,
         "outcome" => "not_sold"
       }) do
    "High bid of #{money(price, currency)} at #{venue}; not sold"
  end

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

  @doc "A public artifact kind as a compact human label."
  def artifact_kind(kind) when is_atom(kind) do
    kind
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
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

  # Both fields are real names and which one a person uses depends on the car.
  # A 911 is `code: "911", label: "993"` and Porsche people say 993 — the label
  # is the generation and it is the more specific of the two. A Carrera GT is
  # `code: "carrera_gt", label: "980"` and nobody calls it a 980. The line
  # between them: a numeric label only loses to a code that is a *word*.
  defp model_name(%{"code" => code, "label" => label}) when is_binary(label) do
    if numeric?(label) and is_binary(code) and named?(code),
      do: model_from_code(code),
      else: label
  end

  defp model_name(%{"code" => code}) when is_binary(code), do: model_from_code(code)
  defp model_name(_absent), do: nil

  defp numeric?(value), do: String.match?(value, ~r/\A\d+\z/)

  defp named?(code), do: String.match?(code, ~r/[a-z]/i)

  # "carrera_gt" reads as "Carrera GT": words capitalise, and a token with no
  # vowel in it is an initialism (gt, rs, gts) rather than a word.
  defp model_from_code(code) do
    code
    |> String.split("_")
    |> Enum.map_join(" ", fn
      token ->
        if String.match?(token, ~r/\A[^aeiou]+\z/i),
          do: String.upcase(token),
          else: String.capitalize(token)
    end)
  end

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
