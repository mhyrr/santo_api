defmodule SantoApi.Owners do
  @moduledoc """
  The owner side of the house: who a user is in the ledger, which cars they
  steward, and what they may assert about them.

  This context holds the authorization layer and calls `SantoApi.Registry` for
  every write. The separation is deliberate (owner_surface §4): **stewardship is
  authz, never registry truth.** Claiming a car creates no ownership claim —
  possession proves access, not title — so a page says "maintained by", never
  "owned by". Keeping stewardship out of `Registry` keeps the ledger's write
  paths ignorant of users, which is what lets a party outlive its account.

  The scope split (§3) is enforced here, and here only: an owner self-ratifies
  event- and observed-scope claims on a car they steward, and factory- or
  provenance-scope claims from an owner wait at the operator gate.
  `Vocabulary.scope_kind/1` draws the line.
  """

  import Ecto.Query, warn: false

  alias SantoApi.Accounts.Scope
  alias SantoApi.Accounts.User
  alias SantoApi.Owners.Stewardship
  alias SantoApi.Registry
  alias SantoApi.Registry.{Artifact, Claim, Party, Vehicle}
  alias SantoApi.Repo

  @doc """
  The ledger identity for a user, or `nil` before they have asserted anything.

  Read through the user's id rather than off the struct, because a struct held
  from before `ensure_party/2` still says `nil` and callers would silently mint a
  second party.
  """
  def party(%User{id: user_id}) do
    Repo.one(
      from(p in Party,
        join: u in User,
        on: u.party_id == p.id,
        where: u.id == ^user_id
      )
    )
  end

  @doc """
  Give a user their permanent ledger identity — the first assertive act
  (owner_surface §5).

  Idempotent on the handle already held. A *different* handle is refused rather
  than applied: the name is baked into every claim's `content_hash`, so a rename
  is not an edit we can make, and silently ignoring the argument would hide that
  from the caller.
  """
  def ensure_party(%User{} = user, handle) when is_binary(handle) do
    case party(user) do
      %Party{} = existing ->
        if existing.name == normalize_handle(handle),
          do: {:ok, existing},
          else: {:error, :handle_immutable}

      nil ->
        create_party(user, handle)
    end
  end

  defp create_party(user, handle) do
    Repo.transaction(fn ->
      with {:ok, party} <- Repo.insert(Party.handle_changeset(handle)),
           {:ok, _user} <- link_party(user, party) do
        party
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp link_party(user, party) do
    user
    |> Ecto.Changeset.change(party_id: party.id)
    |> Ecto.Changeset.unique_constraint(:party_id)
    |> Repo.update()
  end

  defp normalize_handle(handle), do: handle |> String.trim() |> String.downcase()

  ## Stewardship — who maintains which car

  @doc """
  Authorize a user to maintain a car's log (owner_surface §4 step 5).

  Mints the user's permanent handle on the way through, because a grant is the
  first assertive act and there is no stewardship without a ledger identity to
  attribute entries to. Writes no claim: this says who maintains the log, not
  who owns the car.

  ## Options

    * `:handle` — the user's permanent public handle, required the first time
    * `:proof_artifact` — the possession proof that justified the grant (§4)
    * `:decided_by` — the operator who approved it

  Idempotent for a user who already stewards the car. A car another user
  actively stewards returns `{:error, :already_stewarded}` — a second claimant is
  a contested claim for an operator to adjudicate, not a second row.
  """
  def grant_stewardship(%User{} = user, %Vehicle{} = vehicle, opts \\ []) do
    case active_stewardship(vehicle) do
      %Stewardship{user_id: user_id} = existing when user_id == user.id ->
        {:ok, existing}

      %Stewardship{} ->
        {:error, :already_stewarded}

      nil ->
        with {:ok, _party} <- ensure_party(user, Keyword.fetch!(opts, :handle)) do
          {:ok,
           Repo.insert!(%Stewardship{
             user_id: user.id,
             vehicle_id: vehicle.id,
             proof_artifact_id: artifact_id(opts[:proof_artifact]),
             status: :active,
             decided_by_user_id: user_id(opts[:decided_by]),
             decided_at: DateTime.utc_now()
           })}
        end
    end
  end

  @doc """
  End a stewardship. A status flip with a reason and a decider — the row stays,
  and so does everything logged under it.
  """
  def revoke_stewardship(%Stewardship{} = stewardship, reason, decided_by \\ nil)
      when is_binary(reason) do
    case Repo.get(Stewardship, stewardship.id) do
      %Stewardship{status: :active} = current ->
        current
        |> Ecto.Changeset.change(
          status: :revoked,
          reason: reason,
          decided_by_user_id: user_id(decided_by),
          decided_at: DateTime.utc_now()
        )
        |> Repo.update()

      _inactive ->
        {:error, :not_active}
    end
  end

  @doc """
  The party a page names as maintaining this car, or `nil` when nobody does.
  """
  def steward(%Vehicle{} = vehicle) do
    Repo.one(
      from(s in Stewardship,
        join: u in User,
        on: u.id == s.user_id,
        join: p in Party,
        on: p.id == u.party_id,
        where: s.vehicle_id == ^vehicle.id and s.status == :active,
        select: p
      )
    )
  end

  @doc """
  The caller's active stewardship of this car, or `nil`. The authorization every
  owner write goes through.
  """
  def stewardship(%Scope{user: %User{} = user}, %Vehicle{} = vehicle) do
    Repo.one(
      from(s in Stewardship,
        where:
          s.user_id == ^user.id and s.vehicle_id == ^vehicle.id and
            s.status == :active
      )
    )
  end

  def stewardship(_scope, %Vehicle{}), do: nil

  @doc "Whether the caller may maintain this car's log."
  def stewarding?(scope, %Vehicle{} = vehicle), do: stewardship(scope, vehicle) != nil

  @doc "The caller's garage — every car they currently steward, newest first."
  def list_stewarded_vehicles(%Scope{user: %User{} = user}) do
    Repo.all(
      from(v in Vehicle,
        join: s in Stewardship,
        on: s.vehicle_id == v.id,
        where: s.user_id == ^user.id and s.status == :active,
        order_by: [desc: s.decided_at]
      )
    )
  end

  def list_stewarded_vehicles(_scope), do: []

  defp active_stewardship(%Vehicle{} = vehicle) do
    Repo.one(from(s in Stewardship, where: s.vehicle_id == ^vehicle.id and s.status == :active))
  end

  defp artifact_id(%Artifact{id: id}), do: id
  defp artifact_id(nil), do: nil

  defp user_id(%User{id: id}), do: id
  defp user_id(nil), do: nil

  @doc """
  The logbook as this caller may read it (owner_surface §6).

  The steward of a car sees their private entries; everybody else sees the
  public page. This is the read half of the privacy toggle, and it has to exist
  wherever the toggle does — an entry only its author can hide and nobody at all
  can see is a hole, not a feature.
  """
  def timeline(scope, %Vehicle{} = vehicle) do
    Registry.timeline(vehicle.id, include_private: stewarding?(scope, vehicle))
  end

  ## Entries — the composer's write path

  @doc """
  Write one composed entry to the ledger (owner_surface §1, §3).

  Every claim and photo of one entry shares an `entry_ref`, which is what makes
  a fill-up present as one line rather than two and what lets two identical
  ten-gallon fill-ups on one day be two events instead of one deduped claim.

  The scope split, and the only place it is enforced:

    * **event and observed scope** — proposed and ratified in one transaction
      with the owner as ratifier. The gate's shape survives (every claim passes
      through `:proposed`, every admission has a who and a when); only the
      latency collapses.
    * **factory and provenance scope** — proposed and left there. These touch
      `facts` and the verified display, so they wait for the operator gate or
      corroborating evidence.

  All or nothing: one rejected claim rolls the whole entry back, because half an
  entry in the ledger is worse than none.

  ## Attributes

    * `:date` — required. The timeline orders by it and the fold reads recency
      off it, so an owner entry is never undated.
    * `:claims` — `[%{predicate: ..., value: ...}]`, at least one.
    * `:photos` — `[%{path:, filename:, mime:}]`, owner-supplied artifacts.
    * `:visibility` — `:public` (default) or `:private`. Presentation only: a
      private claim is still admitted, still counts, and still folds into
      current state.
  """
  def compose_entry(scope, %Vehicle{} = vehicle, attrs) do
    with {:ok, stewardship} <- authorize_entry(scope, vehicle),
         {:ok, date} <- entry_date(attrs),
         {:ok, claim_attrs} <- entry_claims(attrs) do
      party = party(%User{id: stewardship.user_id})
      write_entry(vehicle, party, date, claim_attrs, attrs)
    end
  end

  defp authorize_entry(scope, vehicle) do
    case stewardship(scope, vehicle) do
      %Stewardship{} = stewardship -> {:ok, stewardship}
      nil -> {:error, :not_stewarded}
    end
  end

  defp entry_date(%{date: %Date{} = date}), do: {:ok, date}

  defp entry_date(%{date: iso}) when is_binary(iso) do
    case Date.from_iso8601(iso) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, :missing_date}
    end
  end

  defp entry_date(_attrs), do: {:error, :missing_date}

  defp entry_claims(%{claims: [_first | _rest] = claims}), do: {:ok, claims}
  defp entry_claims(_attrs), do: {:error, :empty_entry}

  defp write_entry(vehicle, party, date, claim_attrs, attrs) do
    entry_ref = Registry.new_entry_ref()
    visibility = Map.get(attrs, :visibility, :public)

    result =
      Repo.transaction(fn ->
        claims = Enum.map(claim_attrs, &write_claim!(vehicle, party, date, entry_ref, &1))

        artifacts =
          Enum.map(Map.get(attrs, :photos, []), &write_photo!(vehicle, party, entry_ref, &1))

        %{
          entry_ref: entry_ref,
          claims: Enum.map(claims, &apply_visibility!(&1, visibility)),
          artifacts: Enum.map(artifacts, &apply_visibility!(&1, visibility))
        }
      end)

    case result do
      {:ok, entry} -> {:ok, entry}
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_claim!(vehicle, party, date, entry_ref, %{predicate: predicate, value: value}) do
    attrs = %{
      "predicate" => predicate,
      "value" => value,
      "scope_date" => date,
      "entry_ref" => entry_ref
    }

    case Registry.propose_claim(vehicle, party, attrs) do
      {:ok, claim} ->
        maybe_self_ratify!(claim, party)

      {:error, %Ecto.Changeset{} = changeset} ->
        if duplicate_hash?(changeset),
          do: recover_claim!(vehicle, changeset, party),
          else: Repo.rollback(changeset)

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  # An observation re-asserted is one fact, not two. `entry_ref` joins the hash
  # for event-scoped claims only (owner_surface §2, ratified), so two identical
  # fill-ups on one day are two distinct `event.fuel` claims that share a single
  # `observation.mileage` — the car read 41,660 once, whatever we were doing when
  # we noticed. Recovering the existing claim is what the savepoint in
  # `propose_claim` was built for; the alternative is refusing an entry an owner
  # legitimately wants to make.
  defp duplicate_hash?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn {field, {_message, meta}} ->
      field == :content_hash and meta[:constraint] == :unique
    end)
  end

  defp recover_claim!(vehicle, changeset, party) do
    content_hash = Ecto.Changeset.get_field(changeset, :content_hash)

    case Repo.get_by(Claim, vehicle_id: vehicle.id, content_hash: content_hash) do
      %Claim{state: :proposed} = claim ->
        maybe_self_ratify!(claim, party)

      %Claim{state: :admitted} = claim ->
        claim

      # Rejected or superseded: this exact assertion has already been ruled on.
      # Quietly resurrecting it would let the composer undo an adjudication.
      %Claim{state: state} ->
        Repo.rollback({:claim_not_live, state})

      nil ->
        Repo.rollback(changeset)
    end
  end

  # The line the doctrine draws, read straight off the vocabulary so it cannot
  # drift from the scope kinds themselves.
  defp maybe_self_ratify!(%Claim{scope_kind: kind} = claim, party)
       when kind in [:event, :observed] do
    case Registry.ratify_claim(claim.id, party) do
      {:ok, ratified} -> ratified
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp maybe_self_ratify!(%Claim{} = claim, _party), do: claim

  # Raises rather than returning an error, which rolls the entry back with the
  # original exception — a photo that cannot be read or stored is not a case the
  # composer can helpfully explain away.
  defp write_photo!(vehicle, party, entry_ref, %{path: path, filename: filename} = photo) do
    {:ok, artifact} =
      Registry.create_upload_artifact(%{
        vehicle_id: vehicle.id,
        path: path,
        filename: filename,
        mime: photo[:mime],
        kind: :photo,
        entry_ref: entry_ref,
        source_party: party
      })

    artifact
  end

  # Public is the default on both tables, so only a private entry writes here.
  defp apply_visibility!(row, :public), do: row

  defp apply_visibility!(row, :private) do
    case Registry.set_visibility(row, :private) do
      {:ok, updated} -> updated
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc """
  What the composer pre-fills for the next entry (owner_surface §1).

  The Fuelly bar is three numbers, and it is only three numbers if the odometer
  starts from the last reading rather than from an empty field. Empty for a car
  with no entries — there is nothing to carry forward and a zero would be a lie.
  """
  def last_entry_defaults(scope, %Vehicle{} = vehicle) do
    if stewarding?(scope, vehicle) do
      %{}
      |> put_last(vehicle, "observation.mileage", &%{odometer: &1})
      |> put_last(vehicle, "event.fuel", &%{volume: &1["volume"], unit: &1["unit"]})
    else
      %{}
    end
  end

  defp put_last(defaults, vehicle, predicate, shape) do
    case latest_claim_value(vehicle, predicate) do
      nil -> defaults
      value -> Map.merge(defaults, shape.(value))
    end
  end

  defp latest_claim_value(vehicle, predicate) do
    Repo.one(
      from(c in Claim,
        where:
          c.vehicle_id == ^vehicle.id and c.predicate == ^predicate and
            c.state == :admitted and c.method == :human,
        order_by: [desc: c.scope_date, desc: c.inserted_at],
        limit: 1,
        select: c.value
      )
    )
  end
end
