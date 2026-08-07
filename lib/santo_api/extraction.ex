defmodule SantoApi.Extraction do
  @moduledoc """
  The one-box extractor (owner_surface §7b): a sentence in, candidate vehicle
  facts out. The project's first hosted LLM call.

  Doctrine holds — the LLM extracts, the ledger computes. The model's only
  job is to fill a fixed schema from the owner's words; everything after the
  parse is deterministic: `claims/1` maps the reading onto the closed
  vocabulary, validation is `Vocabulary.validate/2`, and nothing here touches
  the ledger. The typed sentence itself is stored as the artifact by the
  origination path, so a better extractor can re-run against the same bytes.

  Failure is a designed state, not an exception: any error — no API key, a
  transport failure, a refusal — comes back as `{:error, reason}` and the
  flow renders the read-back screen with empty lines (§7b.1 decision 4).
  There is no dead end, so nothing here raises.

  The request uses structured outputs (`output_config.format`) so a parsed
  response is guaranteed to match the schema — the read-back never has to
  defend against free-form model prose.
  """

  require Logger

  @endpoint "https://api.anthropic.com/v1/messages"
  @api_version "2023-06-01"

  # The model never invents: absent means null, and the read-back shows an
  # empty line the owner can fill. Guessing here would put words in the
  # owner's mouth that the ledger then attributes to them.
  @system_prompt """
  You extract vehicle facts from a single sentence a car owner typed to \
  describe their own car. Fill the schema from what the sentence actually \
  states. Never guess, infer, or normalize beyond the owner's words: a fact \
  the sentence does not state is null. "mileage" is the odometer reading in \
  miles as an integer. "vin" is a 17-character VIN only if one appears in \
  the text. "model" is the model name exactly as the owner wrote it.
  """

  @schema %{
    "type" => "object",
    "properties" => %{
      "vin" => %{"anyOf" => [%{"type" => "string"}, %{"type" => "null"}]},
      "year" => %{"anyOf" => [%{"type" => "integer"}, %{"type" => "null"}]},
      "marque" => %{"anyOf" => [%{"type" => "string"}, %{"type" => "null"}]},
      "model" => %{"anyOf" => [%{"type" => "string"}, %{"type" => "null"}]},
      "color" => %{"anyOf" => [%{"type" => "string"}, %{"type" => "null"}]},
      "mileage" => %{"anyOf" => [%{"type" => "integer"}, %{"type" => "null"}]}
    },
    "required" => ~w(vin year marque model color mileage),
    "additionalProperties" => false
  }

  @doc """
  Read a sentence into candidate facts.

  Returns `{:ok, reading}` where the reading holds `:vin`, `:year`,
  `:marque`, `:model`, `:color`, and `:mileage`, any of which may be nil —
  the model is told an unstated fact is null, and the read-back screen shows
  the gap as an editable empty line.
  """
  def extract(sentence) when is_binary(sentence) do
    with {:ok, api_key} <- api_key(),
         {:ok, body} <- request(api_key, sentence),
         {:ok, fields} <- read_response(body) do
      {:ok, reading(fields)}
    end
  end

  @doc """
  The deterministic half: a reading, mapped onto the closed vocabulary.

  Every mapping is code, not model output — the value shapes match what
  santo emits (`identity.model` is always code+label) so `claim_comparison/1`
  compares like with like when the decode arrives at resolution. A line the
  vocabulary rejects is dropped rather than persisted malformed; the sentence
  artifact still holds the owner's words in full.
  """
  def claims(reading) do
    [
      {"identity.model_year", reading[:year]},
      {"identity.marque", normalize_marque(reading[:marque])},
      {"identity.model", model_value(reading[:model])},
      {"state.exterior", exterior_value(reading[:color])},
      {"observation.mileage", reading[:mileage]}
    ]
    |> Enum.reject(fn {_predicate, value} -> is_nil(value) end)
    |> Enum.filter(fn {predicate, value} ->
      SantoApi.Registry.Vocabulary.validate(predicate, value) == :ok
    end)
    |> Enum.map(fn {predicate, value} -> %{predicate: predicate, value: value} end)
  end

  defp request(api_key, sentence) do
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
          max_tokens: 1024,
          system: @system_prompt,
          output_config: %{
            effort: "low",
            format: %{type: "json_schema", schema: @schema}
          },
          messages: [%{role: "user", content: sentence}]
        }
      ]
      |> Keyword.merge(Application.get_env(:santo_api, :extraction_req_options, []))

    case Req.request(options) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("extraction request failed: HTTP #{status}")
        {:error, :unavailable}

      {:error, reason} ->
        Logger.warning("extraction request failed: #{inspect(reason)}")
        {:error, :unavailable}
    end
  end

  # Check stop_reason before touching content: a refusal is a successful HTTP
  # response whose content may be empty or off-schema.
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
      vin: presence(fields["vin"]),
      year: if(is_integer(fields["year"]), do: fields["year"]),
      marque: presence(fields["marque"]),
      model: presence(fields["model"]),
      color: presence(fields["color"]),
      mileage: if(is_integer(fields["mileage"]), do: fields["mileage"])
    }
  end

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp presence(_value), do: nil

  # Santo emits lowercase marques ("porsche"); the owner's "Porsche" is the
  # same word, so normalize before it enters a hash.
  defp normalize_marque(nil), do: nil
  defp normalize_marque(marque), do: String.downcase(marque)

  # The owner's words carry the label; the code is a slug of it, because the
  # value shape requires one and there is no compiled table for a marque santo
  # does not decode. When resolution brings santo's own code the comparison
  # may disagree — which is the audit working, not a bug to paper over.
  defp model_value(nil), do: nil

  defp model_value(model) do
    code =
      model
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")

    if code == "", do: nil, else: %{"code" => code, "label" => model}
  end

  defp exterior_value(nil), do: nil
  defp exterior_value(color), do: %{"summary" => color}

  defp model, do: Keyword.fetch!(config(), :model)

  defp api_key do
    case Keyword.get(config(), :api_key) do
      key when is_binary(key) and key != "" ->
        {:ok, key}

      _absent ->
        Logger.warning("extraction skipped: no ANTHROPIC_API_KEY configured")
        {:error, :not_configured}
    end
  end

  defp config, do: Application.get_env(:santo_api, :extraction, [])
end
