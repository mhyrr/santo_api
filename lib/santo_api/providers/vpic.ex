defmodule SantoApi.Providers.Vpic do
  @moduledoc """
  NHTSA vPIC provider for generic VIN-pattern specifications.

  vPIC data is manufacturer-submitted reference data. The acquisition
  preserves the complete response and its diagnostics; `facts/1` is the
  existing narrow interpreter retained until interpretation is split
  from transport.
  """

  @behaviour SantoApi.Providers.Provider

  alias SantoApi.Providers.{Acquisition, Request}

  @endpoint "https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValues/"

  @impl true
  def descriptor do
    %{
      id: :nhtsa_vpic,
      name: "NHTSA vPIC",
      capabilities: [:generic_specifications],
      identity_kinds: [:vin],
      required_selectors: [],
      fulfillment: :sync_api,
      billing: :free,
      access_class: :open_data,
      documentation_url: "https://vpic.nhtsa.dot.gov/api/"
    }
  end

  @impl true
  def supports?(%Request{capability: :generic_specifications, identity: {:vin, vin}})
      when is_binary(vin) and vin != "",
      do: :ok

  def supports?(%Request{capability: capability})
      when capability != :generic_specifications,
      do: {:error, {:unsupported_capability, capability}}

  def supports?(%Request{} = request),
    do: {:error, {:unsupported_identity, Request.identity_kind(request)}}

  @impl true
  def acquire(%Request{identity: {:vin, vin}} = request) do
    with :ok <- supports?(request),
         {:ok, %{payload: payload, url: url}} <- fetch(vin) do
      {:ok,
       %Acquisition{
         acquisition_id: Ecto.UUID.generate(),
         provider: descriptor().id,
         capability: request.capability,
         coverage: coverage(payload),
         payload: payload,
         source_url: url,
         media_type: "application/json",
         acquired_at: DateTime.utc_now(),
         rights_profile: "nhtsa-vpic-open-data-v1",
         diagnostics: diagnostics(payload)
       }}
    end
  end

  def acquire(%Request{} = request), do: supports?(request)

  def fetch(vin) do
    url = @endpoint <> URI.encode(vin, &URI.char_unreserved?/1) <> "?format=json"

    options =
      [url: url, retry: false]
      |> Keyword.merge(Application.get_env(:santo_api, :vpic_req_options, []))

    case Req.request(options) do
      {:ok, %Req.Response{status: 200, body: %{"Results" => [values]}}} ->
        {:ok, %{payload: values, url: url}}

      {:ok, %Req.Response{status: 200, body: body}} ->
        {:error, {:unexpected_body, body}}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def facts(%{"ErrorCode" => "0"} = values) do
    [
      {"identity.marque", downcased(values["Make"])},
      {"identity.model", model_value(values["Model"])},
      {"identity.model_year", year(values["ModelYear"])}
    ]
    |> Enum.reject(fn {_predicate, value} -> is_nil(value) end)
  end

  def facts(_values), do: []

  defp coverage(%{"ErrorCode" => "0"}), do: :complete
  defp coverage(values) when map_size(values) > 0, do: :partial
  defp coverage(_values), do: :none

  defp diagnostics(values) do
    %{
      "error_code" => values["ErrorCode"],
      "error_text" => values["ErrorText"],
      "suggested_vin" => values["SuggestedVIN"],
      "possible_values" => values["PossibleValues"],
      "additional_error_text" => values["AdditionalErrorText"]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp downcased(value) when is_binary(value) and value != "", do: String.downcase(value)
  defp downcased(_value), do: nil

  defp model_value(value) do
    case slug(value) do
      nil -> nil
      code -> %{"code" => code, "label" => nil}
    end
  end

  defp slug(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
    |> case do
      "" -> nil
      slug -> slug
    end
  end

  defp slug(_value), do: nil

  defp year(value) when is_binary(value) do
    case Integer.parse(value) do
      {year, ""} -> year
      _ -> nil
    end
  end

  defp year(_value), do: nil
end
