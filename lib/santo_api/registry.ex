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

  alias SantoApi.Registry.{
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
  All vehicles, most recently ingested first. Bench-only listing — there
  is no scoping or pagination yet, matching the rest of the registry.
  """
  def list_vehicles do
    Repo.all(from v in Vehicle, order_by: [desc: v.inserted_at])
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
    Repo.all(from c in Claim, where: c.vehicle_id == ^vehicle_id, order_by: c.predicate)
  end

  def list_evidence_requests(vehicle_id) do
    Repo.all(from r in EvidenceRequest, where: r.vehicle_id == ^vehicle_id, order_by: r.subject)
  end

  def list_artifacts(vehicle_id) do
    Repo.all(
      from a in Artifact, where: a.vehicle_id == ^vehicle_id, order_by: [desc: a.inserted_at]
    )
  end

  @doc """
  Store an uploaded file as an artifact: content-hashed into the uploads
  dir, deduped by sha. `storage_ref` is the basename inside the
  configured uploads dir, so the store can move without rewriting rows.
  """
  def create_upload_artifact(%{path: path, filename: filename, kind: kind} = attrs) do
    content = File.read!(path)
    sha = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

    case Repo.get_by(Artifact, sha256: sha) do
      %Artifact{} = existing ->
        {:ok, existing}

      nil ->
        storage_ref = sha <> Path.extname(filename)
        dir = uploads_dir()
        File.mkdir_p!(dir)
        File.cp!(path, Path.join(dir, storage_ref))

        {:ok,
         Repo.insert!(%Artifact{
           vehicle_id: attrs[:vehicle_id],
           kind: kind,
           sha256: sha,
           storage_ref: storage_ref,
           mime: attrs[:mime],
           source_url: attrs[:source_url],
           source_party_id: vin_santo_party().id,
           acquired_at: DateTime.utc_now(),
           metadata: Map.merge(attrs[:metadata] || %{}, %{"filename" => filename})
         })}
    end
  end

  defp uploads_dir do
    Application.get_env(
      :santo_api,
      :uploads_dir,
      Path.join(to_string(:code.priv_dir(:santo_api)), "uploads")
    )
  end

  @doc """
  Propose a human claim against a vehicle — the bench path. Enters
  `:proposed`; `ratify_claim/1` is the gate.
  """
  def propose_claim(%Vehicle{} = vehicle, attrs) do
    changeset = Claim.propose_changeset(vehicle, vin_santo_party(), attrs)

    with {:ok, claim} <- Repo.insert(changeset) do
      refresh_facts(vehicle)
      {:ok, claim}
    end
  end

  def ratify_claim(claim_id), do: flip_claim(claim_id, :admitted)
  def reject_claim(claim_id), do: flip_claim(claim_id, :rejected)

  defp flip_claim(claim_id, new_state) do
    result =
      Repo.transaction(fn ->
        case Repo.get(Claim, claim_id) do
          nil ->
            Repo.rollback(:not_found)

          %Claim{state: :proposed} = claim ->
            claim = claim |> Ecto.Changeset.change(state: new_state) |> Repo.update!()
            {:ok, vehicle} = fetch_vehicle(claim.vehicle_id)
            refresh_facts(vehicle)
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
  Fetch a vPIC snapshot for a VIN-identified vehicle, store it as an
  api_snapshot artifact, and emit its facts as `:proposed` claims — the
  ratification gate applies to external evidence. Pre-1981 chassis
  identities are outside vPIC's scope.
  """
  def ingest_vpic(%Vehicle{identity_kind: :vin} = vehicle) do
    vin = String.trim_leading(vehicle.identity_key, "vin:")

    with {:ok, request} <- Request.new(:generic_specifications, {:vin, vin}),
         {:ok, %Acquisition{} = acquisition} <- Providers.acquire(:nhtsa_vpic, request) do
      Repo.transaction(fn -> persist_acquisition(vehicle, acquisition) end)
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
      from c in Claim,
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
          scope_kind: c.scope_kind,
          inserted_at: c.inserted_at
        }
    )
  end

  @doc """
  Recompute the one-row view (contract §8): factory/provenance claims
  flatten into `vehicle.facts`; event-scoped claims stay in the logbook.
  Runs inside every claim-writing path; call it after any out-of-band
  claim state change.
  """
  def refresh_facts(%Vehicle{} = vehicle) do
    facts =
      vehicle.id
      |> live_claim_entries()
      |> Enum.filter(&(&1.scope_kind == :factory))
      |> Enum.group_by(& &1.predicate)
      |> Map.new(fn {predicate, entries} -> {predicate, fact(predicate, entries)} end)

    vehicle |> Ecto.Changeset.change(facts: facts) |> Repo.update!()
  end

  defp fact(predicate, entries) do
    best =
      Enum.min_by(
        entries,
        &{state_rank(&1.state), DateTime.to_unix(&1.inserted_at, :microsecond)}
      )

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

  defp comparison_status(predicate, entries) do
    [first | rest] = entries

    cond do
      length(Enum.uniq_by(entries, & &1.party)) < 2 ->
        :single_source

      Enum.all?(rest, &Vocabulary.equivalent?(predicate, first.value, &1.value)) ->
        :agreement

      true ->
        :conflict
    end
  end

  defp persist_acquisition(vehicle, %Acquisition{} = acquisition) do
    {:ok, provider} = Providers.provider(acquisition.provider)
    party = ensure_party(provider.descriptor().name, :vendor)
    sha = :crypto.hash(:sha256, Jason.encode!(acquisition.payload)) |> Base.encode16(case: :lower)

    artifact =
      Repo.get_by(Artifact, sha256: sha) ||
        Repo.insert!(%Artifact{
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

    refresh_facts(vehicle)
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
        santo_version: santo_version()
      })

    emit_claims(vehicle, decode)
    open_evidence_requests(vehicle, identity)
    refresh_facts(vehicle)
  end

  defp snapshot({:ok, decoded}), do: Terms.sanitize(decoded)
  defp snapshot({:ambiguous, readings}), do: %{"ambiguous" => Terms.sanitize(readings)}

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
end
