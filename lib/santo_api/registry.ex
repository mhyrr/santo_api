defmodule SantoApi.Registry do
  @moduledoc """
  The vehicle registry: ingest identifiers, persist identity rows, hold
  the claim record. Semantics live in docs/design/evidence_contract.md.

  Santo-derived claims enter as `:admitted` without the ratification
  gate: they are deterministic functions of the identifier itself — the
  one class of fact the registry may assert on its own authority.
  Extracted and human claims will enter as `:proposed`.

  No scope threading yet: registry data is global and there is no auth;
  scopes arrive with the first authenticated surface.
  """

  import Ecto.Query, warn: false

  alias SantoApi.Repo
  alias SantoApi.Storage

  alias SantoApi.Registry.{
    Adjudication,
    Artifact,
    Claim,
    EvidenceRequest,
    IdentityKey,
    Party,
    Vehicle,
    Vocabulary
  }

  alias SantoApi.Providers
  alias SantoApi.Providers.{Acquisition, Request}
  alias SantoApi.Terms

  def ingest(input) do
    case Santo.Identity.key(input) do
      {:ok, identity} ->
        normalized = Santo.Normalize.normalize(input)
        decode = Santo.decode(normalized)

        {:ok, vehicle} =
          Repo.transaction(fn -> upsert_vehicle(identity, normalized, decode) end)

        {:ok, vehicle}

      {:error, %Santo.Invalid{} = invalid} ->
        {:error, invalid}
    end
  end

  @doc """
  Register a trusted pre-standard chassis identity that Santo does not yet
  decode. This is deliberately atom-only: callers must choose a reviewed
  marque and era rather than turning external strings into atoms.
  """
  def register_chassis(marque, era, number)
      when marque in [:ferrari, :porsche] and is_atom(era) and is_binary(number) do
    case String.trim(number) do
      "" ->
        {:error, :invalid_chassis_number}

      normalized ->
        identity = {:chassis, marque, era, normalized}

        {:ok, vehicle} =
          Repo.transaction(fn -> upsert_vehicle(identity, normalized, nil) end)

        {:ok, vehicle}
    end
  end

  def register_chassis(_marque, _era, _number), do: {:error, :invalid_chassis_identity}

  @doc """
  Register a reviewed standard VIN that Santo can identify but cannot decode.

  This is intentionally limited to Ferrari's WMI. It gives external providers
  a stable vehicle row without manufacturing factory claims from a generic VIN.
  """
  def register_vin(:ferrari, vin) when is_binary(vin) do
    normalized = vin |> String.trim() |> String.upcase()

    if byte_size(normalized) == 17 and String.starts_with?(normalized, "ZFF") do
      {:ok, vehicle} =
        Repo.transaction(fn -> upsert_vehicle({:vin, normalized}, normalized, nil) end)

      {:ok, vehicle}
    else
      {:error, :invalid_vin_identity}
    end
  end

  def register_vin(_marque, _vin), do: {:error, :invalid_vin_identity}

  @doc """
  All vehicles, most recently ingested first. Bench-only listing — there
  is no scoping or pagination yet, matching the rest of the registry.
  """
  def list_vehicles do
    Repo.all(from(v in Vehicle, order_by: [desc: v.inserted_at]))
  end

  def fetch_vehicle(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Vehicle{} = vehicle <- Repo.get(Vehicle, uuid) do
      {:ok, vehicle}
    else
      _ -> {:error, :not_found}
    end
  end

  def list_claims(vehicle_id) do
    Repo.all(from(c in Claim, where: c.vehicle_id == ^vehicle_id, order_by: c.predicate))
  end

  def list_evidence_requests(vehicle_id) do
    Repo.all(from(r in EvidenceRequest, where: r.vehicle_id == ^vehicle_id, order_by: r.subject))
  end

  def list_artifacts(vehicle_id) do
    Repo.all(
      from(a in Artifact, where: a.vehicle_id == ^vehicle_id, order_by: [desc: a.inserted_at])
    )
  end

  def list_adjudications(vehicle_id) do
    Repo.all(
      from(a in Adjudication,
        where: a.vehicle_id == ^vehicle_id,
        order_by: [desc: a.inserted_at],
        preload: [:claim_a, :claim_b, :prevailing_claim, :decided_by_party, :evidence_request]
      )
    )
  end

  @doc """
  Store an uploaded file as an artifact: content-hashed into the artifact
  store, deduped by sha. `storage_ref` is a basename and carries no location,
  so the store can move without rewriting rows — see `SantoApi.Storage`.

  `:source_party` is the party that supplied the file; it defaults to Vin Santo
  for the bench path. Because artifacts dedupe on content, an upload of bytes we
  already hold returns the existing row and keeps its original supplier.
  """
  def create_upload_artifact(%{path: path, filename: filename, kind: kind} = attrs) do
    content = File.read!(path)
    sha = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

    case non_snapshot_artifact_by_sha(sha) do
      %Artifact{} = existing ->
        {:ok, existing}

      nil ->
        storage_ref = sha <> Path.extname(filename)
        :ok = Storage.put(storage_ref, content)

        {:ok,
         Repo.insert!(%Artifact{
           vehicle_id: attrs[:vehicle_id],
           kind: kind,
           sha256: sha,
           storage_ref: storage_ref,
           mime: attrs[:mime],
           source_url: attrs[:source_url],
           entry_ref: attrs[:entry_ref],
           source_party_id: source_party_id(attrs[:source_party]),
           acquired_at: DateTime.utc_now(),
           metadata: Map.merge(attrs[:metadata] || %{}, %{"filename" => filename})
         })}
    end
  end

  @doc """
  Persist a source pointer without copying the referenced page. Reference
  artifacts are content-deduplicated and carry their reuse posture in metadata.
  """
  def create_reference_artifact(
        %Vehicle{} = vehicle,
        %Party{} = source_party,
        %{source_url: source_url} = attrs
      )
      when is_binary(source_url) and source_url != "" do
    kind = attrs[:kind] || :reference
    metadata = attrs[:metadata] || %{}

    sha =
      artifact_sha(%{
        "vehicle" => vehicle.identity_key,
        "source_party" => source_party.name,
        "kind" => to_string(kind),
        "source_url" => source_url,
        "metadata" => metadata
      })

    case non_snapshot_artifact_by_sha(sha) do
      %Artifact{} = existing ->
        {:ok, existing}

      nil ->
        {:ok,
         Repo.insert!(%Artifact{
           vehicle_id: vehicle.id,
           source_party_id: source_party.id,
           kind: kind,
           sha256: sha,
           source_url: source_url,
           acquired_at: attrs[:acquired_at] || DateTime.utc_now(),
           metadata: metadata
         })}
    end
  end

  defp source_party_id(%Party{id: id}), do: id
  defp source_party_id(nil), do: vin_santo_party().id

  @doc """
  Show or hide a claim or artifact. Presentation only (owner_surface §6): the
  ledger row, its hash, its state, and its tier are all untouched — this governs
  who is shown the row, not whether it counts.
  """
  def set_visibility(%schema{} = row, visibility)
      when schema in [Claim, Artifact] and visibility in [:public, :private] do
    row |> Ecto.Changeset.change(visibility: visibility) |> Repo.update()
  end

  @doc """
  Mint the grouping tag every claim and artifact of one composed entry shares
  (owner_surface §2).

  UUIDv7, monotonic: entries sort chronologically by ref, including a burst
  composed inside one millisecond.
  """
  def new_entry_ref, do: Ecto.UUID.generate(version: 7, precision: :monotonic)

  @doc """
  Propose a human claim against a vehicle — the bench path. Enters
  `:proposed`; `ratify_claim/2` is the gate.
  """
  def propose_claim(%Vehicle{} = vehicle, attrs) do
    propose_claim(vehicle, vin_santo_party(), attrs)
  end

  def propose_claim(%Vehicle{} = vehicle, %Party{} = party, attrs) do
    changeset = Claim.propose_changeset(vehicle, party, attrs)

    # A caller may intentionally recover a duplicate claim inside a larger
    # transaction. The savepoint keeps PostgreSQL's constraint error from
    # aborting that surrounding transaction before the caller can query the
    # existing claim. There is nothing to take a savepoint in when the caller
    # has no transaction — the corpus scripts (TK-011).
    mode = if Repo.in_transaction?(), do: :savepoint, else: :transaction

    with {:ok, claim} <- Repo.insert(changeset, mode: mode) do
      refresh_projections(vehicle)
      {:ok, claim}
    end
  end

  @doc """
  The ratification gate: one state flip with who and when attached
  (contract §8). The deciding party defaults to Vin Santo — the bench —
  and is supplied explicitly on the owner self-ratification path.
  """
  def ratify_claim(claim_id, party \\ nil), do: flip_claim(claim_id, :admitted, party)
  def reject_claim(claim_id, party \\ nil), do: flip_claim(claim_id, :rejected, party)

  @doc """
  Resolve two live claims into the append-only casebook.

  A supersede outcome admits the prevailing claim when necessary and flips the
  other claim to `:superseded`. Coexistence admits both claims and preserves the
  disagreement. Requesting evidence leaves claim state alone and opens the
  corresponding evidence request. Every branch recomputes the materialized fact.
  """
  def adjudicate_claims(%Party{} = decider, claim_a_id, claim_b_id, attrs) do
    result =
      Repo.transaction(fn ->
        with {:ok, {claim_a, claim_b}} <- lock_claim_pair(claim_a_id, claim_b_id),
             :ok <- validate_claim_pair(claim_a, claim_b) do
          changeset = Adjudication.create_changeset(decider, claim_a, claim_b, attrs)

          with :ok <- validate_adjudication_changeset(changeset),
               :ok <- validate_adjudication_artifacts(changeset, claim_a.vehicle_id) do
            content_hash = Ecto.Changeset.get_field(changeset, :content_hash)

            case Repo.get_by(Adjudication, content_hash: content_hash) do
              %Adjudication{} = existing ->
                existing

              nil ->
                case validate_live_claims(claim_a, claim_b) do
                  :ok ->
                    changeset = prepare_adjudication(changeset, claim_a)
                    apply_adjudication_outcome!(changeset, claim_a, claim_b)
                    adjudication = Repo.insert!(changeset)
                    refresh_projections(Repo.get!(Vehicle, claim_a.vehicle_id))
                    adjudication

                  {:error, reason} ->
                    Repo.rollback(reason)
                end
            end
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, adjudication} -> {:ok, adjudication}
      {:error, reason} -> {:error, reason}
    end
  end

  defp flip_claim(claim_id, new_state, party) do
    decider = party || vin_santo_party()

    result =
      Repo.transaction(fn ->
        case Repo.get(Claim, claim_id) do
          nil ->
            Repo.rollback(:not_found)

          %Claim{state: :proposed} = claim ->
            claim =
              claim
              |> Ecto.Changeset.change(
                state: new_state,
                ratified_by_party_id: decider.id,
                ratified_at: DateTime.utc_now()
              )
              |> Repo.update!()

            {:ok, vehicle} = fetch_vehicle(claim.vehicle_id)
            refresh_projections(vehicle)
            claim

          %Claim{state: state} ->
            Repo.rollback({:not_proposed, state})
        end
      end)

    case result do
      {:ok, claim} -> {:ok, claim}
      {:error, reason} -> {:error, reason}
    end
  end

  defp lock_claim_pair(claim_a_id, claim_b_id) do
    with {:ok, claim_a_uuid} <- Ecto.UUID.cast(claim_a_id),
         {:ok, claim_b_uuid} <- Ecto.UUID.cast(claim_b_id) do
      claims =
        Repo.all(
          from(c in Claim,
            where: c.id in ^[claim_a_uuid, claim_b_uuid],
            order_by: c.id,
            lock: "FOR UPDATE"
          )
        )

      by_id = Map.new(claims, &{&1.id, &1})

      case {Map.get(by_id, claim_a_uuid), Map.get(by_id, claim_b_uuid)} do
        {%Claim{} = claim_a, %Claim{} = claim_b} -> {:ok, {claim_a, claim_b}}
        _ -> {:error, :not_found}
      end
    else
      :error -> {:error, :not_found}
    end
  end

  defp validate_claim_pair(%Claim{id: id}, %Claim{id: id}), do: {:error, :same_claim}

  defp validate_claim_pair(%Claim{} = claim_a, %Claim{} = claim_b) do
    cond do
      claim_a.vehicle_id != claim_b.vehicle_id ->
        {:error, :different_vehicles}

      claim_a.predicate != claim_b.predicate ->
        {:error, :different_predicates}

      claim_a.scope_kind != claim_b.scope_kind ->
        {:error, :different_scopes}

      claim_a.scope_kind == :event ->
        {:error, :events_do_not_conflict}

      claim_a.scope_kind == :observed and claim_a.scope_date != claim_b.scope_date ->
        {:error, :non_overlapping_observations}

      true ->
        :ok
    end
  end

  defp validate_adjudication_changeset(%Ecto.Changeset{valid?: true}), do: :ok
  defp validate_adjudication_changeset(%Ecto.Changeset{} = changeset), do: {:error, changeset}

  defp validate_adjudication_artifacts(changeset, vehicle_id) do
    artifact_ids = Ecto.Changeset.get_field(changeset, :evidence_artifact_ids, [])

    count =
      Repo.aggregate(
        from(a in Artifact, where: a.id in ^artifact_ids and a.vehicle_id == ^vehicle_id),
        :count
      )

    if count == length(Enum.uniq(artifact_ids)),
      do: :ok,
      else: {:error, :invalid_evidence_artifacts}
  end

  defp validate_live_claims(%Claim{state: state_a}, %Claim{state: state_b})
       when state_a in [:proposed, :admitted] and state_b in [:proposed, :admitted],
       do: :ok

  defp validate_live_claims(%Claim{state: state_a}, %Claim{state: state_b}),
    do: {:error, {:claims_not_live, state_a, state_b}}

  defp prepare_adjudication(changeset, claim) do
    case Ecto.Changeset.get_field(changeset, :outcome) do
      :request_evidence ->
        classes = Ecto.Changeset.get_field(changeset, :requested_evidence_classes)

        request =
          Repo.one(
            from(r in EvidenceRequest,
              where:
                r.vehicle_id == ^claim.vehicle_id and r.subject == ^claim.predicate and
                  r.status == :open
            )
          ) ||
            Repo.insert!(%EvidenceRequest{
              vehicle_id: claim.vehicle_id,
              subject: claim.predicate,
              evidence_classes: classes
            })

        Adjudication.with_evidence_request(changeset, request)

      _ ->
        changeset
    end
  end

  defp apply_adjudication_outcome!(changeset, claim_a, claim_b) do
    case Ecto.Changeset.get_field(changeset, :outcome) do
      :supersede ->
        prevailing_id = Ecto.Changeset.get_field(changeset, :prevailing_claim_id)

        case {claim_a.id == prevailing_id, claim_b.id == prevailing_id} do
          {true, false} ->
            set_claim_state!(claim_a, :admitted)
            set_claim_state!(claim_b, :superseded)

          {false, true} ->
            set_claim_state!(claim_b, :admitted)
            set_claim_state!(claim_a, :superseded)

          _ ->
            Repo.rollback(:prevailing_claim_not_in_pair)
        end

      :coexist_with_note ->
        set_claim_state!(claim_a, :admitted)
        set_claim_state!(claim_b, :admitted)

      :request_evidence ->
        :ok
    end
  end

  defp set_claim_state!(%Claim{state: state}, state), do: :ok

  defp set_claim_state!(%Claim{} = claim, state) do
    claim |> Ecto.Changeset.change(state: state) |> Repo.update!()
    :ok
  end

  def satisfy_evidence_request(request_id, refs) do
    case Repo.get(EvidenceRequest, request_id) do
      nil ->
        {:error, :not_found}

      %EvidenceRequest{status: :open} = request ->
        request
        |> Ecto.Changeset.change(
          status: :satisfied,
          satisfied_by_claim_id: refs[:claim_id],
          satisfied_by_artifact_id: refs[:artifact_id]
        )
        |> Repo.update()

      %EvidenceRequest{} ->
        {:error, :not_open}
    end
  end

  def vin_santo_party, do: ensure_party("Vin Santo", :vin_santo)

  def ensure_party(name, kind) do
    Repo.get_by(Party, name: name, kind: kind) ||
      Repo.insert!(%Party{name: name, kind: kind})
  end

  @doc """
  Acquire evidence for a vehicle through a registered provider and persist the
  immutable retrieval. The request identity must name the supplied vehicle.
  """
  def acquire(%Vehicle{} = vehicle, provider_id, %Request{} = request) do
    if IdentityKey.serialize(request.identity) == vehicle.identity_key do
      with {:ok, %Acquisition{} = acquisition} <- Providers.acquire(provider_id, request) do
        record_acquisition(vehicle, acquisition)
      end
    else
      {:error, :identity_mismatch}
    end
  end

  @doc """
  Persist one already-completed provider acquisition. Re-persisting the same
  acquisition id is idempotent; a fresh retrieval has a fresh id even when its
  payload bytes are unchanged.
  """
  def record_acquisition(%Vehicle{} = vehicle, %Acquisition{} = acquisition) do
    with {:ok, _uuid} <- Ecto.UUID.cast(acquisition.acquisition_id) do
      Repo.transaction(fn -> persist_acquisition(vehicle, acquisition) end)
    else
      :error -> {:error, :invalid_acquisition_id}
    end
  end

  @doc """
  Fetch a vPIC snapshot for a VIN-identified vehicle, store it as an
  api_snapshot artifact, and emit its facts as `:proposed` claims — the
  ratification gate applies to external evidence. Pre-1981 chassis
  identities are outside vPIC's scope.
  """
  def ingest_vpic(%Vehicle{identity_kind: :vin} = vehicle) do
    vin = String.trim_leading(vehicle.identity_key, "vin:")

    with {:ok, request} <- Request.new(:generic_specifications, {:vin, vin}) do
      acquire(vehicle, :nhtsa_vpic, request)
    end
  end

  def ingest_vpic(%Vehicle{}), do: {:error, :unsupported_identity}

  @doc """
  The oracle pattern as a query: group live claims by predicate and
  label each `:agreement`, `:conflict`, or `:single_source`. Derived,
  never stored — nothing overwrites anything.
  """
  def claim_comparison(vehicle_id) do
    vehicle_id
    |> live_claim_entries()
    |> Enum.group_by(& &1.predicate)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {predicate, entries} ->
      %{predicate: predicate, status: comparison_status(predicate, entries), claims: entries}
    end)
  end

  defp live_claim_entries(vehicle_id) do
    Repo.all(
      from(c in Claim,
        join: p in Party,
        on: p.id == c.asserted_by_party_id,
        where: c.vehicle_id == ^vehicle_id and c.state in [:admitted, :proposed],
        order_by: [c.predicate, p.name],
        select: %{
          claim_id: c.id,
          predicate: c.predicate,
          value: c.value,
          state: c.state,
          method: c.method,
          party: p.name,
          party_id: p.id,
          artifact_id: c.artifact_id,
          scope_kind: c.scope_kind,
          scope_date: c.scope_date,
          inserted_at: c.inserted_at
        }
      )
    )
  end

  @doc """
  Recompute both derived maps in one write.

  `facts` is the one-row view of the factory record (contract §8):
  factory/provenance claims flatten into it, event-scoped claims stay in the
  logbook. `current_state` is what the car is now (owner_surface §2b), folded
  from the same ledger but never from `facts`.

  Runs inside every claim-writing path; call it after any out-of-band claim
  state change. Both maps are replayable by construction — drop them and this
  rebuilds them identically.
  """
  def refresh_projections(%Vehicle{} = vehicle) do
    entries = live_claim_entries(vehicle.id)

    vehicle
    |> Ecto.Changeset.change(
      facts: materialized_facts(entries),
      current_state: folded_current_state(entries)
    )
    |> Repo.update!()
  end

  defp materialized_facts(entries) do
    entries
    |> Enum.filter(&(&1.scope_kind == :factory))
    |> Enum.group_by(& &1.predicate)
    |> Map.new(fn {predicate, group} -> {predicate, fact(predicate, group)} end)
  end

  # The fold (owner_surface §2b). Admitted claims only: a proposed entry must
  # never mutate public state, or the §8 confirm gate stops meaning anything.
  # Latest scope date wins, ties to latest insertion — deliberately the inverse
  # of facts, which ties to earliest. Facts asks what was true at birth; this
  # asks what is true now, so recency winning is the semantics.
  defp folded_current_state(entries) do
    entries
    |> Enum.filter(&(&1.state == :admitted))
    |> Enum.flat_map(&trait_candidates/1)
    |> Enum.group_by(& &1.predicate)
    |> Map.new(fn {predicate, candidates} ->
      {predicate, candidates |> Enum.max_by(&recency/1) |> trait_entry()}
    end)
  end

  # The two inputs §2b names: an observation states a trait directly; an event's
  # `sets` deltas state one as a consequence of what happened. An event without
  # deltas stays timeline-only.
  defp trait_candidates(%{scope_kind: :observed} = entry),
    do: [candidate(entry, entry.predicate, entry.value, "observed")]

  defp trait_candidates(%{scope_kind: :event, value: %{"sets" => sets}} = entry)
       when is_list(sets) do
    for %{"predicate" => predicate, "value" => value} <- sets do
      candidate(entry, predicate, value, "event")
    end
  end

  defp trait_candidates(_entry), do: []

  defp candidate(entry, predicate, value, source) do
    %{
      predicate: predicate,
      value: value,
      source: source,
      claim_id: entry.claim_id,
      scope_date: entry.scope_date,
      inserted_at: entry.inserted_at
    }
  end

  # An undated claim cannot out-rank a dated one: "we don't know when" loses.
  defp recency(%{scope_date: nil} = candidate), do: {{0, 0, 0}, insertion(candidate)}
  defp recency(candidate), do: {Date.to_erl(candidate.scope_date), insertion(candidate)}

  defp insertion(candidate), do: DateTime.to_unix(candidate.inserted_at, :microsecond)

  defp trait_entry(candidate) do
    %{
      "value" => candidate.value,
      "as_of" => candidate.scope_date && Date.to_iso8601(candidate.scope_date),
      "source" => candidate.source,
      "claim_id" => candidate.claim_id
    }
  end

  defp fact(predicate, entries) do
    best = best_fact_entry(predicate, entries)

    status =
      case comparison_status(predicate, entries) do
        :conflict -> "conflicted"
        _no_disagreement when best.state == :admitted -> "verified"
        _no_disagreement -> "unverified"
      end

    %{"value" => best.value, "status" => status}
  end

  defp state_rank(:admitted), do: 0
  defp state_rank(:proposed), do: 1

  defp best_fact_entry(predicate, entries) do
    best_state_rank = entries |> Enum.map(&state_rank(&1.state)) |> Enum.min()
    state_entries = Enum.filter(entries, &(state_rank(&1.state) == best_state_rank))
    earliest = Enum.min_by(state_entries, &DateTime.to_unix(&1.inserted_at, :microsecond))

    state_entries
    |> Enum.filter(&Vocabulary.equivalent?(predicate, earliest.value, &1.value))
    |> Enum.min_by(fn entry ->
      {-value_richness(entry.value), DateTime.to_unix(entry.inserted_at, :microsecond)}
    end)
  end

  defp value_richness(value) when is_map(value) do
    Enum.count(value, fn {_key, field} -> !is_nil(field) end)
  end

  defp value_richness(_value), do: 1

  defp comparison_status(_predicate, [%{scope_kind: :event} | _entries]), do: :history

  defp comparison_status(predicate, [%{scope_kind: :observed} | _entries] = entries) do
    scope_groups = Enum.group_by(entries, & &1.scope_date)

    statuses =
      Enum.map(scope_groups, fn {_date, claims} -> value_comparison_status(predicate, claims) end)

    cond do
      :conflict in statuses -> :conflict
      map_size(scope_groups) > 1 -> :history
      true -> hd(statuses)
    end
  end

  defp comparison_status(predicate, entries), do: value_comparison_status(predicate, entries)

  defp value_comparison_status(predicate, entries) do
    [first | rest] = entries

    cond do
      length(Enum.uniq_by(entries, &comparison_source/1)) < 2 ->
        :single_source

      Enum.all?(rest, &Vocabulary.equivalent?(predicate, first.value, &1.value)) ->
        :agreement

      true ->
        :conflict
    end
  end

  defp comparison_source(%{artifact_id: artifact_id}) when not is_nil(artifact_id),
    do: {:artifact, artifact_id}

  defp comparison_source(%{party_id: party_id}), do: {:party, party_id}

  defp persist_acquisition(vehicle, %Acquisition{} = acquisition) do
    {:ok, provider} = Providers.provider(acquisition.provider)
    party = ensure_party(provider.descriptor().name, :vendor)
    sha = :crypto.hash(:sha256, Jason.encode!(acquisition.payload)) |> Base.encode16(case: :lower)

    artifact =
      case Repo.get_by(Artifact, acquisition_id: acquisition.acquisition_id) do
        %Artifact{vehicle_id: vehicle_id} = existing when vehicle_id == vehicle.id ->
          existing

        %Artifact{} ->
          Repo.rollback(:acquisition_identity_mismatch)

        nil ->
          Repo.insert!(%Artifact{
            acquisition_id: acquisition.acquisition_id,
            vehicle_id: vehicle.id,
            kind: :api_snapshot,
            sha256: sha,
            payload: acquisition.payload,
            source_url: acquisition.source_url,
            source_party_id: party.id,
            mime: acquisition.media_type,
            acquired_at: acquisition.acquired_at,
            metadata: %{
              "provider" => to_string(acquisition.provider),
              "capability" => to_string(acquisition.capability),
              "coverage" => to_string(acquisition.coverage),
              "rights_profile" => acquisition.rights_profile,
              "diagnostics" => acquisition.diagnostics
            }
          })
      end

    for {predicate, value} <- acquisition_facts(acquisition) do
      :ok = Vocabulary.validate(predicate, value)
      scope_kind = Vocabulary.scope_kind(predicate)

      Repo.insert!(
        %Claim{
          vehicle_id: vehicle.id,
          asserted_by_party_id: party.id,
          artifact_id: artifact.id,
          predicate: predicate,
          value: value,
          scope_kind: scope_kind,
          state: :proposed,
          method: :structured_api,
          method_meta: %{"vendor" => party.name},
          content_hash:
            Claim.hash(
              vehicle.identity_key,
              predicate,
              value,
              scope_kind,
              nil,
              :structured_api,
              party.name
            )
        },
        on_conflict: :nothing,
        conflict_target: [:vehicle_id, :content_hash]
      )
    end

    refresh_projections(vehicle)
    artifact
  end

  # Per-provider claim interpretation stays Registry-side: providers own
  # transport, the registry owns what becomes a claim.
  defp acquisition_facts(%Acquisition{provider: :nhtsa_vpic, payload: payload}),
    do: Providers.Vpic.facts(payload)

  defp upsert_vehicle(identity, input, decode) do
    key = IdentityKey.serialize(identity)

    case Repo.get_by(Vehicle, identity_key: key) do
      %Vehicle{} = existing -> existing
      nil -> create_vehicle(identity, key, input, decode)
    end
  end

  defp create_vehicle(identity, key, input, decode) do
    vehicle =
      Repo.insert!(%Vehicle{
        identity_kind: IdentityKey.kind(identity),
        identity_key: key,
        candidates: IdentityKey.candidates(identity),
        input: input,
        decode_snapshot: snapshot(decode),
        santo_version: if(is_nil(decode), do: nil, else: santo_version())
      })

    emit_claims(vehicle, decode)
    open_evidence_requests(vehicle, identity)
    refresh_projections(vehicle)
  end

  defp snapshot({:ok, decoded}), do: Terms.sanitize(decoded)
  defp snapshot({:ambiguous, readings}), do: %{"ambiguous" => Terms.sanitize(readings)}
  defp snapshot(nil), do: nil

  defp santo_version, do: to_string(Application.spec(:santo, :vsn))

  # Claims come only from unambiguous decodes — the registry never guesses.
  defp emit_claims(vehicle, {:ok, decoded}) do
    party = vin_santo_party()

    for {predicate, value} <- decode_facts(decoded) do
      :ok = Vocabulary.validate(predicate, value)
      scope_kind = Vocabulary.scope_kind(predicate)

      Repo.insert!(%Claim{
        vehicle_id: vehicle.id,
        asserted_by_party_id: party.id,
        predicate: predicate,
        value: value,
        scope_kind: scope_kind,
        state: :admitted,
        method: :santo,
        method_meta: %{"santo_version" => santo_version()},
        content_hash:
          Claim.hash(vehicle.identity_key, predicate, value, scope_kind, nil, :santo, party.name)
      })
    end

    :ok
  end

  defp emit_claims(_vehicle, _decode), do: :ok

  defp decode_facts(%Santo.Decoded{} = decoded) do
    [
      {"identity.marque", maybe_string(decoded.marque)},
      {"identity.model", model_value(decoded.model)},
      {"identity.model_year", single_year(decoded.years)},
      {"identity.market", market_value(decoded.market)},
      {"build.plant", decoded.attributes[:plant]},
      {"build.variant", maybe_string(decoded.attributes[:variant])}
    ]
    |> Enum.reject(fn {_predicate, value} -> is_nil(value) end)
  end

  defp maybe_string(nil), do: nil
  defp maybe_string(value), do: to_string(value)

  defp model_value({code, label}), do: %{"code" => to_string(code), "label" => label}
  defp model_value(nil), do: nil

  defp single_year([year]), do: year
  defp single_year(_years), do: nil

  defp market_value(market) when market in [:us, :row], do: to_string(market)
  defp market_value(_market), do: nil

  # A disputed row gets exactly one request — resolve identity first;
  # subordinate gaps only make sense once we know which car it is.
  defp open_evidence_requests(vehicle, {:disputed, _candidates, evidence}) do
    Repo.insert!(%EvidenceRequest{
      vehicle_id: vehicle.id,
      subject: "identity",
      evidence_classes: Enum.map(evidence, &to_string/1)
    })

    :ok
  end

  defp open_evidence_requests(_vehicle, _identity), do: :ok

  defp non_snapshot_artifact_by_sha(sha) do
    Repo.one(
      from(a in Artifact,
        where: a.sha256 == ^sha and a.kind != :api_snapshot,
        limit: 1
      )
    )
  end

  defp artifact_sha(payload) do
    :crypto.hash(:sha256, Jason.encode!(payload))
    |> Base.encode16(case: :lower)
  end
end
