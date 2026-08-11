defmodule SantoApi.OwnersExportTest do
  use SantoApi.DataCase, async: false

  import SantoApi.AccountsFixtures

  alias SantoApi.Accounts.Scope
  alias SantoApi.Events
  alias SantoApi.Owners
  alias SantoApi.Registry

  setup do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    user = user_fixture(%{handle: "archivedriver"})
    {:ok, _stewardship} = Owners.grant_stewardship(user, vehicle)

    %{vehicle: vehicle, user: user, scope: Scope.for_user(user)}
  end

  test "the ZIP documents the format and includes private entries plus original uploads", ctx do
    source_path = "priv/demo/media/cayman-autocross-paddock.jpg"

    {:ok, entry} =
      Owners.compose_entry(ctx.scope, ctx.vehicle, %{
        date: ~D[2026-08-10],
        visibility: :private,
        claims: [%{predicate: "event.note", value: %{"text" => "Not ready to share"}}],
        photos: [
          %{
            path: source_path,
            filename: "private-paddock.jpg",
            mime: "image/jpeg",
            alt_text: "Cayman in the paddock"
          }
        ]
      })

    {:ok, event_result} =
      Events.create_participation(ctx.scope, ctx.vehicle, %{
        event: %{
          title: "WDCR 2026 Event 2",
          starts_on: ~D[2026-04-19],
          place_text: "Summit Point Motorsports Park"
        },
        participation: %{
          journal: "A private account of the day.",
          visibility: :private,
          details: [%{label: "Best run", value: "44.182"}]
        },
        links: [
          %{label: "Course walk", kind: :video, url: "https://example.com/course-walk"}
        ]
      })

    assert {:ok, archive} = Owners.export_record(ctx.scope, ctx.vehicle)
    assert archive.filename == "vin-santo-#{ctx.vehicle.public_id}-record.zip"

    files = unzip(archive.body)
    assert Map.has_key?(files, "README.txt")
    assert files["README.txt"] =~ "vin_santo.vehicle_record"

    record = Jason.decode!(files["record.json"])
    assert record["format"] == "vin_santo.vehicle_record"
    assert record["version"] == 1
    assert record["vehicle"]["identity_key"] == "vin:WP0AB29827U782968"
    assert record["stewardship"]["handle"] == "archivedriver"

    private_claim = Enum.find(record["claims"], &(&1["id"] == hd(entry.claims).id))
    assert private_claim["visibility"] == "private"
    assert private_claim["value"]["text"] == "Not ready to share"

    [photo] = Enum.filter(record["photos"], &(&1["entry_ref"] == entry.entry_ref))
    assert photo["visibility"] == "private"
    assert photo["archive_path"] =~ ~r{^originals/[0-9a-f-]+-private-paddock\.jpg$}
    assert files[photo["archive_path"]] == File.read!(source_path)

    exported_event =
      Enum.find(record["events"], &(&1["id"] == event_result.participation.id))

    assert exported_event["visibility"] == "private"
    assert exported_event["details"] == [%{"label" => "Best run", "value" => "44.182"}]

    assert [%{"label" => "Course walk", "url" => "https://example.com/course-walk"}] =
             Enum.map(exported_event["attachments"], &Map.take(&1, ["label", "url"]))
  end

  test "a new steward's archive excludes the previous steward's private contribution", ctx do
    {:ok, previous} =
      Owners.compose_entry(ctx.scope, ctx.vehicle, %{
        date: ~D[2026-08-09],
        visibility: :private,
        claims: [%{predicate: "event.note", value: %{"text" => "Previous owner's note"}}]
      })

    stewardship = Owners.stewardship(ctx.scope, ctx.vehicle)
    {:ok, _revoked} = Owners.revoke_stewardship(stewardship, "car changed hands")

    next_user = user_fixture(%{handle: "archivebuyer"})
    {:ok, _stewardship} = Owners.grant_stewardship(next_user, ctx.vehicle)
    next_scope = Scope.for_user(next_user)

    assert {:ok, archive} = Owners.export_record(next_scope, ctx.vehicle)
    record = archive.body |> unzip() |> Map.fetch!("record.json") |> Jason.decode!()

    refute Enum.any?(record["claims"], &(&1["id"] == hd(previous.claims).id))
    refute Enum.any?(record["entries"], &(&1["entry_ref"] == previous.entry_ref))
  end

  test "public third-party evidence stays metadata rather than copied bytes", ctx do
    {:ok, artifact} =
      Registry.create_upload_artifact(%{
        vehicle_id: ctx.vehicle.id,
        path: "priv/demo/media/cayman-autocross-paddock.jpg",
        filename: "registry-source.jpg",
        mime: "image/jpeg",
        kind: :document
      })

    {:ok, claim} =
      Registry.propose_claim(ctx.vehicle, %{
        "predicate" => "event.note",
        "value" => %{"text" => "Documented by a public source"},
        "scope_date" => "2026-08-08",
        "entry_ref" => Registry.new_entry_ref(),
        "artifact_id" => artifact.id
      })

    {:ok, _admitted} = Registry.ratify_claim(claim.id)
    assert {:ok, archive} = Owners.export_record(ctx.scope, ctx.vehicle)

    files = unzip(archive.body)
    record = Jason.decode!(files["record.json"])
    exported = Enum.find(record["artifacts"], &(&1["id"] == artifact.id))

    assert exported["source"] == "Vin Santo"
    assert exported["archive_path"] == nil
    refute Enum.any?(Map.keys(files), &String.contains?(&1, artifact.id))
  end

  test "a signed-in stranger cannot build an archive", ctx do
    stranger = user_fixture(%{handle: "archiveoutsider"})

    assert {:error, :not_stewarded} =
             Owners.export_record(Scope.for_user(stranger), ctx.vehicle)
  end

  defp unzip(bytes) do
    assert {:ok, files} = :zip.extract(bytes, [:memory])
    Map.new(files, fn {name, body} -> {List.to_string(name), body} end)
  end
end
