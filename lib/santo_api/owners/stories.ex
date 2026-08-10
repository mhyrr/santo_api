defmodule SantoApi.Owners.Stories do
  @moduledoc """
  Owner-authorized curation of the mutable story block on a car page.

  The current steward may revise the block in place. That is intentionally
  unlike a claim correction: prose about why the car matters is presentation,
  not an attested fact.
  """

  alias SantoApi.Accounts.{Scope, User}
  alias SantoApi.Owners
  alias SantoApi.Owners.{Stewardship, VehicleStory}
  alias SantoApi.Registry.Vehicle
  alias SantoApi.Repo

  def get_story(%Vehicle{} = vehicle) do
    case Repo.get_by(VehicleStory, vehicle_id: vehicle.id) do
      %VehicleStory{} = story -> Repo.preload(story, :author_user)
      nil -> nil
    end
  end

  def change_story(%VehicleStory{} = story, attrs \\ %{}),
    do: VehicleStory.changeset(story, attrs)

  def save_story(%Scope{user: %User{} = user} = scope, %Vehicle{} = vehicle, attrs) do
    with %Stewardship{} <- Owners.stewardship(scope, vehicle) do
      story = get_story(vehicle) || %VehicleStory{vehicle_id: vehicle.id}

      story
      |> Map.put(:author_user_id, user.id)
      |> VehicleStory.changeset(attrs)
      |> Repo.insert_or_update()
    else
      nil -> {:error, :not_stewarded}
    end
  end

  def save_story(_scope, %Vehicle{}, _attrs), do: {:error, :authentication_required}
end
