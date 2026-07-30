defmodule SantoApi.VpicFixtures do
  @moduledoc """
  vPIC DecodeVinValues payloads, taken from santo's oracle snapshot
  (oracle/fixtures/vpic_snapshot.exs) — real captured responses, trimmed.
  The Carrera GT is the canonical conflict case: vPIC labels the model
  "911" while santo decodes carrera_gt.
  """

  def cgt_values do
    %{
      "VIN" => "WP0CA298X5L001502",
      "Make" => "PORSCHE",
      "MakeID" => "584",
      "Manufacturer" => "DR. ING. H.C.F. PORSCHE AG",
      "Model" => "911",
      "ModelYear" => "2005",
      "Trim" => "GT",
      "PlantCity" => "LEIPZIG",
      "PlantCountry" => "GERMANY",
      "BodyClass" => "Coupe",
      "DisplacementL" => "5.7",
      "EngineHP" => "605",
      "FuelTypePrimary" => "Gasoline",
      "ErrorCode" => "0",
      "ErrorText" => "0 - VIN decoded clean. Check Digit (9th position) is correct"
    }
  end

  def cgt_response, do: response(cgt_values())

  def response(values) do
    %{
      "Count" => 1,
      "Message" => "Results returned successfully",
      "SearchCriteria" => "VIN:" <> Map.fetch!(values, "VIN"),
      "Results" => [values]
    }
  end
end
