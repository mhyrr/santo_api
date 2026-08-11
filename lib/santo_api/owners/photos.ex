defmodule SantoApi.Owners.Photos do
  @moduledoc """
  Owner-authorized presentation for first-party car photos.

  Upload bytes remain immutable Registry artifacts. This context governs the
  mutable choices that make them useful on a living car page: captionless alt
  text, ordering, hero selection, entry visibility, and removal from display.
  """

  import Ecto.Query, warn: false

  alias SantoApi.Accounts.{Scope, User}
  alias SantoApi.Media
  alias SantoApi.Owners
  alias SantoApi.Owners.{Stewardship, VehiclePhoto}
  alias SantoApi.Registry
  alias SantoApi.Registry.{Artifact, Vehicle}
  alias SantoApi.Repo

  @doc "Photos visible to a public visitor or, when authorized, the steward."
  def list_photos(%Vehicle{} = vehicle, opts \\ []) do
    include_private = Keyword.get(opts, :include_private, false)
    private_author_user_id = Keyword.get(opts, :private_author_user_id)

    visibility_filter =
      cond do
        not include_private ->
          dynamic([photo], photo.visibility == :public)

        is_binary(private_author_user_id) ->
          dynamic(
            [photo],
            photo.visibility == :public or photo.author_user_id == ^private_author_user_id
          )

        true ->
          dynamic(true)
      end

    query =
      from(photo in VehiclePhoto,
        join: artifact in Artifact,
        on: artifact.id == photo.artifact_id,
        join: author in User,
        on: author.id == photo.author_user_id,
        where: photo.vehicle_id == ^vehicle.id,
        order_by: [asc: photo.position, asc: photo.inserted_at],
        preload: [artifact: artifact, author_user: author]
      )

    query
    |> where(^visibility_filter)
    |> Repo.all()
  end

  @doc "The selected hero visible to this viewer, if the car has one."
  def hero(%Vehicle{} = vehicle, opts \\ []) do
    vehicle
    |> list_photos(opts)
    |> Enum.find(& &1.hero)
  end

  @doc "Attach one validated upload to an entry and the car's ordered gallery."
  def attach(
        %Scope{user: %User{} = user} = scope,
        %Vehicle{} = vehicle,
        %Artifact{} = artifact,
        attrs
      ) do
    with %Stewardship{} <- Owners.stewardship(scope, vehicle) do
      position = next_position(vehicle)
      visibility = visibility(attrs)

      photo = %VehiclePhoto{
        vehicle_id: vehicle.id,
        artifact_id: artifact.id,
        author_user_id: user.id
      }

      case photo
           |> VehiclePhoto.changeset(%{
             entry_ref: value(attrs, :entry_ref),
             entry_date: value(attrs, :entry_date),
             alt_text: value(attrs, :alt_text),
             position: position,
             visibility: visibility,
             hero: visibility == :public and first_public_photo?(vehicle)
           })
           |> Repo.insert() do
        {:ok, placement} -> {:ok, Repo.preload(placement, [:artifact, :author_user])}
        error -> error
      end
    else
      nil -> {:error, :not_stewarded}
    end
  end

  def attach(_scope, %Vehicle{}, %Artifact{}, _attrs),
    do: {:error, :authentication_required}

  @doc "Update a photo's human alt text."
  def update_alt(scope, %Vehicle{} = vehicle, photo_id, alt_text) do
    with {:ok, _stewardship} <- authorize(scope, vehicle),
         {:ok, photo} <- fetch(vehicle, photo_id) do
      photo
      |> VehiclePhoto.changeset(%{alt_text: alt_text})
      |> Repo.update()
    end
  end

  @doc "Select one public photo as the car's hero."
  def set_hero(scope, %Vehicle{} = vehicle, photo_id) do
    with {:ok, _stewardship} <- authorize(scope, vehicle),
         {:ok, %VehiclePhoto{visibility: :public} = photo} <- fetch(vehicle, photo_id) do
      Repo.transaction(fn ->
        Repo.update_all(
          from(candidate in VehiclePhoto,
            where: candidate.vehicle_id == ^vehicle.id and candidate.hero == true
          ),
          set: [hero: false, updated_at: DateTime.utc_now()]
        )

        photo
        |> Ecto.Changeset.change(hero: true)
        |> Repo.update!()
      end)
    else
      {:ok, %VehiclePhoto{visibility: :private}} -> {:error, :private_photo}
      other -> other
    end
  end

  @doc "Move a gallery photo by one position without accepting arbitrary order input."
  def move(scope, %Vehicle{} = vehicle, photo_id, direction)
      when direction in [:earlier, :later] do
    with {:ok, _stewardship} <- authorize(scope, vehicle),
         {:ok, photo} <- fetch(vehicle, photo_id) do
      photos = list_photos(vehicle, include_private: true)
      index = Enum.find_index(photos, &(&1.id == photo.id))
      swap_index = if direction == :earlier, do: index - 1, else: index + 1

      if is_integer(index) and swap_index >= 0 and swap_index < length(photos) do
        swap_positions(photo, Enum.at(photos, swap_index))
      else
        {:ok, photo}
      end
    end
  end

  def move(_scope, %Vehicle{}, _photo_id, _direction), do: {:error, :invalid_direction}

  @doc "Remove a photo from presentation while retaining its immutable artifact."
  def remove(scope, %Vehicle{} = vehicle, photo_id) do
    with {:ok, _stewardship} <- authorize(scope, vehicle),
         {:ok, photo} <- fetch(vehicle, photo_id) do
      was_hero? = photo.hero

      case Repo.delete(photo) do
        {:ok, removed} ->
          if was_hero?, do: promote_first_public(vehicle)
          {:ok, removed}

        error ->
          error
      end
    end
  end

  @doc "Remove every presentation row belonging to one owner-authored entry."
  def remove_entry(%Scope{user: %User{id: user_id}} = scope, %Vehicle{} = vehicle, entry_ref) do
    with {:ok, _stewardship} <- authorize(scope, vehicle),
         {:ok, ref} <- Ecto.UUID.cast(entry_ref) do
      {count, _rows} =
        Repo.delete_all(
          from(photo in VehiclePhoto,
            where:
              photo.vehicle_id == ^vehicle.id and photo.entry_ref == ^ref and
                photo.author_user_id == ^user_id
          )
        )

      promote_first_public(vehicle)
      {:ok, count}
    else
      :error -> {:error, :not_found}
      other -> other
    end
  end

  def remove_entry(_scope, %Vehicle{}, _entry_ref), do: {:error, :authentication_required}

  @doc "Remove selected photo placements from one authored entry by immutable artifact id."
  def remove_entry_artifacts(
        %Scope{user: %User{id: user_id}} = scope,
        %Vehicle{} = vehicle,
        entry_ref,
        artifact_ids
      )
      when is_list(artifact_ids) do
    with {:ok, _stewardship} <- authorize(scope, vehicle),
         {:ok, ref} <- Ecto.UUID.cast(entry_ref) do
      ids = Enum.uniq(artifact_ids)

      {count, _rows} =
        Repo.delete_all(
          from(photo in VehiclePhoto,
            where:
              photo.vehicle_id == ^vehicle.id and photo.entry_ref == ^ref and
                photo.author_user_id == ^user_id and photo.artifact_id in ^ids
          )
        )

      promote_first_public(vehicle)
      {:ok, count}
    else
      :error -> {:error, :not_found}
      other -> other
    end
  end

  def remove_entry_artifacts(_scope, %Vehicle{}, _entry_ref, _artifact_ids),
    do: {:error, :authentication_required}

  @doc "Change every photo placement in one authored entry without touching shared artifact bytes."
  def set_entry_visibility(
        %Scope{user: %User{id: user_id}} = scope,
        %Vehicle{} = vehicle,
        entry_ref,
        visibility
      )
      when visibility in [:public, :private] do
    with {:ok, _stewardship} <- authorize(scope, vehicle),
         {:ok, ref} <- Ecto.UUID.cast(entry_ref) do
      query =
        from(photo in VehiclePhoto,
          where:
            photo.vehicle_id == ^vehicle.id and photo.entry_ref == ^ref and
              photo.author_user_id == ^user_id
        )

      update_visibility(query, vehicle, visibility)
    else
      :error -> {:error, :not_found}
      other -> other
    end
  end

  def set_entry_visibility(_scope, %Vehicle{}, _entry_ref, _visibility),
    do: {:error, :authentication_required}

  @doc "Change every photo placement the current steward authored on this car."
  def set_all_visibility(
        %Scope{user: %User{id: user_id}} = scope,
        %Vehicle{} = vehicle,
        visibility
      )
      when visibility in [:public, :private] do
    with {:ok, _stewardship} <- authorize(scope, vehicle) do
      query =
        from(photo in VehiclePhoto,
          where: photo.vehicle_id == ^vehicle.id and photo.author_user_id == ^user_id
        )

      update_visibility(query, vehicle, visibility)
    end
  end

  def set_all_visibility(_scope, %Vehicle{}, _visibility),
    do: {:error, :authentication_required}

  @doc "Resolve a visible photo through the public car id and optional owner scope."
  def fetch_visible(scope, public_id, photo_id) do
    with {:ok, id} <- Ecto.UUID.cast(photo_id),
         {:ok, vehicle} <- Registry.fetch_by_public_id(public_id),
         %VehiclePhoto{} = photo <-
           Repo.one(
             from(photo in VehiclePhoto,
               join: artifact in Artifact,
               on: artifact.id == photo.artifact_id,
               where: photo.id == ^id and photo.vehicle_id == ^vehicle.id,
               preload: [artifact: artifact]
             )
           ),
         true <-
           (photo.visibility == :public and Owners.published?(vehicle)) or
             authored_by?(scope, photo) do
      {:ok, photo}
    else
      _absent -> {:error, :not_found}
    end
  end

  def variants(%VehiclePhoto{artifact: %Artifact{} = artifact}), do: Media.variants(artifact)

  def alt(%VehiclePhoto{alt_text: text}, _fallback) when is_binary(text), do: text
  def alt(%VehiclePhoto{}, fallback), do: "Photo of #{fallback}"

  defp authored_by?(%Scope{user: %User{id: user_id}}, %VehiclePhoto{author_user_id: user_id}),
    do: true

  defp authored_by?(_scope, %VehiclePhoto{}), do: false

  defp authorize(%Scope{} = scope, vehicle) do
    case Owners.stewardship(scope, vehicle) do
      %Stewardship{} = stewardship -> {:ok, stewardship}
      nil -> {:error, :not_stewarded}
    end
  end

  defp authorize(_scope, _vehicle), do: {:error, :authentication_required}

  defp fetch(vehicle, photo_id) do
    with {:ok, id} <- Ecto.UUID.cast(photo_id),
         %VehiclePhoto{} = photo <- Repo.get_by(VehiclePhoto, id: id, vehicle_id: vehicle.id) do
      {:ok, photo}
    else
      _absent -> {:error, :not_found}
    end
  end

  defp swap_positions(photo, other) do
    Repo.transaction(fn ->
      photo_position = photo.position
      photo = photo |> Ecto.Changeset.change(position: other.position) |> Repo.update!()
      _other = other |> Ecto.Changeset.change(position: photo_position) |> Repo.update!()
      photo
    end)
  end

  defp next_position(vehicle) do
    query =
      from(photo in VehiclePhoto,
        where: photo.vehicle_id == ^vehicle.id,
        select: max(photo.position)
      )

    case Repo.one(query) do
      nil -> 0
      position -> position + 1
    end
  end

  defp first_public_photo?(vehicle) do
    not Repo.exists?(
      from(photo in VehiclePhoto,
        where: photo.vehicle_id == ^vehicle.id and photo.visibility == :public
      )
    )
  end

  defp promote_first_public(vehicle) do
    if not Repo.exists?(
         from(photo in VehiclePhoto,
           where: photo.vehicle_id == ^vehicle.id and photo.hero == true
         )
       ) do
      case Repo.one(
             from(photo in VehiclePhoto,
               where: photo.vehicle_id == ^vehicle.id and photo.visibility == :public,
               order_by: [asc: photo.position, asc: photo.inserted_at],
               limit: 1
             )
           ) do
        %VehiclePhoto{} = photo ->
          photo |> Ecto.Changeset.change(hero: true) |> Repo.update!()

        nil ->
          :ok
      end
    end
  end

  # Privacy belongs to this use of the upload, not to its content-deduplicated
  # artifact. Hiding one placement must never hide the same bytes in another
  # owner's entry. A hidden hero is demoted in the same update; the next public
  # photo is promoted so the page never points its hero at private media.
  defp update_visibility(query, vehicle, visibility) do
    case Repo.transaction(fn ->
           updates =
             if visibility == :private do
               [visibility: :private, hero: false, updated_at: DateTime.utc_now()]
             else
               [visibility: :public, updated_at: DateTime.utc_now()]
             end

           {count, _rows} = Repo.update_all(query, set: updates)
           promote_first_public(vehicle)
           count
         end) do
      {:ok, count} -> {:ok, count}
      {:error, reason} -> {:error, reason}
    end
  end

  defp visibility(attrs) do
    case value(attrs, :visibility, :public) do
      value when value in [:private, "private"] -> :private
      _public -> :public
    end
  end

  defp value(map, key, default \\ nil)

  defp value(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, to_string(key), default))

  defp value(_attrs, _key, default), do: default
end
