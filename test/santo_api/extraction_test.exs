defmodule SantoApi.ExtractionTest do
  use ExUnit.Case, async: true

  alias SantoApi.Extraction

  # The wire shape of a structured-output response: stop_reason plus a text
  # block whose body is guaranteed-valid JSON for the request's schema.
  defp response(fields, stop_reason \\ "end_turn") do
    %{
      "stop_reason" => stop_reason,
      "content" => [%{"type" => "text", "text" => Jason.encode!(fields)}]
    }
  end

  defp gx550 do
    %{
      "vin" => nil,
      "year" => 2024,
      "marque" => "Lexus",
      "model" => "GX 550",
      "color" => "green",
      "mileage" => 35_000
    }
  end

  describe "extract/1" do
    test "reads the probe sentence into fields" do
      Req.Test.stub(SantoApi.Extraction, fn conn ->
        Req.Test.json(conn, response(gx550()))
      end)

      assert {:ok, reading} = Extraction.extract("2024 Lexus GX 550, green, 35,000 miles")

      assert reading.year == 2024
      assert reading.marque == "Lexus"
      assert reading.model == "GX 550"
      assert reading.color == "green"
      assert reading.mileage == 35_000
      assert reading.vin == nil
    end

    test "sends the sentence and the schema, never the ledger" do
      Req.Test.stub(SantoApi.Extraction, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["model"] == "claude-opus-5"
        assert [%{"role" => "user", "content" => "my car sentence"}] = payload["messages"]
        assert payload["output_config"]["format"]["type"] == "json_schema"

        Req.Test.json(conn, response(gx550()))
      end)

      assert {:ok, _reading} = Extraction.extract("my car sentence")
    end

    test "an embedded VIN comes back as a field" do
      Req.Test.stub(SantoApi.Extraction, fn conn ->
        Req.Test.json(conn, response(%{gx550() | "vin" => "WP0AB29827U782968"}))
      end)

      assert {:ok, %{vin: "WP0AB29827U782968"}} = Extraction.extract("found WP0AB29827U782968")
    end

    test "blank and non-typed fields normalize to nil" do
      Req.Test.stub(SantoApi.Extraction, fn conn ->
        Req.Test.json(
          conn,
          response(%{
            "vin" => "  ",
            "year" => "2024",
            "marque" => nil,
            "model" => "",
            "color" => nil,
            "mileage" => "lots"
          })
        )
      end)

      assert {:ok, reading} = Extraction.extract("gibberish")
      assert reading == %{vin: nil, year: nil, marque: nil, model: nil, color: nil, mileage: nil}
    end

    test "a refusal is an error, not a crash" do
      Req.Test.stub(SantoApi.Extraction, fn conn ->
        Req.Test.json(conn, %{"stop_reason" => "refusal", "content" => []})
      end)

      assert {:error, :refusal} = Extraction.extract("anything")
    end

    test "a server error degrades rather than raising" do
      Req.Test.stub(SantoApi.Extraction, fn conn ->
        Plug.Conn.send_resp(conn, 500, "boom")
      end)

      assert {:error, :unavailable} = Extraction.extract("anything")
    end

    test "a transport error degrades rather than raising" do
      Req.Test.stub(SantoApi.Extraction, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :unavailable} = Extraction.extract("anything")
    end

    test "an unparseable body degrades rather than raising" do
      Req.Test.stub(SantoApi.Extraction, fn conn ->
        Req.Test.json(conn, %{"stop_reason" => "end_turn", "content" => []})
      end)

      assert {:error, :unreadable} = Extraction.extract("anything")
    end
  end

  describe "claims/1" do
    test "maps a full reading onto the closed vocabulary" do
      reading = %{
        vin: nil,
        year: 2024,
        marque: "Lexus",
        model: "GX 550",
        color: "green",
        mileage: 35_000
      }

      claims = Extraction.claims(reading)

      assert %{predicate: "identity.model_year", value: 2024} in claims
      assert %{predicate: "identity.marque", value: "lexus"} in claims

      assert %{predicate: "identity.model", value: %{"code" => "gx_550", "label" => "GX 550"}} in claims

      assert %{predicate: "state.exterior", value: %{"summary" => "green"}} in claims
      assert %{predicate: "observation.mileage", value: 35_000} in claims
    end

    test "every emitted claim passes vocabulary validation" do
      reading = %{
        vin: nil,
        year: 2007,
        marque: "Porsche",
        model: "Cayman S",
        color: "silver",
        mileage: 41_660
      }

      for %{predicate: predicate, value: value} <- Extraction.claims(reading) do
        assert SantoApi.Registry.Vocabulary.validate(predicate, value) == :ok
      end
    end

    test "an empty reading maps to no claims" do
      assert Extraction.claims(%{
               vin: nil,
               year: nil,
               marque: nil,
               model: nil,
               color: nil,
               mileage: nil
             }) ==
               []
    end

    test "a value the vocabulary rejects is dropped, not persisted malformed" do
      assert Extraction.claims(%{year: nil, marque: nil, model: nil, color: nil, mileage: -5}) ==
               []
    end
  end
end
