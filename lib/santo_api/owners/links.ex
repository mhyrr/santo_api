defmodule SantoApi.Owners.Links do
  @moduledoc """
  Curation, not evidence (owner_surface §2, §7b.1 decision 8) — see
  `SantoApi.Owners.VehicleLink` for the doctrine line in full.

  Every write goes through the caller's stewardship, the same authorization
  every owner write goes through (`SantoApi.Owners.stewardship/2`): a link is
  presentation on the page a steward maintains, and someone with no
  stewardship has no page to curate.

  Unlike the ledger, this context deletes and edits in place. A link carries no
  `content_hash` and asserts nothing, so there is no attestation to protect by
  forcing corrections through a retract-and-reassert dance — a steward removing
  a dead YouTube link just removes it.
  """

  import Ecto.Query, warn: false

  alias SantoApi.Accounts.Scope
  alias SantoApi.Owners
  alias SantoApi.Owners.{Stewardship, VehicleLink}
  alias SantoApi.Registry.Vehicle
  alias SantoApi.Repo

  @doc "A car's links, in the order its steward arranged them."
  def list_links(%Vehicle{} = vehicle) do
    Repo.all(
      from(l in VehicleLink,
        where: l.vehicle_id == ^vehicle.id,
        order_by: [asc: l.position, asc: l.inserted_at]
      )
    )
  end

  @doc """
  Add a link to the end of the car's list (owner_surface §7b.1 decision 8,
  onboarding's last step). Requires the caller's active stewardship of
  `vehicle`; any `position` in `attrs` is ignored in favor of appending after
  whatever is already there.
  """
  def add_link(%Scope{} = scope, %Vehicle{} = vehicle, attrs) do
    with {:ok, _stewardship} <- authorize(scope, vehicle) do
      %VehicleLink{vehicle_id: vehicle.id}
      |> VehicleLink.changeset(attrs)
      |> Ecto.Changeset.put_change(:position, next_position(vehicle))
      |> Repo.insert()
    end
  end

  @doc """
  Update a link's `url`, `label`, or `position`. Requires the caller's active
  stewardship, and the link must belong to `vehicle` — a link id alone is not
  enough, since ids are opaque and a caller must not be able to reach another
  car's links by guessing one.
  """
  def update_link(%Scope{} = scope, %Vehicle{} = vehicle, link_id, attrs) do
    with {:ok, _stewardship} <- authorize(scope, vehicle),
         {:ok, link} <- fetch(vehicle, link_id) do
      link
      |> VehicleLink.changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Remove a link. A plain delete — links are mutable presentation, not ledger
  rows, so there is no retraction to model and no reason to keep a dead row
  around (contrast `SantoApi.Registry.retract_claim/2`, which only ever flips a
  state).
  """
  def remove_link(%Scope{} = scope, %Vehicle{} = vehicle, link_id) do
    with {:ok, _stewardship} <- authorize(scope, vehicle),
         {:ok, link} <- fetch(vehicle, link_id) do
      Repo.delete(link)
    end
  end

  defp authorize(scope, vehicle) do
    case Owners.stewardship(scope, vehicle) do
      %Stewardship{} = stewardship -> {:ok, stewardship}
      nil -> {:error, :not_stewarded}
    end
  end

  # Scoped to the vehicle on the way in, not checked after the fact — a link
  # id from another car's page must come back not-found here, never loaded and
  # then rejected.
  defp fetch(vehicle, link_id) do
    case Ecto.UUID.cast(link_id) do
      {:ok, id} ->
        case Repo.get_by(VehicleLink, id: id, vehicle_id: vehicle.id) do
          %VehicleLink{} = link -> {:ok, link}
          nil -> {:error, :not_found}
        end

      :error ->
        {:error, :not_found}
    end
  end

  defp next_position(vehicle) do
    query = from(l in VehicleLink, where: l.vehicle_id == ^vehicle.id, select: max(l.position))

    case Repo.one(query) do
      nil -> 0
      max -> max + 1
    end
  end
end
