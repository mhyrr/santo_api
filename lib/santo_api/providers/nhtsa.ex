defmodule SantoApi.Providers.Nhtsa do
  @moduledoc """
  Local NHTSA population-reference provider for recalls and communications.

  VIN lookup never downloads bulk data. It queries the latest successfully
  imported local releases with a selector tuple resolved by the registry.
  """

  @behaviour SantoApi.Providers.Provider

  alias SantoApi.Nhtsa.Corpus
  alias SantoApi.Providers.{Acquisition, Request, Selector}

  @capabilities [:recall_campaigns, :technical_bulletins]
  @required_selectors Selector.fields()
  @source_url "https://www.nhtsa.gov/nhtsa-datasets-and-apis"

  @impl true
  def descriptor do
    %{
      id: :nhtsa_public_corpus,
      name: "NHTSA Public Corpus",
      capabilities: @capabilities,
      identity_kinds: [:vin],
      required_selectors: @required_selectors,
      fulfillment: :bulk_dataset,
      billing: :free,
      access_class: :open_data,
      documentation_url: @source_url
    }
  end

  @impl true
  def supports?(%Request{capability: capability, identity: {:vin, vin}})
      when capability in @capabilities and is_binary(vin) and vin != "",
      do: :ok

  def supports?(%Request{capability: capability}) when capability not in @capabilities,
    do: {:error, {:unsupported_capability, capability}}

  def supports?(%Request{} = request),
    do: {:error, {:unsupported_identity, Request.identity_kind(request)}}

  @impl true
  def acquire(%Request{} = request) do
    with :ok <- supports?(request),
         [] <- Selector.required_missing(request.selectors, @required_selectors),
         {:ok, result} <- Corpus.lookup(request.capability, request.selectors) do
      records = group_records(request.capability, result.records)
      coverage = coverage(result.coverage, records)

      {:ok,
       %Acquisition{
         acquisition_id: Ecto.UUID.generate(),
         provider: descriptor().id,
         capability: request.capability,
         coverage: coverage,
         payload: %{
           "selectors" => Selector.to_map(request.selectors),
           "corpus_releases" => Enum.map(result.releases, &release_payload/1),
           "records" => records,
           "applicability_label" => "model applicability; vehicle completion unknown"
         },
         source_url: @source_url,
         media_type: "application/json",
         acquired_at: DateTime.utc_now(),
         rights_profile: Corpus.rights_profile(),
         diagnostics: %{
           "release_count" => length(result.releases),
           "matched_source_rows" => length(result.records),
           "record_count" => length(records),
           "release_coverage" => to_string(result.coverage)
         }
       }}
    else
      missing when is_list(missing) and missing != [] ->
        {:pending, %{missing_selectors: missing}}

      {:error, _reason} = error ->
        error
    end
  end

  defp coverage(:partial, _records), do: :partial
  defp coverage(:complete, []), do: :none
  defp coverage(:complete, _records), do: :complete

  defp group_records(capability, records) do
    records
    |> Enum.group_by(&group_key(capability, &1.payload))
    |> Enum.map(fn {_key, grouped} -> grouped_record(grouped) end)
    |> Enum.sort_by(& &1["identifier"])
  end

  defp group_key(:recall_campaigns, payload), do: payload["identifier"]
  defp group_key(:technical_bulletins, payload), do: payload["nhtsa_id"]

  defp grouped_record([first | _rest] = records) do
    first.payload
    |> Map.put("applicability", records |> Enum.map(& &1.payload["applicability"]) |> Enum.uniq())
    |> Map.put(
      "components",
      records |> Enum.map(& &1.payload["component"]) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    )
    |> Map.put("corpus_release", release_payload(first.release))
  end

  defp release_payload(release) do
    %{
      "id" => release.id,
      "dataset" => release.dataset,
      "source_key" => release.source_key,
      "release_key" => release.release_key,
      "released_on" => Date.to_iso8601(release.released_on),
      "acquired_at" => DateTime.to_iso8601(release.acquired_at),
      "source_url" => release.source_url,
      "sha256" => release.sha256
    }
  end
end
