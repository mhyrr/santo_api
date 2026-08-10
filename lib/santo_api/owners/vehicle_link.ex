defmodule SantoApi.Owners.VehicleLink do
  @moduledoc """
  A pointer to where a car lives elsewhere — a build thread, a YouTube channel,
  an Instagram account.

  Links are curation, not evidence (owner_surface §2, §7b.1 decision 8):
  presentation layer only, with no contact with the ledger. No claim, no
  artifact, no `content_hash` — a link is never hashed because it is never
  asserted as fact. That is also what makes it, unlike a claim, safely mutable
  and deletable: there is no attestation seam here to protect.

  A link carries no date of its own and never sits on the timeline spine — it
  lives in its own section of the page (§7b.1). If a link is ever promoted to
  evidence (a dated video corroborating a build), that is a claim-writing
  change on a different table, not an edit to this one (§7b.5, open).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SantoApi.Registry.Vehicle

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @label_max_length 120

  schema "vehicle_links" do
    belongs_to :vehicle, Vehicle

    field :url, :string
    field :label, :string
    field :position, :integer, default: 0
    field :kind, Ecto.Enum, values: [:other, :build_thread], default: :other

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Casts and validates `url`, `label`, `position`.

  `url` must parse to an `http`/`https` URI with a host — narrow on purpose,
  since this field renders as a clickable card and a `javascript:` or
  schemeless string is either dead or dangerous there.
  """
  def changeset(link, attrs) do
    link
    |> cast(attrs, [:url, :label, :position])
    |> validate_required([:url])
    |> validate_length(:label, max: @label_max_length)
    |> validate_change(:url, &validate_url/2)
    |> unique_constraint(:vehicle_id,
      name: :vehicle_links_one_build_thread_per_vehicle_index
    )
  end

  defp validate_url(:url, url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        []

      _invalid ->
        [url: "must be a valid http or https URL"]
    end
  end

  @doc """
  Classifies a link's URL for rendering (owner_surface §9.3's per-platform
  honesty table). YouTube gets a real embed — `{:youtube, video_id}` — because
  its oEmbed is open and keyless. Everything else, including Instagram, comes
  back `:other` and renders as a bare link card: Instagram's oEmbed needs a
  Meta app and a review we haven't done, so the UI does not pretend to a
  richness we lack the rights to.
  """
  def provider(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host, path: path} when is_binary(host) -> classify(strip_www(host), path, url)
      _invalid -> :other
    end
  end

  def provider(_url), do: :other

  defp strip_www(host), do: String.replace_prefix(host, "www.", "")

  defp classify("youtube.com", path, url), do: classify_youtube(path, url)
  defp classify("m.youtube.com", path, url), do: classify_youtube(path, url)
  defp classify("youtu.be", path, _url), do: youtube_from_path_segment(path)
  defp classify(_host, _path, _url), do: :other

  defp classify_youtube("/watch", url) do
    case url |> URI.parse() |> Map.get(:query) do
      query when is_binary(query) ->
        case URI.decode_query(query) do
          %{"v" => id} when is_binary(id) and id != "" -> {:youtube, id}
          _no_id -> :other
        end

      nil ->
        :other
    end
  end

  defp classify_youtube("/shorts/" <> _rest = path, _url) do
    path |> String.trim_leading("/shorts/") |> youtube_id_or_other()
  end

  defp classify_youtube(_path, _url), do: :other

  defp youtube_from_path_segment(path) when is_binary(path) do
    path |> String.trim_leading("/") |> youtube_id_or_other()
  end

  defp youtube_from_path_segment(_path), do: :other

  defp youtube_id_or_other(segment) do
    case segment |> String.split("/") |> List.first() do
      id when is_binary(id) and id != "" -> {:youtube, id}
      _blank -> :other
    end
  end
end
