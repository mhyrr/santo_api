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
  alias SantoApi.Registry.{Artifact, Party, Vehicle}
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
end
