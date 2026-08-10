defmodule SantoApi.Events do
  @moduledoc """
  Generic shared events and the owner accounts gathered around them.

  The context owns only the universal coordinate and participation layer. It
  deliberately does not model runs, classes, sessions, setup sheets, awards,
  or standings. Owner-defined details remain ordered text and never mutate a
  car's durable `current_state`.

  A participation is also an ordinary owner update. Creation therefore writes
  the logbook entry through `SantoApi.Owners` and stores its `entry_ref` here;
  conversation remains on that update permalink, where the subject is clear.
  """

  import Ecto.Query, warn: false

  alias SantoApi.Accounts.{Scope, User}
  alias SantoApi.Events.{EventAttachment, EventOccurrence, EventParticipation}
  alias SantoApi.Owners
  alias SantoApi.Registry.{Artifact, Vehicle}
  alias SantoApi.Repo

  @doc "Create one event participation and its ordinary car update atomically."
  def create_participation(
        %Scope{user: %User{} = user} = scope,
        %Vehicle{} = vehicle,
        attrs
      ) do
    if Owners.stewarding?(scope, vehicle) do
      case Repo.transaction(fn -> create_participation!(scope, user, vehicle, attrs) end) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :not_stewarded}
    end
  end

  def create_participation(_scope, %Vehicle{}, _attrs), do: {:error, :authentication_required}

  @doc "Add labeled photo uploads to an existing participation and its car update."
  def add_uploads(
        %Scope{user: %User{id: user_id}} = scope,
        %Vehicle{} = vehicle,
        %EventParticipation{} = participation,
        uploads
      )
      when is_list(uploads) do
    if participation.user_id == user_id and participation.vehicle_id == vehicle.id do
      case Repo.transaction(fn ->
             media =
               case Owners.attach_photos(scope, vehicle, participation.entry_ref, uploads) do
                 {:ok, media} -> media
                 {:error, reason} -> Repo.rollback(reason)
               end

             position =
               Repo.aggregate(
                 from(a in EventAttachment, where: a.participation_id == ^participation.id),
                 :count
               )

             uploads
             |> Enum.zip(media.artifacts)
             |> Enum.with_index(position)
             |> Enum.each(fn {{upload, artifact}, index} ->
               %EventAttachment{participation_id: participation.id, artifact_id: artifact.id}
               |> EventAttachment.changeset(%{
                 label: value(upload, :label, value(upload, :filename, "Photo")),
                 kind: :photo,
                 position: index
               })
               |> insert_or_rollback!()
             end)

             Repo.preload(
               participation,
               [:event, :user, :vehicle, attachments: :artifact],
               force: true
             )
           end) do
        {:ok, updated} -> {:ok, updated}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :not_authorized}
    end
  end

  def add_uploads(_scope, %Vehicle{}, %EventParticipation{}, _uploads),
    do: {:error, :authentication_required}

  @doc "Validate the combined occurrence/participation draft before its review step."
  def validate_draft(attrs) do
    with {:ok, event} <- validate_draft_event(value(attrs, :event_id), value(attrs, :event, %{})),
         {:ok, participation} <-
           validate_draft_participation(event, value(attrs, :participation, %{})),
         :ok <- validate_draft_links(value(attrs, :links, [])) do
      {:ok, %{event: event, participation: participation}}
    end
  end

  defp create_participation!(scope, user, vehicle, attrs) do
    event = resolve_event!(user, value(attrs, :event_id), value(attrs, :event, %{}))
    participation_attrs = value(attrs, :participation, %{})
    uploads = value(attrs, :uploads, [])
    links = value(attrs, :links, [])

    validate_participation!(event, user, vehicle, participation_attrs)

    entry =
      case Owners.compose_entry(scope, vehicle, %{
             date: event.starts_on,
             claims: [outing_claim(event, participation_attrs)],
             attachments: uploads,
             visibility: visibility(participation_attrs)
           }) do
        {:ok, entry} -> entry
        {:error, reason} -> Repo.rollback(reason)
      end

    participation =
      %EventParticipation{
        event_id: event.id,
        vehicle_id: vehicle.id,
        user_id: user.id,
        entry_ref: entry.entry_ref
      }
      |> EventParticipation.changeset(participation_attrs)
      |> insert_or_rollback!()

    attachments =
      insert_attachments!(participation, uploads, entry.artifacts, links)

    %{
      event: with_counts(event),
      participation: %{
        participation
        | event: event,
          vehicle: vehicle,
          user: user,
          attachments: attachments
      },
      entry: entry
    }
  end

  defp validate_participation!(event, user, vehicle, attrs) do
    draft = %EventParticipation{
      event_id: event.id,
      vehicle_id: vehicle.id,
      user_id: user.id,
      entry_ref: Ecto.UUID.generate()
    }

    case EventParticipation.changeset(draft, attrs) do
      %Ecto.Changeset{valid?: true} -> :ok
      changeset -> Repo.rollback(changeset)
    end
  end

  defp validate_draft_event(event_id, event_attrs) when event_id in [nil, ""] do
    changeset = EventOccurrence.changeset(%EventOccurrence{}, event_attrs)

    if changeset.valid?,
      do: {:ok, Ecto.Changeset.apply_changes(changeset)},
      else: {:error, changeset}
  end

  defp validate_draft_event(event_id, _event_attrs) do
    with {:ok, id} <- Ecto.UUID.cast(event_id),
         %EventOccurrence{} = event <- Repo.get(EventOccurrence, id) do
      {:ok, event}
    else
      _absent -> {:error, :event_not_found}
    end
  end

  defp validate_draft_participation(event, attrs) do
    changeset =
      %EventParticipation{
        event_id: event.id || Ecto.UUID.generate(),
        vehicle_id: Ecto.UUID.generate(),
        user_id: Ecto.UUID.generate(),
        entry_ref: Ecto.UUID.generate()
      }
      |> EventParticipation.changeset(attrs)

    if changeset.valid?,
      do: {:ok, Ecto.Changeset.apply_changes(changeset)},
      else: {:error, changeset}
  end

  defp validate_draft_links(links) do
    Enum.reduce_while(links, :ok, fn link, :ok ->
      changeset =
        %EventAttachment{participation_id: Ecto.UUID.generate()}
        |> EventAttachment.changeset(%{
          url: value(link, :url),
          label: value(link, :label, "Link"),
          kind: value(link, :kind, :link),
          position: 0
        })

      if changeset.valid?, do: {:cont, :ok}, else: {:halt, {:error, changeset}}
    end)
  end

  defp resolve_event!(user, event_id, event_attrs) when event_id in [nil, ""] do
    %EventOccurrence{
      public_id: EventOccurrence.mint_public_id(),
      creator_user_id: user.id,
      source_status: :community
    }
    |> EventOccurrence.changeset(event_attrs)
    |> insert_or_rollback!()
  end

  defp resolve_event!(_user, event_id, _event_attrs) do
    with {:ok, id} <- Ecto.UUID.cast(event_id),
         %EventOccurrence{} = event <- Repo.get(EventOccurrence, id) do
      event
    else
      _absent -> Repo.rollback(:event_not_found)
    end
  end

  defp outing_claim(event, participation_attrs) do
    value = %{
      "kind" => "other",
      "venue" => event.place_text,
      "summary" => value(participation_attrs, :journal)
    }

    %{predicate: "event.outing", value: value}
  end

  defp insert_attachments!(participation, uploads, artifacts, links) do
    uploaded =
      uploads
      |> Enum.zip(artifacts)
      |> Enum.with_index()
      |> Enum.map(fn {{upload, artifact}, position} ->
        %EventAttachment{
          participation_id: participation.id,
          artifact_id: artifact.id
        }
        |> EventAttachment.changeset(%{
          label: value(upload, :label, value(upload, :filename, "Attachment")),
          kind: value(upload, :kind, :file),
          position: position
        })
        |> insert_or_rollback!()
        |> Map.put(:artifact, artifact)
      end)

    linked =
      links
      |> Enum.with_index(length(uploaded))
      |> Enum.map(fn {link, position} ->
        %EventAttachment{participation_id: participation.id}
        |> EventAttachment.changeset(%{
          url: value(link, :url),
          label: value(link, :label, "Link"),
          kind: value(link, :kind, :link),
          position: position
        })
        |> insert_or_rollback!()
      end)

    uploaded ++ linked
  end

  defp insert_or_rollback!(changeset) do
    case Repo.insert(changeset) do
      {:ok, row} -> row
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @doc "Public event page data, with only public participant accounts."
  def fetch_public_event(public_id) when is_binary(public_id) do
    case Repo.get_by(EventOccurrence, public_id: public_id) do
      %EventOccurrence{} = event ->
        event = Repo.preload(event, :creator_user)

        participations =
          Repo.all(
            from(p in EventParticipation,
              where: p.event_id == ^event.id and p.visibility == :public,
              order_by: [asc: p.inserted_at],
              preload: [:user, :vehicle, attachments: :artifact]
            )
          )

        {:ok, event |> Map.put(:participations, participations) |> with_counts()}

      nil ->
        {:error, :not_found}
    end
  end

  def fetch_public_event(_public_id), do: {:error, :not_found}

  @doc "Events available to the generic find-or-name composer."
  def search_events(query \\ "") do
    text = query |> to_string() |> String.trim()

    base =
      from(e in EventOccurrence,
        order_by: [desc: e.starts_on, desc: e.inserted_at],
        limit: 8
      )

    base =
      if text == "" do
        base
      else
        pattern = "%#{text}%"

        from(e in base,
          where:
            ilike(e.title, ^pattern) or ilike(e.place_text, ^pattern) or
              fragment("array_to_string(?, ' ') ILIKE ?", e.tags, ^pattern)
        )
      end

    Repo.all(base)
  end

  @doc "Event participations attached to a car's visible timeline entries."
  def participations_for_vehicle(scope, %Vehicle{} = vehicle) do
    viewer_id = viewer_id(scope)

    EventParticipation
    |> where([p], p.vehicle_id == ^vehicle.id)
    |> visible_to(viewer_id)
    |> preload([:event, :user, :vehicle, attachments: :artifact])
    |> Repo.all()
    |> Enum.map(&with_event_counts/1)
    |> Map.new(&{&1.entry_ref, &1})
  end

  @doc "One visible participation by the ordinary update it extends."
  def participation_for_entry(scope, %Vehicle{} = vehicle, entry_ref) do
    with {:ok, ref} <- Ecto.UUID.cast(entry_ref) do
      viewer_id = viewer_id(scope)

      query =
        EventParticipation
        |> where([p], p.vehicle_id == ^vehicle.id and p.entry_ref == ^ref)
        |> visible_to(viewer_id)
        |> preload([:event, :user, :vehicle, attachments: :artifact])

      case Repo.one(query) do
        %EventParticipation{} = participation -> {:ok, with_event_counts(participation)}
        nil -> {:error, :not_found}
      end
    else
      :error -> {:error, :not_found}
    end
  end

  @doc "Withdraw an owner's event account and its linked logbook update together."
  def retract_participation(
        %Scope{user: %User{id: user_id}} = scope,
        %Vehicle{} = vehicle,
        entry_ref
      ) do
    with {:ok, ref} <- Ecto.UUID.cast(entry_ref),
         %EventParticipation{} = participation <-
           Repo.get_by(EventParticipation,
             vehicle_id: vehicle.id,
             entry_ref: ref,
             user_id: user_id
           ) do
      case Repo.transaction(fn ->
             case Owners.retract_entry(scope, vehicle, ref) do
               {:ok, _count} -> Repo.delete!(participation)
               {:error, reason} -> Repo.rollback(reason)
             end
           end) do
        {:ok, participation} -> {:ok, participation}
        {:error, reason} -> {:error, reason}
      end
    else
      _absent -> {:error, :not_found}
    end
  end

  def retract_participation(_scope, %Vehicle{}, _entry_ref),
    do: {:error, :authentication_required}

  @doc "Resolve uploaded bytes only through a public event and participation."
  def fetch_public_attachment(event_public_id, attachment_id) do
    with {:ok, id} <- Ecto.UUID.cast(attachment_id),
         %EventAttachment{} = attachment <-
           Repo.one(
             from(a in EventAttachment,
               join: p in EventParticipation,
               on: p.id == a.participation_id,
               join: e in EventOccurrence,
               on: e.id == p.event_id,
               join: artifact in Artifact,
               on: artifact.id == a.artifact_id,
               where:
                 a.id == ^id and e.public_id == ^event_public_id and
                   p.visibility == :public,
               preload: [artifact: artifact]
             )
           ) do
      {:ok, attachment}
    else
      _absent -> {:error, :not_found}
    end
  end

  defp with_event_counts(%EventParticipation{event: %EventOccurrence{} = event} = participation) do
    %{participation | event: with_counts(event)}
  end

  defp with_counts(%EventOccurrence{} = event) do
    {participant_count, media_count} =
      Repo.one(
        from(p in EventParticipation,
          left_join: a in EventAttachment,
          on: a.participation_id == p.id and a.kind in [:photo, :video],
          where: p.event_id == ^event.id and p.visibility == :public,
          select: {count(p.id, :distinct), count(a.id)}
        )
      )

    %{event | participant_count: participant_count, media_count: media_count}
  end

  defp viewer_id(%Scope{user: %User{id: id}}), do: id
  defp viewer_id(_anonymous), do: nil

  defp visible_to(query, nil), do: where(query, [p], p.visibility == :public)

  defp visible_to(query, viewer_id) do
    where(query, [p], p.visibility == :public or p.user_id == ^viewer_id)
  end

  defp visibility(attrs) do
    case value(attrs, :visibility, :public) do
      value when value in [:private, "private"] -> :private
      _other -> :public
    end
  end

  defp value(map, key, default \\ nil)

  defp value(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, to_string(key), default))

  defp value(_map, _key, default), do: default
end
