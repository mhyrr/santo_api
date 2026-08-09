defmodule SantoApi.EntryExtractionTest do
  use ExUnit.Case, async: true

  alias SantoApi.EntryExtraction

  test "extracts a fixed logbook draft and supplies today's date to the model" do
    Req.Test.stub(EntryExtraction, fn conn ->
      assert conn.method == "POST"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)
      assert hd(request["messages"])["content"] =~ "Current date: 2026-08-09"

      Req.Test.json(conn, %{
        "stop_reason" => "end_turn",
        "content" => [
          %{
            "type" => "text",
            "text" =>
              Jason.encode!(%{
                "mode" => "fuel",
                "date" => "2026-08-08",
                "odometer" => 41_660,
                "volume" => "13.1",
                "unit" => "gal",
                "total_price" => nil,
                "unit_price" => "5.15",
                "currency" => "USD",
                "summary" => nil,
                "performer" => nil,
                "area" => nil,
                "outing_kind" => nil,
                "venue" => nil,
                "result" => nil,
                "note" => nil
              })
          }
        ]
      })
    end)

    assert {:ok, reading} =
             EntryExtraction.extract(
               "Filled it yesterday: 13.1 gallons at $5.15, 41,660 miles",
               ~D[2026-08-09]
             )

    assert reading.mode == :fuel
    assert reading.date == ~D[2026-08-08]
    assert reading.odometer == 41_660
    assert reading.unit_price == "5.15"
  end

  test "transport and refusal failures are ordinary errors" do
    Req.Test.stub(EntryExtraction, fn conn -> Plug.Conn.send_resp(conn, 503, "down") end)
    assert {:error, :unavailable} = EntryExtraction.extract("anything")

    Req.Test.stub(EntryExtraction, fn conn ->
      Req.Test.json(conn, %{"stop_reason" => "refusal", "content" => []})
    end)

    assert {:error, :refusal} = EntryExtraction.extract("anything")
  end
end
