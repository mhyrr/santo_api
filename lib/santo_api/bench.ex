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
  alias SantoApi.Accounts.{AccessDecision, Scope, User, UserToken}
  alias SantoApi.Events.EventParticipation
  alias SantoApi.Owners
  alias SantoApi.Owners.{Stewardship, VehiclePhoto}
  alias SantoApi.Registry
  alias SantoApi.Registry.{Artifact, Claim, Party, Vehicle}
  alias SantoApi.Repo
  alias SantoApi.Social.ContentReport

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

  @doc """
  Find the exact account an operator named by email or handle.

  The result carries both sides of the split deliberately: the credential row
  and its permanent public Party, followed by the independent active
  Stewardships and append-only account-access decisions.
  """
  def find_access_account(%Scope{} = scope, query) when is_binary(query) do
    with :ok <- authorize_operator(scope),
         {:ok, term} <- normalize_account_query(query) do
      account =
        Repo.one(
          from(u in User,
            left_join: p in assoc(u, :party),
            where: u.email == ^term or u.handle == ^String.downcase(term),
            select: %{user: u, party: p}
          )
        )

      {:ok, decorate_access_account(account)}
    end
  end

  def find_access_account(%Scope{} = scope, _query) do
    with :ok <- authorize_operator(scope), do: {:error, :query_required}
  end

  def find_access_account(_scope, _query), do: {:error, :not_authorized}

  @doc "Suspend an account credential without changing any car authority."
  def suspend_account(%Scope{} = scope, user_id, expected_version, reason) do
    change_account_access(scope, user_id, expected_version, reason, :suspended)
  end

  def suspend_account(_scope, _user_id, _expected_version, _reason),
    do: {:error, :not_authorized}

  @doc "Restore an account credential without reconstructing car authority."
  def restore_account(%Scope{} = scope, user_id, expected_version, reason) do
    change_account_access(scope, user_id, expected_version, reason, :restored)
  end

  def restore_account(_scope, _user_id, _expected_version, _reason),
    do: {:error, :not_authorized}

  @doc "Revoke exactly one active Stewardship through the Owners transition."
  def revoke_stewardship(%Scope{} = scope, stewardship_id, reason) do
    with :ok <- authorize_operator(scope),
         {:ok, id} <- cast_uuid(stewardship_id),
         %Stewardship{} = stewardship <- Repo.get(Stewardship, id) do
      Owners.revoke_stewardship(stewardship, reason, scope.user)
    else
      :error -> {:error, :not_found}
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def revoke_stewardship(_scope, _stewardship_id, _reason),
    do: {:error, :not_authorized}

  @doc "Open car and update reports for the operator queue, oldest first."
  def list_content_reports(%Scope{} = scope) do
    with :ok <- authorize_operator(scope) do
      {:ok,
       Repo.all(
         from(r in ContentReport,
           where: r.status == :open,
           order_by: [asc: r.inserted_at, asc: r.id],
           preload: [:vehicle, :reporter_user]
         )
       )}
    end
  end

  def list_content_reports(_scope), do: {:error, :not_authorized}

  @doc "The number of car and update reports waiting in the Bench."
  def content_report_count(%Scope{} = scope) do
    with :ok <- authorize_operator(scope) do
      {:ok, Repo.aggregate(from(r in ContentReport, where: r.status == :open), :count)}
    end
  end

  def content_report_count(_scope), do: {:error, :not_authorized}

  @doc "Hide a reported car/update or dismiss one report, retaining the decision trail."
  def decide_content_report(%Scope{} = scope, report_id, decision, note)
      when decision in [:hide, :dismiss] do
    with :ok <- authorize_operator(scope),
         {:ok, id} <- cast_uuid(report_id),
         {:ok, note} <- validate_reason(note) do
      Repo.transaction(fn ->
        case Repo.get(ContentReport, id) do
          %ContentReport{} = report ->
            decide_locked_content_report(report, scope.user, decision, note)

          nil ->
            Repo.rollback(:not_found)
        end
      end)
    end
  end

  def decide_content_report(%Scope{} = scope, _report_id, _decision, _note) do
    with :ok <- authorize_operator(scope), do: {:error, :invalid_report_decision}
  end

  def decide_content_report(_scope, _report_id, _decision, _note),
    do: {:error, :not_authorized}

  @doc "Read-only 30-day operating measures derived from the rows each domain already owns."
  def metrics(%Scope{} = scope) do
    with :ok <- authorize_operator(scope) do
      cutoff = DateTime.add(DateTime.utc_now(), -30, :day)

      recent_entry_refs =
        from(c in Claim,
          join: p in Party,
          on: p.id == c.asserted_by_party_id,
          where: p.kind == :owner and not is_nil(c.entry_ref),
          group_by: c.entry_ref,
          having: min(c.inserted_at) >= ^cutoff,
          select: c.entry_ref
        )

      owner_claims =
        Repo.all(
          from(c in Claim,
            join: p in Party,
            on: p.id == c.asserted_by_party_id,
            where: p.kind == :owner and c.entry_ref in subquery(recent_entry_refs),
            order_by: [asc: c.inserted_at, asc: c.id]
          )
        )

      entry_metrics = owner_entry_metrics(owner_claims)
      claim_count = Repo.aggregate(from(c in Claim, where: c.inserted_at >= ^cutoff), :count)

      {:ok,
       Map.merge(entry_metrics, %{
         window_days: 30,
         active_stewards:
           Repo.aggregate(from(s in Stewardship, where: s.status == :active), :count),
         claims: claim_count,
         claims_per_day: Float.round(claim_count / 30, 1)
       })}
    end
  end

  def metrics(_scope), do: {:error, :not_authorized}

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

  defp decide_locked_content_report(report, operator, decision, note) do
    reports = lock_content_target_reports(report)
    selected = Enum.find(reports, &(&1.id == report.id))

    cond do
      is_nil(selected) ->
        Repo.rollback(:not_found)

      selected.status != :open ->
        Repo.rollback(:already_decided)

      decision == :dismiss ->
        dismiss_content_report(selected, operator, note)

      true ->
        hide_content_target(selected, reports, operator, note)
    end
  end

  defp lock_content_target_reports(%ContentReport{} = report) do
    query =
      from(r in ContentReport,
        where: r.target_kind == ^report.target_kind and r.vehicle_id == ^report.vehicle_id,
        order_by: [asc: r.inserted_at, asc: r.id],
        lock: "FOR UPDATE"
      )

    query =
      case report.entry_ref do
        nil -> where(query, [r], is_nil(r.entry_ref))
        entry_ref -> where(query, [r], r.entry_ref == ^entry_ref)
      end

    Repo.all(query)
  end

  defp dismiss_content_report(report, operator, note) do
    report
    |> Ecto.Changeset.change(
      status: :dismissed,
      decided_by_user_id: operator.id,
      decided_at: DateTime.utc_now(),
      decision_note: note
    )
    |> Repo.update!()
  end

  defp hide_content_target(report, _reports, operator, note) do
    now = DateTime.utc_now()

    hidden =
      case report.target_kind do
        :vehicle -> hide_vehicle(report.vehicle_id, now)
        :entry -> hide_entry(report.vehicle_id, report.entry_ref, now)
      end

    resolution_query =
      from(r in ContentReport,
        where:
          r.target_kind == ^report.target_kind and r.vehicle_id == ^report.vehicle_id and
            r.status == :open
      )

    resolution_query =
      case report.entry_ref do
        nil -> where(resolution_query, [r], is_nil(r.entry_ref))
        entry_ref -> where(resolution_query, [r], r.entry_ref == ^entry_ref)
      end

    Repo.update_all(
      resolution_query,
      set: [
        status: :actioned,
        decided_by_user_id: operator.id,
        decided_at: now,
        decision_note: note,
        updated_at: now
      ]
    )

    %{report: report, hidden: hidden}
  end

  defp hide_vehicle(vehicle_id, now) do
    case Repo.one(from(v in Vehicle, where: v.id == ^vehicle_id, lock: "FOR UPDATE")) do
      %Vehicle{visibility: :public} = vehicle ->
        vehicle
        |> Ecto.Changeset.change(visibility: :private, updated_at: now)
        |> Repo.update!()

      %Vehicle{visibility: :private} ->
        Repo.rollback(:already_hidden)

      nil ->
        Repo.rollback(:not_found)
    end
  end

  defp hide_entry(vehicle_id, entry_ref, now) do
    claim_query =
      from(c in Claim, where: c.vehicle_id == ^vehicle_id and c.entry_ref == ^entry_ref)

    photo_query =
      from(p in VehiclePhoto, where: p.vehicle_id == ^vehicle_id and p.entry_ref == ^entry_ref)

    participation_query =
      from(p in EventParticipation,
        where: p.vehicle_id == ^vehicle_id and p.entry_ref == ^entry_ref
      )

    if not Repo.exists?(claim_query) and not Repo.exists?(photo_query) and
         not Repo.exists?(participation_query) do
      Repo.rollback(:not_found)
    end

    {claims, _rows} = Repo.update_all(claim_query, set: [visibility: :private, updated_at: now])
    {photos, _rows} = Repo.update_all(photo_query, set: [visibility: :private, updated_at: now])

    {participations, _rows} =
      Repo.update_all(participation_query, set: [visibility: :private, updated_at: now])

    %{claims: claims, photos: photos, participations: participations}
  end

  defp owner_entry_metrics(claims) do
    entries = claims |> Enum.group_by(& &1.entry_ref) |> Map.values()
    entry_count = length(entries)
    mcp_entries = Enum.count(entries, &mcp_entry?/1)
    amended_entries = Enum.count(entries, &amended_entry?/1)
    deleted_entries = Enum.count(entries, &deleted_entry?/1)
    corrected_entries = amended_entries + deleted_entries

    %{
      entries: entry_count,
      mcp_entries: mcp_entries,
      composer_entries: entry_count - mcp_entries,
      mcp_share: percentage(mcp_entries, entry_count),
      amended_entries: amended_entries,
      deleted_entries: deleted_entries,
      correction_rate: percentage(corrected_entries, entry_count)
    }
  end

  defp mcp_entry?([first | _rest]), do: first.method_meta["surface"] == "mcp"
  defp mcp_entry?([]), do: false

  defp amended_entry?(claims) do
    Enum.any?(claims, &(&1.state == :retracted)) and
      Enum.any?(claims, &(&1.state in @live_claim_states))
  end

  defp deleted_entry?(claims) do
    Enum.any?(claims, &(&1.state == :retracted)) and
      not Enum.any?(claims, &(&1.state in @live_claim_states))
  end

  defp percentage(_numerator, 0), do: 0.0
  defp percentage(numerator, denominator), do: Float.round(numerator / denominator * 100, 1)

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

  defp authorize_operator(%Scope{user: %User{id: user_id}} = scope) do
    authorized? =
      Accounts.operator?(scope) and
        Repo.exists?(
          from(u in User,
            where: u.id == ^user_id and u.operator == true and is_nil(u.suspended_at)
          )
        )

    if authorized?, do: :ok, else: {:error, :not_authorized}
  end

  defp authorize_operator(_scope), do: {:error, :not_authorized}

  defp normalize_account_query(query) do
    case String.trim(query) do
      "" -> {:error, :query_required}
      term -> {:ok, term}
    end
  end

  defp decorate_access_account(nil), do: nil

  defp decorate_access_account(account) do
    user_id = account.user.id

    active_stewardships =
      Repo.all(
        from(s in Stewardship,
          where: s.user_id == ^user_id and s.status == :active,
          order_by: [desc: s.decided_at, desc: s.id],
          preload: [:vehicle]
        )
      )

    access_decisions =
      Repo.all(
        from(d in AccessDecision,
          where: d.user_id == ^user_id,
          order_by: [desc: d.access_version],
          preload: [:decided_by_user]
        )
      )

    account
    |> Map.put(:active_stewardships, active_stewardships)
    |> Map.put(:access_decisions, access_decisions)
  end

  defp change_account_access(scope, user_id, expected_version, reason, action) do
    with :ok <- authorize_operator(scope),
         {:ok, id} <- cast_uuid(user_id),
         {:ok, version} <- cast_version(expected_version),
         {:ok, reason} <- validate_reason(reason) do
      Repo.transact(fn ->
        case Repo.one(from(u in User, where: u.id == ^id, lock: "FOR UPDATE")) do
          %User{} = user ->
            transition_account_access(user, scope.user, version, reason, action)

          nil ->
            Repo.rollback(:not_found)
        end
      end)
    end
  end

  defp transition_account_access(user, operator, expected_version, reason, action) do
    cond do
      user.access_version != expected_version ->
        Repo.rollback({:stale_access_state, user.access_version})

      action == :suspended and User.suspended?(user) ->
        Repo.rollback(:already_suspended)

      action == :restored and not User.suspended?(user) ->
        Repo.rollback(:already_active)

      true ->
        persist_account_access(user, operator, reason, action)
    end
  end

  defp persist_account_access(user, operator, reason, action) do
    now = DateTime.utc_now()
    next_version = user.access_version + 1
    suspended_at = if action == :suspended, do: now, else: nil

    with {:ok, updated_user} <-
           user
           |> User.access_changeset(suspended_at, next_version)
           |> Repo.update(),
         {:ok, decision} <-
           Repo.insert(%AccessDecision{
             user_id: user.id,
             decided_by_user_id: operator.id,
             action: action,
             reason: reason,
             access_version: next_version,
             decided_at: now
           }) do
      session_tokens =
        Repo.all(
          from(t in UserToken,
            where: t.user_id == ^user.id and t.context == "session",
            select: %{token: t.token}
          )
        )

      {:ok, %{user: updated_user, decision: decision, session_tokens: session_tokens}}
    else
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp cast_uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end

  defp cast_version(version) when is_integer(version) and version >= 0, do: {:ok, version}

  defp cast_version(version) when is_binary(version) do
    case Integer.parse(version) do
      {parsed, ""} when parsed >= 0 -> {:ok, parsed}
      _invalid -> {:error, :invalid_access_version}
    end
  end

  defp cast_version(_version), do: {:error, :invalid_access_version}

  defp validate_reason(reason) when is_binary(reason) do
    case String.trim(reason) do
      "" -> {:error, :reason_required}
      trimmed when byte_size(trimmed) > 500 -> {:error, :reason_too_long}
      trimmed -> {:ok, trimmed}
    end
  end

  defp validate_reason(_reason), do: {:error, :reason_required}

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
