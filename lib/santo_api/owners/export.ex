defmodule SantoApi.Owners.Export do
  @moduledoc """
  Builds the steward's portable vehicle archive.

  The archive is deliberately boring: one documented JSON document plus the
  original bytes the requesting steward supplied. Public registry evidence is
  described and linked in the manifest, but acquired third-party files are not
  silently relicensed into a download. Private contributions are selected by
  author, never merely by whoever stewards the car today.
  """

  import Ecto.Query, warn: false

  alias SantoApi.Accounts.{Scope, User}
  alias SantoApi.Events
  alias SantoApi.Events.EventParticipation
  alias SantoApi.Owners
  alias SantoApi.Owners.{Links, Photos, Stewardship, Stories, VehiclePhoto}
  alias SantoApi.Registry.{Artifact, Claim, Party, Vehicle}
  alias SantoApi.Repo
  alias SantoApi.Storage

  @format "vin_santo.vehicle_record"
  @version 1

  @doc "Build an in-memory ZIP after rechecking active stewardship."
  def build(%Scope{user: %User{} = user} = scope, %Vehicle{} = vehicle) do
    with %Stewardship{} = stewardship <- Owners.stewardship(scope, vehicle),
         %Party{} = party <- Owners.party(user),
         {:ok, original_files, archive_paths, artifacts, claims, photos, participations} <-
           archive_material(scope, vehicle, user, party, stewardship) do
      manifest =
        manifest(
          vehicle,
          party,
          stewardship,
          artifacts,
          archive_paths,
          claims,
          photos,
          participations
        )

      entries =
        [
          {~c"README.txt", readme()},
          {~c"record.json", Jason.encode!(manifest, pretty: true)}
        ] ++ original_files

      case :zip.create(~c"vin-santo-record.zip", entries, [:memory]) do
        {:ok, {_name, bytes}} ->
          {:ok,
           %{
             body: bytes,
             filename: "vin-santo-#{vehicle.public_id}-record.zip",
             manifest: manifest
           }}

        {:error, reason} ->
          {:error, {:archive, reason}}
      end
    else
      nil -> {:error, :not_stewarded}
      {:error, reason} -> {:error, reason}
    end
  end

  def build(_scope, %Vehicle{}), do: {:error, :authentication_required}

  defp manifest(
         vehicle,
         party,
         stewardship,
         artifacts,
         archive_paths,
         claims,
         photos,
         participations
       ) do
    %{
      "format" => @format,
      "version" => @version,
      "exported_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> iso(),
      "vehicle" => vehicle_map(vehicle),
      "stewardship" => stewardship_map(stewardship, party, archive_paths),
      "story" => story_map(Stories.get_story(vehicle)),
      "links" => Enum.map(Links.list_links(vehicle), &link_map/1),
      "entries" => entry_maps(claims, photos, participations),
      "claims" => Enum.map(claims, &claim_map/1),
      "photos" => Enum.map(photos, &photo_map(&1, archive_paths)),
      "events" => Enum.map(participations, &participation_map(&1, archive_paths)),
      "artifacts" => Enum.map(artifacts, &artifact_map(&1, archive_paths))
    }
  end

  defp archive_material(scope, vehicle, user, party, stewardship) do
    claims = record_claims(vehicle, party)

    photos =
      Photos.list_photos(vehicle,
        include_private: true,
        private_author_user_id: user.id
      )

    participations = Events.record_participations(scope, vehicle)
    owner_artifacts = owner_artifacts(vehicle, party)

    selected_ids =
      claims
      |> Enum.map(& &1.artifact_id)
      |> Kernel.++(Enum.map(photos, & &1.artifact_id))
      |> Kernel.++(participation_artifact_ids(participations))
      |> Kernel.++(Enum.map(owner_artifacts, & &1.id))
      |> Kernel.++([stewardship.proof_artifact_id])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    artifacts = fetch_artifacts(selected_ids)

    own_ids =
      owner_artifacts
      |> Enum.map(& &1.id)
      |> Kernel.++(
        photos
        |> Enum.filter(&(&1.author_user_id == user.id))
        |> Enum.map(& &1.artifact_id)
      )
      |> Kernel.++(own_participation_artifact_ids(participations, user.id))
      |> Kernel.++([stewardship.proof_artifact_id])
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    original_artifacts =
      Enum.filter(artifacts, &(&1.storage_ref && MapSet.member?(own_ids, &1.id)))

    with {:ok, files} <- fetch_originals(original_artifacts) do
      archive_paths = Map.new(files, fn {artifact, path, _bytes} -> {artifact.id, path} end)

      zip_files =
        Enum.map(files, fn {_artifact, path, bytes} -> {String.to_charlist(path), bytes} end)

      {:ok, zip_files, archive_paths, artifacts, claims, photos, participations}
    end
  end

  defp record_claims(vehicle, party) do
    Repo.all(
      from(claim in Claim,
        where:
          claim.vehicle_id == ^vehicle.id and
            ((claim.state == :admitted and claim.visibility == :public) or
               claim.asserted_by_party_id == ^party.id),
        order_by: [asc: claim.inserted_at],
        preload: [
          :artifact,
          :asserted_by_party,
          :ratified_by_party,
          :retracted_by_party
        ]
      )
    )
  end

  defp owner_artifacts(vehicle, party) do
    Repo.all(
      from(artifact in Artifact,
        where: artifact.vehicle_id == ^vehicle.id and artifact.source_party_id == ^party.id
      )
    )
  end

  defp fetch_artifacts([]), do: []

  defp fetch_artifacts(ids) do
    Repo.all(
      from(artifact in Artifact,
        where: artifact.id in ^ids,
        order_by: [asc: artifact.acquired_at, asc: artifact.inserted_at],
        preload: [:source_party]
      )
    )
  end

  defp participation_artifact_ids(participations) do
    participations
    |> Enum.flat_map(& &1.attachments)
    |> Enum.map(& &1.artifact_id)
  end

  defp own_participation_artifact_ids(participations, user_id) do
    participations
    |> Enum.filter(&(&1.user_id == user_id))
    |> participation_artifact_ids()
  end

  defp fetch_originals(artifacts) do
    Enum.reduce_while(artifacts, {:ok, []}, fn artifact, {:ok, files} ->
      case Storage.fetch(artifact.storage_ref) do
        {:ok, bytes} ->
          path = original_path(artifact)
          {:cont, {:ok, [{artifact, path, bytes} | files]}}

        {:error, reason} ->
          {:halt, {:error, {:storage, artifact.id, reason}}}
      end
    end)
    |> case do
      {:ok, files} -> {:ok, Enum.reverse(files)}
      error -> error
    end
  end

  defp original_path(artifact) do
    filename = artifact.metadata["filename"] || artifact.storage_ref || "upload"

    safe_name =
      filename
      |> to_string()
      |> Path.basename()
      |> String.replace(~r/[^[:alnum:]._-]+/u, "-")
      |> String.trim("-.")
      |> case do
        "" -> "upload"
        name -> name
      end

    "originals/#{artifact.id}-#{safe_name}"
  end

  defp vehicle_map(vehicle) do
    %{
      "public_id" => vehicle.public_id,
      "identity_kind" => to_string(vehicle.identity_kind),
      "identity_key" => vehicle.identity_key,
      "input" => vehicle.input,
      "santo_version" => vehicle.santo_version,
      "decode_snapshot" => vehicle.decode_snapshot,
      "factory_facts" => vehicle.facts,
      "current_state" => vehicle.current_state,
      "created_at" => iso(vehicle.inserted_at),
      "updated_at" => iso(vehicle.updated_at)
    }
  end

  defp stewardship_map(stewardship, party, archive_paths) do
    %{
      "handle" => party.name,
      "status" => to_string(stewardship.status),
      "proof_artifact_id" => stewardship.proof_artifact_id,
      "proof_archive_path" => archive_paths[stewardship.proof_artifact_id],
      "decided_at" => iso(stewardship.decided_at),
      "created_at" => iso(stewardship.inserted_at)
    }
  end

  defp story_map(nil), do: nil

  defp story_map(story) do
    %{
      "tagline" => story.tagline,
      "body" => story.body,
      "author" => story.author_user.handle,
      "created_at" => iso(story.inserted_at),
      "updated_at" => iso(story.updated_at)
    }
  end

  defp link_map(link) do
    %{
      "url" => link.url,
      "label" => link.label,
      "kind" => to_string(link.kind),
      "position" => link.position
    }
  end

  defp claim_map(claim) do
    %{
      "id" => claim.id,
      "entry_ref" => claim.entry_ref,
      "predicate" => claim.predicate,
      "value" => claim.value,
      "scope" => to_string(claim.scope_kind),
      "date" => iso(claim.scope_date),
      "state" => to_string(claim.state),
      "visibility" => to_string(claim.visibility),
      "method" => to_string(claim.method),
      "method_meta" => claim.method_meta,
      "asserted_by" => party_name(claim.asserted_by_party),
      "ratified_by" => party_name(claim.ratified_by_party),
      "ratified_at" => iso(claim.ratified_at),
      "retracted_by" => party_name(claim.retracted_by_party),
      "retracted_at" => iso(claim.retracted_at),
      "artifact_id" => claim.artifact_id,
      "content_hash" => claim.content_hash,
      "recorded_at" => iso(claim.inserted_at)
    }
  end

  defp photo_map(%VehiclePhoto{} = photo, archive_paths) do
    %{
      "id" => photo.id,
      "entry_ref" => photo.entry_ref,
      "date" => iso(photo.entry_date),
      "artifact_id" => photo.artifact_id,
      "archive_path" => archive_paths[photo.artifact_id],
      "author" => photo.author_user.handle,
      "alt_text" => photo.alt_text,
      "position" => photo.position,
      "hero" => photo.hero,
      "visibility" => to_string(photo.visibility)
    }
  end

  defp participation_map(%EventParticipation{} = participation, archive_paths) do
    %{
      "id" => participation.id,
      "entry_ref" => participation.entry_ref,
      "visibility" => to_string(participation.visibility),
      "author" => participation.user.handle,
      "journal" => participation.journal,
      "tags" => participation.tags,
      "details" => Enum.map(participation.details, &%{"label" => &1.label, "value" => &1.value}),
      "event" => event_map(participation.event),
      "attachments" =>
        Enum.map(participation.attachments, fn attachment ->
          %{
            "id" => attachment.id,
            "label" => attachment.label,
            "kind" => to_string(attachment.kind),
            "position" => attachment.position,
            "url" => attachment.url,
            "artifact_id" => attachment.artifact_id,
            "archive_path" => archive_paths[attachment.artifact_id]
          }
        end)
    }
  end

  defp event_map(event) do
    %{
      "public_id" => event.public_id,
      "title" => event.title,
      "starts_on" => iso(event.starts_on),
      "ends_on" => iso(event.ends_on),
      "starts_at" => iso(event.starts_at),
      "ends_at" => iso(event.ends_at),
      "timezone" => event.timezone,
      "place" => event.place_text,
      "description" => event.description,
      "tags" => event.tags,
      "source_status" => to_string(event.source_status)
    }
  end

  defp entry_maps(claims, photos, participations) do
    claims_by_ref = claims |> Enum.reject(&is_nil(&1.entry_ref)) |> Enum.group_by(& &1.entry_ref)
    photos_by_ref = Enum.group_by(photos, & &1.entry_ref)
    participations_by_ref = Map.new(participations, &{&1.entry_ref, &1})

    refs =
      Map.keys(claims_by_ref) ++ Map.keys(photos_by_ref) ++ Map.keys(participations_by_ref)

    refs
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.map(fn ref ->
      entry_claims = Map.get(claims_by_ref, ref, [])
      entry_photos = Map.get(photos_by_ref, ref, [])
      participation = Map.get(participations_by_ref, ref)

      %{
        "entry_ref" => ref,
        "date" => iso(entry_date(entry_claims, entry_photos, participation)),
        "visibility" => entry_visibility(entry_claims, entry_photos, participation),
        "claim_ids" => Enum.map(entry_claims, & &1.id),
        "photo_ids" => Enum.map(entry_photos, & &1.id),
        "event_participation_id" => participation && participation.id
      }
    end)
    |> Enum.sort_by(&(&1["date"] || ""), :desc)
  end

  defp entry_date([%Claim{scope_date: date} | _rest], _photos, _participation), do: date
  defp entry_date([], [%VehiclePhoto{entry_date: date} | _rest], _participation), do: date

  defp entry_date([], [], %EventParticipation{event: event}), do: event.starts_on
  defp entry_date([], [], nil), do: nil

  defp entry_visibility(claims, photos, participation) do
    private? =
      Enum.any?(claims, &(&1.visibility == :private)) or
        Enum.any?(photos, &(&1.visibility == :private)) or
        (participation && participation.visibility == :private)

    if private?, do: "private", else: "public"
  end

  defp artifact_map(artifact, archive_paths) do
    %{
      "id" => artifact.id,
      "entry_ref" => artifact.entry_ref,
      "kind" => to_string(artifact.kind),
      "sha256" => artifact.sha256,
      "mime" => artifact.mime,
      "filename" => artifact.metadata["filename"],
      "archive_path" => archive_paths[artifact.id],
      "source" => party_name(artifact.source_party),
      "source_url" => artifact.source_url,
      "acquired_at" => iso(artifact.acquired_at),
      "visibility" => to_string(artifact.visibility),
      "metadata" => artifact.metadata,
      "payload" => artifact.payload
    }
  end

  defp party_name(%Party{name: name}), do: name
  defp party_name(nil), do: nil

  defp iso(nil), do: nil
  defp iso(%Date{} = value), do: Date.to_iso8601(value)
  defp iso(%Time{} = value), do: Time.to_iso8601(value)
  defp iso(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp iso(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)

  defp readme do
    """
    Vin Santo vehicle record export
    ===============================

    record.json uses the vin_santo.vehicle_record format, version 1. It is
    UTF-8 JSON and contains the car identity, projections, story, links,
    grouped entries, underlying claims, photos, event accounts, and artifact
    metadata visible to this steward. Private contributions authored by the
    requesting steward are included and retain visibility = "private".

    originals/ contains the original bytes supplied by the requesting steward,
    named by artifact id and original filename. An artifact with no archive_path
    is a source pointer or third-party record described in JSON but not copied
    into this archive.

    Event detail labels and values are owner-defined text. They are displayable
    and searchable, but the format does not promise that they are comparable or
    safe to compute.
    """
  end
end
