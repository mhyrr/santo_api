defmodule SantoApiWeb.MCP.Tools do
  @moduledoc """
  The tool set (owner_surface §8), deliberately small.

  Five tools: what cars are mine, log something, fix it, remove it, read it
  back. Retrieval is half the reason to keep a log, and `get_timeline` is what
  makes the assistant a reader of the record rather than only a scribe.

  Two rules run through all of it.

  **Nothing an owner says is ever rejected for vocabulary.** The predicate
  vocabulary is closed and stays closed — adding one is a reviewed code change
  — but a closed vocabulary is a constraint on *us*, not a spelling test for
  the owner. Anything that does not fit is kept verbatim in the note residual.
  A logbook that argues with you is a logbook you stop using.

  **The owner asserts; the model only carries.** Claims land attributed to the
  owner's party with `method: :llm_extract`, so the ledger records that a
  model mediated without pretending the model is the source. Per Greg's call
  on 2026-08-03 there is no confirm step — the tool call is the owner's
  assertive act — and correction is what catches a mishearing instead.
  """

  alias SantoApi.Accounts.Scope
  alias SantoApi.Owners
  alias SantoApi.Registry
  alias SantoApi.Registry.Vocabulary
  alias SantoApiWeb.VehicleLive.Presenter

  @vehicle_arg %{
    type: "string",
    description: "The car's short id, as returned by my_vehicles (e.g. \"j4q6ws6zfm\")."
  }

  @claims_arg %{
    type: "array",
    description: """
    What happened, as one or more claims. Recognised predicates are
    event.fuel, event.service, event.modification, event.outing, event.note,
    and observation.mileage. Anything else you pass is kept verbatim as a note
    rather than rejected, so prefer logging an imperfect match over dropping
    what the owner said.
    """,
    items: %{
      type: "object",
      required: ["predicate", "value"],
      properties: %{
        predicate: %{type: "string"},
        value: %{
          description:
            "Shape depends on the predicate: observation.mileage is an integer, " <>
              "event.fuel takes volume, unit (gal or l), total_cents (what was " <>
              "paid, in whole cents) and currency — send unit_price instead if " <>
              "the owner gave a price per gallon and it is multiplied out for " <>
              "you. The event.* rest take an object with a text field."
        }
      }
    }
  }

  @tools [
    %{
      name: "my_vehicles",
      description:
        "The cars this person maintains a logbook for. Call this first — every " <>
          "other tool needs the short id it returns.",
      inputSchema: %{type: "object", properties: %{}, required: []}
    },
    %{
      name: "log_entry",
      description:
        "Record something that happened to a car: a fill-up, a service, a track " <>
          "day, a modification, an odometer reading, or a plain note. Write what " <>
          "the owner said without rounding or inferring, then read the entry back " <>
          "to them so a mishearing gets caught while you are still talking.",
      inputSchema: %{
        type: "object",
        required: ["vehicle", "date", "claims"],
        properties: %{
          vehicle: @vehicle_arg,
          date: %{
            type: "string",
            description:
              "The day it happened, as YYYY-MM-DD. Resolve \"Friday\" or " <>
                "\"yesterday\" against today's date before calling; never guess a " <>
                "date the owner did not give you."
          },
          claims: @claims_arg,
          note: %{
            type: "string",
            description: "Anything else worth keeping, in the owner's own words."
          }
        }
      }
    },
    %{
      name: "amend_entry",
      description:
        "Correct an entry that is already logged. Pass the whole corrected set of " <>
          "claims, not only the changed one. The previous values are withdrawn but " <>
          "stay in the record — nothing is deleted, so a correction is always safe.",
      inputSchema: %{
        type: "object",
        required: ["vehicle", "entry_ref", "claims"],
        properties: %{
          vehicle: @vehicle_arg,
          entry_ref: %{
            type: "string",
            description: "The entry's id, returned by log_entry and get_timeline."
          },
          claims: @claims_arg,
          date: %{
            type: "string",
            description:
              "Only if the date itself was wrong. Left alone, the entry keeps the " <>
                "day it already had."
          }
        }
      }
    },
    %{
      name: "delete_entry",
      description:
        "Remove an entry the owner no longer wants on the car's record. The claims " <>
          "are withdrawn rather than erased, so this is reversible by logging it again.",
      inputSchema: %{
        type: "object",
        required: ["vehicle", "entry_ref"],
        properties: %{vehicle: @vehicle_arg, entry_ref: %{type: "string"}}
      }
    },
    %{
      name: "get_timeline",
      description:
        "The car's logbook, newest first — use it to answer questions like when " <>
          "the oil was last changed or what the odometer read at the last fill-up, " <>
          "and to find the entry_ref of something the owner wants corrected.",
      inputSchema: %{
        type: "object",
        required: ["vehicle"],
        properties: %{
          vehicle: @vehicle_arg,
          limit: %{type: "integer", description: "How many entries to return. Default 20."}
        }
      }
    }
  ]

  def list, do: @tools

  def call(%Scope{} = scope, "my_vehicles", _args), do: {:ok, ok(my_vehicles(scope))}

  def call(%Scope{} = scope, name, args)
      when name in ~w(log_entry amend_entry delete_entry get_timeline) do
    case fetch_vehicle(scope, args) do
      {:ok, vehicle} -> {:ok, dispatch(scope, vehicle, name, args)}
      {:error, message} -> {:ok, failure(message)}
    end
  end

  def call(_scope, _name, _args), do: {:error, :unknown_tool}

  ## The tools

  defp my_vehicles(scope) do
    case Owners.list_stewarded_vehicles(scope) do
      [] ->
        "You do not maintain any cars yet. Claim one at the car's page on Vin Santo " <>
          "by photographing its VIN plate."

      vehicles ->
        Enum.map_join(vehicles, "\n", fn vehicle ->
          "#{vehicle.public_id} — #{headline(vehicle)}"
        end)
    end
  end

  defp dispatch(scope, vehicle, "log_entry", args) do
    {claims, residual} = partition_claims(args["claims"], args["note"])

    case Owners.compose_entry(scope, vehicle, %{
           date: args["date"],
           claims: claims ++ residual,
           method: :llm_extract,
           method_meta: %{"surface" => "mcp"}
         }) do
      {:ok, entry} ->
        ok(echo(entry, vehicle, residual), %{entry_ref: entry.entry_ref})

      {:error, reason} ->
        failure(explain(reason))
    end
  end

  defp dispatch(scope, vehicle, "amend_entry", args) do
    {claims, residual} = partition_claims(args["claims"], args["note"])

    attrs =
      %{claims: claims ++ residual, method: :llm_extract, method_meta: %{"surface" => "mcp"}}
      |> maybe_put_date(args["date"])

    case Owners.amend_entry(scope, vehicle, args["entry_ref"], attrs) do
      {:ok, entry} -> ok("Corrected. " <> echo(entry, vehicle, residual))
      {:error, reason} -> failure(explain(reason))
    end
  end

  defp dispatch(scope, vehicle, "delete_entry", args) do
    case Owners.retract_entry(scope, vehicle, args["entry_ref"]) do
      {:ok, count} ->
        ok("Removed the entry (#{count} #{plural(count, "claim")}) from #{headline(vehicle)}.")

      {:error, reason} ->
        failure(explain(reason))
    end
  end

  defp dispatch(scope, vehicle, "get_timeline", args) do
    limit = args["limit"] || 20

    case Owners.timeline(scope, vehicle) do
      [] ->
        ok("#{headline(vehicle)} has no logbook entries yet.")

      entries ->
        entries
        |> Enum.take(limit)
        |> Enum.map_join("\n", &render_entry/1)
        |> ok()
    end
  end

  ## The note residual — the reason nothing is ever rejected

  defp partition_claims(claims, note) when is_list(claims) do
    {known, unknown} =
      claims
      |> Enum.map(&normalize/1)
      |> Enum.split_with(fn claim ->
        predicate = claim["predicate"]

        Vocabulary.scope_kind(predicate) != :error and
          Vocabulary.validate(predicate, claim["value"]) == :ok
      end)

    {Enum.map(known, &%{predicate: &1["predicate"], value: &1["value"]}),
     residual_note(unknown, note)}
  end

  defp partition_claims(_claims, note), do: {[], residual_note([], note)}

  # An assistant states a fact in whatever shape it heard, and the tool
  # description guides without binding — `value` carries prose, not a schema.
  # So the dialect is resolved here, before validation, and one shape reaches
  # the ledger: the same fill-up typed into the composer and dictated aloud is
  # one set of keys, comparable and readable by the same code.
  defp normalize(%{"predicate" => predicate} = claim),
    do: Map.put(claim, "value", Vocabulary.normalize(predicate, claim["value"]))

  defp normalize(claim), do: claim

  # Everything that did not fit, kept in one note rather than several: it was
  # one thing the owner said, and splitting it would invent structure the
  # vocabulary just declined to give it.
  defp residual_note([], nil), do: []
  defp residual_note([], note) when is_binary(note), do: [note_claim(note)]

  defp residual_note(unknown, note) do
    text =
      unknown
      |> Enum.map_join("; ", fn claim ->
        label = claim["predicate"] |> to_string() |> String.split(".") |> List.last()
        "#{String.replace(label, "_", " ")}: #{render_value(claim["value"])}"
      end)
      |> then(&if(note, do: note <> " (" <> &1 <> ")", else: &1))

    [note_claim(text)]
  end

  defp note_claim(text), do: %{predicate: "event.note", value: %{"text" => text}}

  ## Rendering — what the assistant reads back

  # One renderer for the car's page and for the agent, because they are saying
  # the same thing to two audiences. `Presenter` already knows that a service's
  # headline is what was done and its detail is who did it; re-deriving that
  # here would give an owner two different accounts of one entry, and the one
  # read aloud would be the worse of them.

  defp echo(entry, vehicle, residual) do
    kept = if residual == [], do: "", else: " Kept the rest as a note."

    "Logged for #{headline(vehicle)} on #{entry_date(entry)}: " <>
      "#{render_parts(entry)}.#{kept}"
  end

  defp render_entry(entry) do
    private = if entry.visibility == :private, do: " [not on the public page]", else: ""
    ref = if is_binary(entry.entry_ref), do: " (entry_ref: #{entry.entry_ref})", else: ""

    "#{Presenter.on_date(entry.date) || "Undated"} — #{render_parts(entry)}#{private}#{ref}"
  end

  defp render_parts(entry) do
    parts = Presenter.entry_parts(entry)

    case parts.details do
      [] -> parts.headline
      details -> parts.headline <> " — " <> Enum.map_join(details, ", ", & &1.value)
    end
  end

  # Only for the residual, where by definition no predicate matched and the
  # presenter has nothing to say. Values are flattened to their words rather
  # than encoded, so an owner never hears their own sentence read back as JSON.
  defp render_value(%{"text" => text}), do: text
  defp render_value(value) when is_binary(value), do: value
  defp render_value(value) when is_integer(value), do: Presenter.delimit(value)

  defp render_value(value) when is_map(value) do
    Enum.map_join(value, ", ", fn {key, inner} ->
      "#{String.replace(to_string(key), "_", " ")} #{render_value(inner)}"
    end)
  end

  defp render_value(value) when is_list(value), do: Enum.map_join(value, ", ", &render_value/1)
  defp render_value(value), do: to_string(value)

  defp headline(vehicle) do
    case Presenter.title(vehicle) do
      nil -> vehicle.identity_key
      "" -> vehicle.identity_key
      title -> title
    end
  end

  defp entry_date(%{claims: [%{scope_date: %Date{} = date} | _rest]}), do: Date.to_iso8601(date)
  defp entry_date(_entry), do: "the logged date"

  ## Results and failures

  defp ok(text, structured \\ nil) do
    base = %{content: [%{type: "text", text: text}]}
    if structured, do: Map.put(base, :structuredContent, structured), else: base
  end

  # A tool that ran and said no is not a protocol error. `isError` lets the
  # assistant tell its owner what happened and try something else.
  defp failure(message) do
    %{content: [%{type: "text", text: message}], isError: true}
  end

  defp fetch_vehicle(_scope, %{"vehicle" => public_id}) when is_binary(public_id) do
    case Registry.fetch_by_public_id(public_id) do
      {:ok, vehicle} ->
        {:ok, vehicle}

      {:error, :not_found} ->
        {:error, "No car with the id #{public_id}. Call my_vehicles to see the right ones."}
    end
  end

  defp fetch_vehicle(_scope, _args),
    do: {:error, "Which car? Pass the short id from my_vehicles."}

  defp maybe_put_date(attrs, nil), do: attrs
  defp maybe_put_date(attrs, date), do: Map.put(attrs, :date, date)

  defp plural(1, word), do: word
  defp plural(_count, word), do: word <> "s"

  defp explain(:not_stewarded),
    do: "That is not a car you maintain, so entries cannot be logged against it."

  defp explain(:entry_not_found),
    do: "No entry with that id on this car. Call get_timeline to find the right entry_ref."

  defp explain(:missing_date), do: "That entry needs a date, as YYYY-MM-DD."
  defp explain(:empty_entry), do: "Nothing to log — pass at least one claim."
  defp explain({:claim_not_live, _state}), do: "That assertion has already been ruled on."
  defp explain(reason), do: "The entry could not be recorded (#{inspect(reason)})."
end
