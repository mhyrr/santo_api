defmodule SantoApi.Nhtsa.Corpus do
  @moduledoc """
  Preserved, locally indexed NHTSA bulk releases.

  Refreshing is independent of VIN lookup. A lookup reads only successfully
  imported releases, so transport and import failures can never masquerade as a
  legitimate no-record answer.
  """

  import Ecto.Query, warn: false

  alias SantoApi.Nhtsa.Corpus.{Importer, Record, Release}
  alias SantoApi.Providers.Selector
  alias SantoApi.{Repo, Storage}

  @rights_profile "nhtsa-open-data-v1"
  @datasets [:recall_campaigns, :technical_bulletins]

  @recall_sources [
    %{
      dataset: :recall_campaigns,
      source_key: "pre_2010",
      url: "https://static.nhtsa.gov/odi/ffdd/rcl/FLAT_RCL_PRE_2010.zip"
    },
    %{
      dataset: :recall_campaigns,
      source_key: "post_2010",
      url: "https://static.nhtsa.gov/odi/ffdd/rcl/FLAT_RCL_POST_2010.zip"
    }
  ]

  @bulletin_sources (for period <-
                           ~w(1995-1999 2000-2004 2005-2009 2010-2014 2015-2019 2020-2024 2025-2025 2025-2026) do
                       %{
                         dataset: :technical_bulletins,
                         source_key: "received_" <> String.replace(period, "-", "_"),
                         url: "https://static.nhtsa.gov/odi/ffdd/tsbs/TSBS_RECEIVED_#{period}.zip"
                       }
                     end)

  def datasets, do: @datasets
  def rights_profile, do: @rights_profile
  def sources(:recall_campaigns), do: @recall_sources
  def sources(:technical_bulletins), do: @bulletin_sources
  def sources(:all), do: @recall_sources ++ @bulletin_sources

  def refresh(dataset \\ :all)

  def refresh(dataset) when dataset in [:all | @datasets] do
    dataset
    |> sources()
    |> Enum.map(&refresh_source/1)
  end

  def refresh(_dataset), do: [{:error, :unknown_dataset}]

  def refresh_source(%{dataset: dataset, source_key: source_key, url: url})
      when dataset in @datasets and is_binary(source_key) and is_binary(url) do
    acquired_at = DateTime.utc_now()

    options =
      [url: url, retry: false, decode_body: false]
      |> Keyword.merge(Application.get_env(:santo_api, :nhtsa_corpus_req_options, []))

    case Req.request(options) do
      {:ok, %Req.Response{status: 200, body: body} = response} when is_binary(body) ->
        checksum = sha256(body)
        released_on = response_release_date(response, acquired_at)

        import_archive(%{
          dataset: dataset,
          source_key: source_key,
          release_key: response_release_key(response, checksum),
          released_on: released_on,
          source_url: url,
          acquired_at: acquired_at,
          media_type: response_media_type(response),
          rights_profile: @rights_profile,
          body: body
        })

      {:ok, %Req.Response{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def refresh_source(_source), do: {:error, :invalid_source}

  @doc """
  Preserve and import one source-shaped NHTSA ZIP release.

  The release key is source-assigned (normally HTTP `Last-Modified`). Replaying
  identical bytes for that key is idempotent; changing bytes under the same key
  is rejected instead of rewriting history.
  """
  def import_archive(attrs) when is_map(attrs) do
    with {:ok, normalized} <- validate_release_attrs(attrs),
         :ok <- Storage.put(normalized.storage_ref, normalized.body),
         {:ok, disposition, release} <- ensure_release(normalized) do
      case disposition do
        :existing -> {:ok, :existing, release}
        :import -> import_release(release, normalized.body)
      end
    end
  end

  def import_archive(_attrs), do: {:error, :invalid_release}

  @doc """
  Match a complete model-population selector against the latest successfully
  imported release for each source partition.
  """
  def lookup(dataset, %Selector{} = selector) when dataset in @datasets do
    with :ok <- require_lookup_selector(selector),
         releases when releases != [] <- latest_releases(dataset) do
      release_ids = Enum.map(releases, & &1.id)
      marque = normalize_lookup(selector.marque)
      model = normalize_lookup(selector.model["code"])

      records =
        Repo.all(
          from(r in Record,
            where:
              r.release_id in ^release_ids and r.model_year == ^selector.model_year and
                r.marque == ^marque and r.model == ^model,
            order_by: [asc: r.payload["identifier"], asc: r.source_row],
            preload: [:release]
          )
        )

      coverage = if Enum.any?(releases, &(&1.coverage == :partial)), do: :partial, else: :complete
      {:ok, %{coverage: coverage, releases: releases, records: records}}
    else
      [] -> {:error, :corpus_unavailable}
      {:error, _reason} = error -> error
    end
  end

  def lookup(_dataset, _selector), do: {:error, :invalid_selectors}

  def latest_releases(dataset) when dataset in @datasets do
    dataset = to_string(dataset)

    Repo.all(
      from(r in Release,
        where: r.dataset == ^dataset and r.status == :imported,
        order_by: [asc: r.source_key, desc: r.released_on, desc: r.acquired_at, desc: r.id]
      )
    )
    |> Enum.uniq_by(& &1.source_key)
  end

  def latest_releases(_dataset), do: []

  defp validate_release_attrs(attrs) do
    dataset = fetch(attrs, :dataset)
    source_key = fetch(attrs, :source_key)
    release_key = fetch(attrs, :release_key)
    released_on = fetch(attrs, :released_on)
    source_url = fetch(attrs, :source_url)
    acquired_at = fetch(attrs, :acquired_at)
    media_type = fetch(attrs, :media_type)
    rights_profile = fetch(attrs, :rights_profile)
    body = fetch(attrs, :body)

    cond do
      dataset not in @datasets ->
        {:error, :unknown_dataset}

      !nonempty?(source_key) or !nonempty?(release_key) ->
        {:error, :invalid_release_identity}

      !official_url?(source_url) ->
        {:error, :unofficial_source}

      !is_struct(released_on, Date) or !is_struct(acquired_at, DateTime) ->
        {:error, :invalid_release_date}

      !nonempty?(media_type) or !nonempty?(rights_profile) or !is_binary(body) ->
        {:error, :invalid_release_metadata}

      true ->
        checksum = sha256(body)

        {:ok,
         %{
           dataset: to_string(dataset),
           source_key: source_key,
           release_key: release_key,
           released_on: released_on,
           source_url: source_url,
           acquired_at: acquired_at,
           sha256: checksum,
           storage_ref: checksum <> ".zip",
           media_type: media_type,
           rights_profile: rights_profile,
           body: body
         }}
    end
  end

  defp ensure_release(attrs) do
    identity = [
      dataset: attrs.dataset,
      source_key: attrs.source_key,
      release_key: attrs.release_key
    ]

    case Repo.get_by(Release, identity) do
      %Release{} = release -> existing_release(release, attrs.sha256)
      nil -> insert_release(attrs)
    end
  end

  defp insert_release(attrs) do
    changeset =
      attrs
      |> Map.drop([:body])
      |> Map.put(:status, :importing)
      |> Release.create_changeset()

    case Repo.insert(changeset) do
      {:ok, release} ->
        {:ok, :import, release}

      {:error, changeset} ->
        identity = [
          dataset: attrs.dataset,
          source_key: attrs.source_key,
          release_key: attrs.release_key
        ]

        case Repo.get_by(Release, identity) do
          %Release{} = release -> existing_release(release, attrs.sha256)
          nil -> {:error, changeset}
        end
    end
  end

  defp existing_release(%Release{sha256: checksum} = release, checksum) do
    if release.status == :imported,
      do: {:ok, :existing, release},
      else: {:ok, :import, release}
  end

  defp existing_release(%Release{} = release, _checksum) do
    {:error, {:release_identity_collision, release.id}}
  end

  defp import_release(release, archive) do
    result =
      Repo.transaction(fn ->
        locked_release =
          Repo.one!(from(r in Release, where: r.id == ^release.id, lock: "FOR UPDATE"))

        if locked_release.status == :imported do
          {:existing, locked_release}
        else
          Repo.delete_all(from(r in Record, where: r.release_id == ^locked_release.id))

          insert_batch = fn batch -> insert_records(locked_release, batch) end

          case Importer.import_archive(
                 String.to_existing_atom(locked_release.dataset),
                 archive,
                 insert_batch
               ) do
            {:ok, stats} ->
              coverage = if stats.malformed_row_count > 0, do: :partial, else: :complete

              imported =
                locked_release
                |> Ecto.Changeset.change(
                  status: :imported,
                  coverage: coverage,
                  record_count: stats.record_count,
                  malformed_row_count: stats.malformed_row_count,
                  diagnostics: %{
                    "malformed_rows" => Enum.reverse(stats.malformed_rows),
                    "skipped_unindexable_rows" => stats.skipped_row_count
                  }
                )
                |> Repo.update!()

              {:imported, imported}

            {:error, reason} ->
              Repo.rollback(reason)
          end
        end
      end)

    case result do
      {:ok, {:imported, imported}} ->
        {:ok, :imported, imported}

      {:ok, {:existing, existing}} ->
        {:ok, :existing, existing}

      {:error, reason} ->
        failed = mark_failed(release.id, reason)

        {:error, {:import_failed, failed.id, reason}}
    end
  end

  defp mark_failed(release_id, reason) do
    Repo.transaction(fn ->
      release =
        Repo.one!(from(r in Release, where: r.id == ^release_id, lock: "FOR UPDATE"))

      if release.status == :imported do
        release
      else
        release
        |> Ecto.Changeset.change(
          status: :failed,
          coverage: nil,
          diagnostics: %{"import_error" => inspect(reason, limit: 20)}
        )
        |> Repo.update!()
      end
    end)
    |> case do
      {:ok, release} -> release
      {:error, failure} -> raise "could not record corpus import failure: #{inspect(failure)}"
    end
  end

  defp insert_records(release, batch) do
    now = DateTime.utc_now()

    with {:ok, rows} <- validate_records(release, batch, now) do
      {_count, _returned} = Repo.insert_all(Record, rows)
      :ok
    end
  end

  defp validate_records(release, batch, now) do
    Enum.reduce_while(batch, {:ok, []}, fn attrs, {:ok, rows} ->
      changeset = Record.create_changeset(release, attrs)

      if changeset.valid? do
        record = Ecto.Changeset.apply_changes(changeset)

        row = %{
          id: Ecto.UUID.generate(),
          release_id: release.id,
          source_row: record.source_row,
          record_key: record.record_key,
          marque: record.marque,
          model: record.model,
          model_year: record.model_year,
          payload: record.payload,
          inserted_at: now,
          updated_at: now
        }

        {:cont, {:ok, [row | rows]}}
      else
        {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      {:error, _reason} = error -> error
    end
  end

  defp require_lookup_selector(selector) do
    case Selector.required_missing(selector, Selector.fields()) do
      [] -> :ok
      missing -> {:error, {:missing_selectors, missing}}
    end
  end

  defp response_release_key(response, checksum) do
    response
    |> Req.Response.get_header("last-modified")
    |> List.first()
    |> case do
      nil -> checksum
      header -> header
    end
  end

  defp response_release_date(response, acquired_at) do
    response
    |> Req.Response.get_header("last-modified")
    |> List.first()
    |> parse_http_date()
    |> case do
      {:ok, date} -> date
      :error -> DateTime.to_date(acquired_at)
    end
  end

  defp response_media_type(response) do
    response
    |> Req.Response.get_header("content-type")
    |> List.first()
    |> case do
      nil -> "application/zip"
      content_type -> content_type |> String.split(";", parts: 2) |> hd()
    end
  end

  defp parse_http_date(nil), do: :error

  defp parse_http_date(value) do
    case :httpd_util.convert_request_date(String.to_charlist(value)) do
      {{year, month, day}, _time} -> Date.new(year, month, day)
      _invalid -> :error
    end
  rescue
    _invalid -> :error
  end

  defp official_url?(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: "https", host: host}}
      when host in ["nhtsa.gov", "www.nhtsa.gov", "api.nhtsa.gov", "static.nhtsa.gov"] ->
        true

      _other ->
        false
    end
  end

  defp official_url?(_url), do: false

  defp normalize_lookup(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
  end

  defp fetch(attrs, key), do: Map.get(attrs, key, Map.get(attrs, to_string(key)))
  defp nonempty?(value), do: is_binary(value) and String.trim(value) != ""

  defp sha256(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end
end
