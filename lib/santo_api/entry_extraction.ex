defmodule SantoApi.EntryExtraction do
  @moduledoc """
  Natural-language intake for an existing car's logbook.

  The model fills a fixed draft schema. It never writes, computes a price, or
  decides which claims enter the ledger; `SantoApi.Logbook.EntryDraft` performs
  that deterministic half and the owner reviews its ordinary composer fields
  before saving.
  """

  require Logger

  @endpoint "https://api.anthropic.com/v1/messages"
  @api_version "2023-06-01"

  @system_prompt """
  Extract one car-log update from the owner's sentence into the supplied schema.
  Use only what the owner stated; never guess a number, shop, venue, or outcome.
  Classify the update as fuel, service, modification, outing, or note. Resolve
  relative dates against the current date supplied by the user message. Fuel
  volume and prices must remain decimal strings exactly as stated. Currency is
  the three-letter ISO code implied by the owner's amount. `total_price` is the
  whole amount paid; `unit_price` is price per fuel unit. Do not calculate one
  from the other. `odometer` is a non-negative integer reading in miles.
  For an outing, kind is autocross, track, show, drive, or other. Put the owner's
  useful narrative in summary; use note only when the update does not fit another
  type. Unstated optional fields are null.
  """

  @nullable_string %{"anyOf" => [%{"type" => "string"}, %{"type" => "null"}]}
  @nullable_integer %{"anyOf" => [%{"type" => "integer"}, %{"type" => "null"}]}

  @schema %{
    "type" => "object",
    "properties" => %{
      "mode" => %{"type" => "string", "enum" => ~w(fuel service modification outing note)},
      "date" => @nullable_string,
      "odometer" => @nullable_integer,
      "volume" => @nullable_string,
      "unit" => %{
        "anyOf" => [%{"type" => "string", "enum" => ~w(gal l)}, %{"type" => "null"}]
      },
      "total_price" => @nullable_string,
      "unit_price" => @nullable_string,
      "currency" => @nullable_string,
      "summary" => @nullable_string,
      "performer" => @nullable_string,
      "area" => @nullable_string,
      "outing_kind" => %{
        "anyOf" => [
          %{"type" => "string", "enum" => ~w(autocross track show drive other)},
          %{"type" => "null"}
        ]
      },
      "venue" => @nullable_string,
      "result" => @nullable_string,
      "note" => @nullable_string
    },
    "required" => ~w(
      mode date odometer volume unit total_price unit_price currency summary
      performer area outing_kind venue result note
    ),
    "additionalProperties" => false
  }

  @doc "Extract one sentence into a candidate entry draft."
  def extract(sentence, today \\ Date.utc_today()) when is_binary(sentence) do
    with {:ok, api_key} <- api_key(),
         {:ok, body} <- request(api_key, sentence, today),
         {:ok, fields} <- read_response(body) do
      {:ok, reading(fields)}
    end
  end

  defp request(api_key, sentence, today) do
    options =
      [
        url: @endpoint,
        method: :post,
        retry: false,
        headers: [
          {"x-api-key", api_key},
          {"anthropic-version", @api_version}
        ],
        json: %{
          model: model(),
          max_tokens: 1_200,
          system: @system_prompt,
          output_config: %{
            effort: "low",
            format: %{type: "json_schema", schema: @schema}
          },
          messages: [
            %{
              role: "user",
              content: "Current date: #{Date.to_iso8601(today)}\nUpdate: #{sentence}"
            }
          ]
        }
      ]
      |> Keyword.merge(Application.get_env(:santo_api, :entry_extraction_req_options, []))

    case Req.request(options) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("entry extraction request failed: HTTP #{status}")
        {:error, :unavailable}

      {:error, reason} ->
        Logger.warning("entry extraction request failed: #{inspect(reason)}")
        {:error, :unavailable}
    end
  end

  defp read_response(%{"stop_reason" => "refusal"}), do: {:error, :refusal}

  defp read_response(%{"content" => content}) when is_list(content) do
    with %{"text" => text} <- Enum.find(content, &(&1["type"] == "text")),
         {:ok, fields} when is_map(fields) <- Jason.decode(text) do
      {:ok, fields}
    else
      _unreadable -> {:error, :unreadable}
    end
  end

  defp read_response(_body), do: {:error, :unreadable}

  defp reading(fields) do
    %{
      mode: mode(fields["mode"]),
      date: date(fields["date"]),
      odometer: non_negative_integer(fields["odometer"]),
      volume: presence(fields["volume"]),
      unit: unit(fields["unit"]),
      total_price: presence(fields["total_price"]),
      unit_price: presence(fields["unit_price"]),
      currency: presence(fields["currency"]),
      summary: presence(fields["summary"]),
      performer: presence(fields["performer"]),
      area: presence(fields["area"]),
      outing_kind: outing_kind(fields["outing_kind"]),
      venue: presence(fields["venue"]),
      result: presence(fields["result"]),
      note: presence(fields["note"])
    }
  end

  defp mode(value) when value in ~w(fuel service modification outing note),
    do: String.to_existing_atom(value)

  defp mode(_unknown), do: :note

  defp date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp date(_value), do: nil

  defp non_negative_integer(value) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_value), do: nil

  defp unit(value) when value in ~w(gal l), do: value
  defp unit(_value), do: nil

  defp outing_kind(value) when value in ~w(autocross track show drive other), do: value
  defp outing_kind(_value), do: nil

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp presence(_value), do: nil

  defp model, do: Keyword.fetch!(config(), :model)

  defp api_key do
    case Keyword.get(config(), :api_key) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _absent -> {:error, :not_configured}
    end
  end

  defp config, do: Application.get_env(:santo_api, :extraction, [])
end
