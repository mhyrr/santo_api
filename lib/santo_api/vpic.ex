defmodule SantoApi.Vpic do
  @moduledoc """
  NHTSA vPIC as an evidence source: fetch a DecodeVinValues snapshot and
  map it onto the claim vocabulary.

  Mapping is deliberately narrow — Make, Model, ModelYear — and values
  are normalized into the shapes santo emits, so
  `SantoApi.Registry.claim_comparison/1` compares like with like. A
  nonzero ErrorCode yields no facts: the snapshot is still evidence, but
  a decode vPIC itself flags is not a claim source.
  """

  @endpoint "https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValues/"

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
