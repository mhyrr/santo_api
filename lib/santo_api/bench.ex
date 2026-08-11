defmodule SantoApi.Bench do
  @moduledoc """
  The authorized application boundary for the operator workbench.

  Queue state is derived from the records each subsystem already owns.
  Ratification reads claim state; contested stewardship reads possession
  challenges and active stewardships. Neither introduces a moderation row.

  The Registry remains ignorant of users. This module accepts the authenticated
  scope, rechecks the operator flag on every read and action, and hands the
  institutional Vin Santo party to the ledger as the decider.
  """

  import Ecto.Query, warn: false

  alias SantoApi.Accounts
  alias SantoApi.Accounts.Scope
  alias SantoApi.Owners
  alias SantoApi.Registry
  alias SantoApi.Registry.{Artifact, Claim, Party, Vehicle}
  alias SantoApi.Repo

  @live_claim_states [:proposed, :admitted]

  @doc """
  Owner-proposed core-car claims waiting at the operator gate, oldest first.

  `scope_kind == :factory` is the vocabulary-owned line. It includes identity,
  as-built data, and delivery provenance, while excluding the event and
  observed claims an owner self-ratifies. Filtering on the asserting party's
  kind keeps vendor, shop, Registry, and Vin Santo proposals out.
  """
  def list_pending_ratifications(%Scope{} = scope) do
    with :ok <- authorize_operator(scope) do
      queue_claims = pending_ratification_query() |> Repo.all()
      {:ok, decorate_ratifications(queue_claims)}
    end
  end

  def list_pending_ratifications(_scope), do: {:error, :not_authorized}

  @doc "The number of claims the ratification queue would return."
  def pending_ratification_count(%Scope{} = scope) do
    with :ok <- authorize_operator(scope) do
      {:ok, Repo.aggregate(pending_ratification_query(), :count)}
    end
  end

  def pending_ratification_count(_scope), do: {:error, :not_authorized}

  @doc "Ratify one eligible queue item through the existing claim transition."
  def ratify_claim(%Scope{} = scope, claim_id), do: decide(scope, claim_id, :ratify)
  def ratify_claim(_scope, _claim_id), do: {:error, :not_authorized}

  @doc "Reject one eligible queue item through the existing claim transition."
  def reject_claim(%Scope{} = scope, claim_id), do: decide(scope, claim_id, :reject)
  def reject_claim(_scope, _claim_id), do: {:error, :not_authorized}

  @doc "Contested possession challenges waiting for an operator decision."
  def list_pending_disputes(%Scope{} = scope) do
    with :ok <- authorize_operator(scope) do
      {:ok, Owners.list_pending_disputes()}
    end
  end

  def list_pending_disputes(_scope), do: {:error, :not_authorized}

  @doc "The number of contested possession challenges waiting in the bench."
  def pending_dispute_count(%Scope{} = scope) do
    with :ok <- authorize_operator(scope), do: {:ok, Owners.pending_dispute_count()}
  end

  def pending_dispute_count(_scope), do: {:error, :not_authorized}

  @doc "Resolve a stewardship dispute through the existing Owners status transitions."
  def resolve_dispute(%Scope{} = scope, challenge_id, outcome, reason)
      when outcome in [:keep_incumbent, :transfer_to_claimant] do
    with :ok <- authorize_operator(scope) do
      Owners.resolve_dispute(challenge_id, scope.user, outcome, reason)
    end
  end

  def resolve_dispute(%Scope{} = scope, _challenge_id, _outcome, _reason) do
    with :ok <- authorize_operator(scope), do: {:error, :invalid_dispute_decision}
  end

  def resolve_dispute(_scope, _challenge_id, _outcome, _reason),
    do: {:error, :not_authorized}

  defp pending_ratification_query do
    from(c in Claim,
      join: p in Party,
      on: p.id == c.asserted_by_party_id,
      join: v in Vehicle,
      on: v.id == c.vehicle_id,
      where: c.state == :proposed and c.scope_kind == :factory and p.kind == :owner,
      order_by: [asc: c.inserted_at, asc: c.id],
      select: %{claim: c, party: p, vehicle: v}
    )
  end

  defp decide(scope, claim_id, decision) do
    with :ok <- authorize_operator(scope),
         {:ok, claim} <- eligible_claim(claim_id) do
      decider = Registry.vin_santo_party()

      case decision do
        :ratify -> Registry.ratify_claim(claim.id, decider)
        :reject -> Registry.reject_claim(claim.id, decider)
      end
    end
  end

  defp eligible_claim(claim_id) do
    with {:ok, id} <- Ecto.UUID.cast(claim_id),
         %{claim: claim, party_kind: party_kind} <-
           Repo.one(
             from(c in Claim,
               join: p in Party,
               on: p.id == c.asserted_by_party_id,
               where: c.id == ^id,
               select: %{claim: c, party_kind: p.kind}
             )
           ) do
      cond do
        claim.state != :proposed -> {:error, {:not_proposed, claim.state}}
        claim.scope_kind != :factory -> {:error, :not_eligible}
        party_kind != :owner -> {:error, :not_eligible}
        true -> {:ok, claim}
      end
    else
      :error -> {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  defp authorize_operator(scope) do
    if Accounts.operator?(scope), do: :ok, else: {:error, :not_authorized}
  end

  defp decorate_ratifications([]), do: []

  defp decorate_ratifications(queue_claims) do
    entry_refs = queue_claims |> Enum.map(& &1.claim.entry_ref) |> Enum.reject(&is_nil/1)
    vehicle_ids = queue_claims |> Enum.map(& &1.claim.vehicle_id) |> Enum.uniq()
    predicates = queue_claims |> Enum.map(& &1.claim.predicate) |> Enum.uniq()

    source_claims = source_claims(entry_refs)
    competing_claims = competing_claims(vehicle_ids, predicates)

    artifact_ids =
      (Enum.map(queue_claims, & &1.claim.artifact_id) ++
         Enum.map(competing_claims, & &1.artifact_id))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    artifacts = artifacts(artifact_ids, entry_refs)
    artifacts_by_id = Map.new(artifacts, &{&1.id, &1})
    artifacts_by_entry = Enum.group_by(artifacts, & &1.entry_ref)
    source_claims_by_entry = Enum.group_by(source_claims, & &1.entry_ref)
    competitors_by_subject = Enum.group_by(competing_claims, &{&1.vehicle_id, &1.predicate})

    Enum.map(queue_claims, fn row ->
      claim = row.claim
      entry_claims = Map.get(source_claims_by_entry, claim.entry_ref, [])

      competitors =
        competitors_by_subject
        |> Map.get({claim.vehicle_id, claim.predicate}, [])
        |> Enum.reject(&(&1.claim_id == claim.id))
        |> Enum.map(&Map.put(&1, :artifact, Map.get(artifacts_by_id, &1.artifact_id)))

      %{
        id: claim.id,
        claim: claim,
        party: row.party,
        vehicle: row.vehicle,
        source_entry: source_entry(claim, entry_claims),
        evidence:
          claim_evidence(
            claim,
            artifacts_by_id,
            Map.get(artifacts_by_entry, claim.entry_ref, [])
          ),
        competing_claims: competitors
      }
    end)
  end

  defp source_claims([]), do: []

  defp source_claims(entry_refs) do
    Repo.all(
      from(c in Claim,
        join: p in Party,
        on: p.id == c.asserted_by_party_id,
        where: c.entry_ref in ^entry_refs,
        order_by: [asc: c.inserted_at, asc: c.id],
        select: %{
          claim_id: c.id,
          entry_ref: c.entry_ref,
          predicate: c.predicate,
          value: c.value,
          scope_kind: c.scope_kind,
          scope_date: c.scope_date,
          state: c.state,
          visibility: c.visibility,
          method: c.method,
          method_meta: c.method_meta,
          party: p.name,
          inserted_at: c.inserted_at
        }
      )
    )
  end

  defp competing_claims([], _predicates), do: []
  defp competing_claims(_vehicle_ids, []), do: []

  defp competing_claims(vehicle_ids, predicates) do
    Repo.all(
      from(c in Claim,
        join: p in Party,
        on: p.id == c.asserted_by_party_id,
        where:
          c.vehicle_id in ^vehicle_ids and c.predicate in ^predicates and
            c.state in ^@live_claim_states,
        order_by: [asc: c.inserted_at, asc: c.id],
        select: %{
          claim_id: c.id,
          vehicle_id: c.vehicle_id,
          predicate: c.predicate,
          value: c.value,
          state: c.state,
          party: p.name,
          party_kind: p.kind,
          method: c.method,
          artifact_id: c.artifact_id,
          inserted_at: c.inserted_at
        }
      )
    )
  end

  defp artifacts([], []), do: []

  defp artifacts(artifact_ids, entry_refs) do
    Repo.all(
      from(a in Artifact,
        where: a.id in ^artifact_ids or a.entry_ref in ^entry_refs,
        order_by: [asc: a.inserted_at, asc: a.id],
        preload: [:source_party]
      )
    )
  end

  defp source_entry(%Claim{entry_ref: nil}, _claims), do: nil

  defp source_entry(claim, claims) do
    %{
      entry_ref: claim.entry_ref,
      claims: Enum.reject(claims, &(&1.claim_id == claim.id)),
      public_link?:
        Enum.any?(claims, fn sibling ->
          sibling.state == :admitted and sibling.visibility == :public and
            sibling.scope_kind in [:event, :observed]
        end)
    }
  end

  defp claim_evidence(claim, artifacts_by_id, entry_artifacts) do
    direct =
      case Map.get(artifacts_by_id, claim.artifact_id) do
        %Artifact{} = artifact -> [%{artifact: artifact, role: :claim_basis}]
        nil -> []
      end

    entry = Enum.map(entry_artifacts, &%{artifact: &1, role: :entry_attachment})

    (direct ++ entry)
    |> Enum.uniq_by(& &1.artifact.id)
  end
end
