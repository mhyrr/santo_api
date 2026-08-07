defmodule SantoApi.Origination do
  @moduledoc """
  The front door for a car in no registry at all (owner_surface §7b).

  One submit creates everything in one transaction — the user, the party,
  the car, the claims, the stewardship — and the owner lands on a real page
  immediately (§7b.1 decision 6). The user exists before the email is sent,
  so the magic-link click publishes rather than unlocks: public rendering
  gates on `user.confirmed_at` through the stewardship join, and no
  visibility flips after the fact.

  Persistence splits by path, on principle (§7b.1 decision 5): a VIN lookup
  persists immediately — its decoded facts exist independent of who typed
  them — and never comes through here. A sentence persists only once there
  is an account behind it, because its entire content is one unidentified
  person's word. This module is the sentence path, which also disposes of
  the junk-row problem: no account, no row.

  The typed sentence is stored as the artifact and attached to every
  extracted claim, so a better extractor can re-run against the same bytes
  and the ledger records what the claims were read from.

  The one deliberate doctrine deviation lives here (§7b.1 decision 2, §3):
  owner identity claims self-ratify on an `:asserted` car. Self-declared
  identity on an originated car has no counterparty and no decode to
  disagree with, and a car whose own name is `:proposed` has no name.
  Resolution audits the shortcut automatically — when the VIN lands, the
  decode arrives `:admitted` and `claim_comparison/1` surfaces any
  disagreement with both sources shown. §3's gate still governs every other
  factory claim and every claim on a `:vin` car.
  """

  alias SantoApi.Accounts
  alias SantoApi.Owners
  alias SantoApi.Registry
  alias SantoApi.Registry.Claim
  alias SantoApi.Repo

  @doc """
  Originate a car from a sentence, creating the account behind it.

  ## Attributes

    * `:email`, `:handle` — the registration (§9.1: the handle is reserved
      here, permanent, and becomes the party name)
    * `:sentence` — the typed sentence; becomes the row's input and the
      stored artifact
    * `:claims` — `[%{predicate:, value:}]`, the (possibly owner-edited)
      read-back lines; may be empty — a car nobody could describe still
      originates, and the page invites the rest
    * `:method` — `:llm_extract` when the extractor read the lines,
      `:human` when the owner typed them into an empty read-back

  `magic_link_url_fun` builds the login URL for the email, sent after the
  transaction commits.

  Returns `{:ok, %{user:, party:, vehicle:}}` or `{:error, step, reason}` —
  a failed registration rolls the whole thing back: no account, no row.
  """
  def originate(attrs, magic_link_url_fun) when is_function(magic_link_url_fun, 1) do
    result =
      Repo.transaction(fn ->
        with {:ok, user} <- register(attrs) do
          build_record(user, attrs, [])
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, %{user: user} = created} ->
        {:ok, _email} = Accounts.deliver_login_instructions(user, magic_link_url_fun)
        {:ok, created}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Originate another car for an account that already exists.

  Collectors have lots of cars: stewardship is per `(user, vehicle)`, so
  this is the same front door minus the registration screen — the car, the
  claims, and the stewardship land in one transaction, attributed to the
  party the user already has (or minted from their §9.1 reservation at this
  first assertive act). No email is sent and nothing waits: a signed-in
  user already confirmed theirs, so the page is public the moment this
  returns.

  `attrs[:handle]` exists only for legacy accounts that predate the
  reservation — the flow asks them once, the same permanent question
  registration now asks everyone else.
  """
  def originate_for(%SantoApi.Accounts.User{} = user, attrs) do
    grant_opts =
      case attrs[:handle] do
        nil -> []
        handle -> [handle: handle]
      end

    case Repo.transaction(fn -> build_record(user, attrs, grant_opts) end) do
      {:ok, created} -> {:ok, created}
      {:error, reason} -> {:error, reason}
    end
  end

  defp register(attrs) do
    Accounts.register_user(%{email: attrs[:email], handle: attrs[:handle]})
  end

  # The shared core, always inside a transaction: the car, the stewardship,
  # the sentence artifact, the claims, and the opening tick — or nothing.
  defp build_record(user, attrs, grant_opts) do
    sentence = String.trim(attrs[:sentence] || "")
    method = Map.get(attrs, :method, :llm_extract)

    with {:ok, vehicle} <- Registry.originate(sentence),
         {:ok, _stewardship} <- Owners.grant_stewardship(user, vehicle, grant_opts),
         party = Owners.party(user),
         {:ok, artifact} <- store_sentence(vehicle, party, sentence) do
      entry_ref = write_claims!(vehicle, party, artifact, Map.get(attrs, :claims, []), method)
      write_origination_entry!(vehicle, party, artifact, sentence, entry_ref)

      {:ok, refreshed} = Registry.fetch_vehicle(vehicle.id)
      %{user: user, party: party, vehicle: refreshed}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  # The claimant's own words, held as bytes so a better extractor can re-run
  # against them later. The owner supplied it, so the owner's party is the
  # source — attributing it to Vin Santo would say the registry wrote it.
  defp store_sentence(vehicle, party, sentence) do
    path =
      Path.join(
        System.tmp_dir!(),
        "origination-#{System.unique_integer([:positive])}.txt"
      )

    File.write!(path, sentence)

    try do
      Registry.create_upload_artifact(%{
        vehicle_id: vehicle.id,
        path: path,
        filename: "origination.txt",
        mime: "text/plain",
        kind: :document,
        source_party: party,
        metadata: %{"purpose" => "origination_sentence"}
      })
    after
      File.rm(path)
    end
  end

  # Factory claims are timeless and stand alone; event- and observed-scope
  # claims share one entry_ref so the page shows one origination tick, not a
  # scatter of lines (§7b.3 screen 4).
  defp write_claims!(vehicle, party, artifact, claims, method) do
    entry_ref = Registry.new_entry_ref()
    today = Date.utc_today()

    opts = [
      method: method,
      method_meta: %{"surface" => "origination"}
    ]

    for %{predicate: predicate, value: value} <- claims do
      attrs =
        case SantoApi.Registry.Vocabulary.scope_kind(predicate) do
          :factory ->
            %{"predicate" => predicate, "value" => value, "artifact_id" => artifact.id}

          _dated ->
            %{
              "predicate" => predicate,
              "value" => value,
              "artifact_id" => artifact.id,
              "scope_date" => today,
              "entry_ref" => entry_ref
            }
        end

      vehicle
      |> propose!(party, attrs, opts)
      |> maybe_self_ratify!(vehicle, party)
    end

    entry_ref
  end

  # The build thread's opening post: the origination is itself an entry
  # (§7b.3 screen 4), carrying the sentence in the owner's own words. Typed,
  # not extracted, so its method is :human whatever read the other lines. It
  # shares the extracted claims' entry_ref — the page shows one tick, and the
  # odometer reads as a detail of the record starting rather than a second
  # line.
  defp write_origination_entry!(vehicle, party, artifact, sentence, entry_ref) do
    vehicle
    |> propose!(
      party,
      %{
        "predicate" => "event.origination",
        "value" => %{"text" => sentence},
        "artifact_id" => artifact.id,
        "scope_date" => Date.utc_today(),
        "entry_ref" => entry_ref
      },
      method: :human
    )
    |> maybe_self_ratify!(vehicle, party)
  end

  defp propose!(vehicle, party, attrs, opts) do
    case Registry.propose_claim(vehicle, party, attrs, opts) do
      {:ok, claim} -> claim
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  # The §3 scope split, plus origination's one scoped deviation: identity
  # claims self-ratify because the car is `:asserted` — resolution audits
  # them. Any other factory- or provenance-scope line an extractor ever
  # emits stays `:proposed` and waits at the gate.
  defp maybe_self_ratify!(%Claim{scope_kind: kind} = claim, _vehicle, party)
       when kind in [:event, :observed] do
    ratify!(claim, party)
  end

  defp maybe_self_ratify!(
         %Claim{scope_kind: :factory, predicate: "identity." <> _rest} = claim,
         %{identity_kind: :asserted},
         party
       ) do
    ratify!(claim, party)
  end

  defp maybe_self_ratify!(%Claim{} = claim, _vehicle, _party), do: claim

  defp ratify!(claim, party) do
    case Registry.ratify_claim(claim.id, party) do
      {:ok, ratified} -> ratified
      {:error, reason} -> Repo.rollback(reason)
    end
  end
end
