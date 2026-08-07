defmodule SantoApi.Nhtsa.CorpusTest do
  use SantoApi.DataCase, async: false

  alias SantoApi.Nhtsa.Corpus
  alias SantoApi.Nhtsa.Corpus.{Record, Release}
  alias SantoApi.Providers.{Acquisition, Nhtsa, Request, Selector}
  alias SantoApi.Storage

  @recalls Path.expand("../fixtures/nhtsa/recalls.txt", __DIR__)
  @bulletins Path.expand("../fixtures/nhtsa/technical_bulletins.txt", __DIR__)
  @recall_url "https://static.nhtsa.gov/odi/ffdd/rcl/FLAT_RCL_PRE_2010.zip"
  @bulletin_url "https://static.nhtsa.gov/odi/ffdd/tsbs/TSBS_RECEIVED_2020-2024.zip"

  test "imports source-shaped recall rows, preserves the release, and reports malformed rows" do
    archive = archive(@recalls, "FLAT_RCL_PRE_2010.txt")

    assert {:ok, :imported, release} =
             Corpus.import_archive(
               release_attrs(:recall_campaigns, "pre_2010", "release-1", archive)
             )

    assert release.status == :imported
    assert release.coverage == :partial
    assert release.record_count == 2
    assert release.malformed_row_count == 1
    assert release.diagnostics["skipped_unindexable_rows"] == 1
    assert [%{"source_row" => 4, "reason" => reason}] = release.diagnostics["malformed_rows"]
    assert reason =~ "field_count"
    assert Storage.exists?(release.storage_ref)

    assert {:ok, result} = Corpus.lookup(:recall_campaigns, cayman_selector())
    assert result.coverage == :partial
    assert Enum.map(result.records, & &1.payload["identifier"]) == ["08V123000", "09V456000"]
  end

  test "the same release is idempotent while a distinct release is preserved" do
    archive = archive(@recalls, "FLAT_RCL_PRE_2010.txt")
    attrs = release_attrs(:recall_campaigns, "pre_2010", "release-1", archive)

    assert {:ok, :imported, first} = Corpus.import_archive(attrs)
    assert {:ok, :existing, replay} = Corpus.import_archive(attrs)
    assert replay.id == first.id
    assert Repo.aggregate(Release, :count) == 1
    assert Repo.aggregate(Record, :count) == 2

    assert {:ok, :imported, second} =
             attrs
             |> Map.put(:release_key, "release-2")
             |> Map.put(:released_on, ~D[2026-08-07])
             |> Corpus.import_archive()

    refute second.id == first.id
    assert Repo.aggregate(Release, :count) == 2
    assert Repo.aggregate(Record, :count) == 4
    assert [%Release{id: latest_id}] = Corpus.latest_releases(:recall_campaigns)
    assert latest_id == second.id
  end

  test "concurrent imports of one release converge on one preserved snapshot" do
    archive = archive(@recalls, "FLAT_RCL_PRE_2010.txt")
    attrs = release_attrs(:recall_campaigns, "pre_2010", "concurrent-release", archive)
    supervisor = start_supervised!(Task.Supervisor)

    results =
      for _ <- 1..2 do
        Task.Supervisor.async_nolink(supervisor, fn -> Corpus.import_archive(attrs) end)
      end
      |> Enum.map(&Task.await(&1, 5_000))

    assert Enum.sort(Enum.map(results, fn {:ok, disposition, _release} -> disposition end)) ==
             [:existing, :imported]

    assert Repo.aggregate(Release, :count) == 1
    assert Repo.aggregate(Record, :count) == 2
  end

  test "imports and matches manufacturer communications without fetching PDFs" do
    body = @bulletins |> File.read!() |> drop_malformed_fixture_row()
    archive = archive_body(body, "TSBS_RECEIVED_2020-2024.txt")

    assert {:ok, :imported, release} =
             Corpus.import_archive(
               release_attrs(:technical_bulletins, "received_2020_2024", "release-1", archive)
             )

    assert release.coverage == :complete
    assert release.record_count == 3

    assert {:ok, result} = Corpus.lookup(:technical_bulletins, cayman_selector())
    assert result.coverage == :complete
    assert Enum.map(result.records, & &1.payload["identifier"]) == ["TI-24-01", "TI-24-02"]

    assert Enum.all?(result.records, fn record ->
             String.starts_with?(
               record.payload["document_url"],
               "https://static.nhtsa.gov/odi/tsbs/2024/MC-"
             )
           end)
  end

  test "refresh downloads with Req and imports the returned official release" do
    archive = archive_body(drop_malformed_fixture_row(File.read!(@recalls)), "FLAT_RCL.txt")

    Req.Test.stub(SantoApi.NhtsaCorpus, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/zip")
      |> Plug.Conn.put_resp_header("last-modified", "Fri, 07 Aug 2026 10:00:00 GMT")
      |> Plug.Conn.send_resp(200, archive)
    end)

    assert {:ok, :imported, release} =
             Corpus.refresh_source(%{
               dataset: :recall_campaigns,
               source_key: "pre_2010",
               url: @recall_url
             })

    assert release.release_key == "Fri, 07 Aug 2026 10:00:00 GMT"
    assert release.released_on == ~D[2026-08-07]
    assert release.source_url == @recall_url
    assert release.rights_profile == "nhtsa-open-data-v1"
  end

  test "lookup distinguishes unavailable corpus from a legitimate no match" do
    assert {:error, :corpus_unavailable} =
             Corpus.lookup(:technical_bulletins, cayman_selector())

    archive = archive_body(drop_malformed_fixture_row(File.read!(@bulletins)), "TSBS.txt")

    assert {:ok, :imported, _release} =
             Corpus.import_archive(
               release_attrs(:technical_bulletins, "received_2020_2024", "release-1", archive)
             )

    ferrari = %Selector{
      marque: "ferrari",
      model: %{"code" => "488", "label" => nil},
      model_year: 2015
    }

    assert {:ok, %{coverage: :complete, records: []}} =
             Corpus.lookup(:technical_bulletins, ferrari)

    assert {:ok, request} =
             Request.new(:technical_bulletins, {:vin, "ZFF75VFA8F0205055"}, ferrari)

    assert {:ok, %Acquisition{coverage: :none} = acquisition} = Nhtsa.acquire(request)
    assert acquisition.payload["records"] == []
    assert [%{"release_key" => "release-1"}] = acquisition.payload["corpus_releases"]
    assert acquisition.rights_profile == "nhtsa-open-data-v1"
  end

  test "provider snapshots selectors, grouped records, release identity, and official links" do
    body = @recalls |> File.read!() |> drop_malformed_fixture_row()

    assert {:ok, :imported, release} =
             Corpus.import_archive(
               release_attrs(
                 :recall_campaigns,
                 "pre_2010",
                 "provider-release",
                 archive_body(body, "FLAT_RCL.txt")
               )
             )

    assert {:ok, request} =
             Request.new(:recall_campaigns, {:vin, "WP0AB29827U782968"}, cayman_selector())

    assert {:ok, %Acquisition{coverage: :complete} = acquisition} = Nhtsa.acquire(request)
    assert acquisition.payload["selectors"] == Selector.to_map(cayman_selector())
    assert acquisition.payload["applicability_label"] =~ "vehicle completion unknown"

    assert [%{"id" => release_id, "release_key" => "provider-release"}] =
             acquisition.payload["corpus_releases"]

    assert release_id == release.id

    assert Enum.map(acquisition.payload["records"], & &1["identifier"]) ==
             ["08V123000", "09V456000"]

    assert Enum.all?(acquisition.payload["records"], fn record ->
             record["corpus_release"]["id"] == release.id and
               String.starts_with?(record["source_url"], "https://api.nhtsa.gov/recalls/")
           end)
  end

  defp release_attrs(dataset, source_key, release_key, body) do
    %{
      dataset: dataset,
      source_key: source_key,
      release_key: release_key,
      released_on: ~D[2026-08-06],
      source_url: if(dataset == :recall_campaigns, do: @recall_url, else: @bulletin_url),
      acquired_at: ~U[2026-08-06 12:00:00Z],
      media_type: "application/zip",
      rights_profile: "nhtsa-open-data-v1",
      body: body
    }
  end

  defp cayman_selector do
    %Selector{
      marque: "porsche",
      model: %{"code" => "cayman", "label" => nil},
      model_year: 2007
    }
  end

  defp archive(path, name), do: path |> File.read!() |> archive_body(name)

  defp archive_body(body, name) do
    assert {:ok, {_filename, archive}} =
             :zip.create(~c"fixture.zip", [{String.to_charlist(name), body}], [:memory])

    archive
  end

  defp drop_malformed_fixture_row(body) do
    body
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "malformed\t"))
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end
end
