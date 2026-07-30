defmodule SantoApiWeb.VinControllerTest do
  use SantoApiWeb.ConnCase, async: true

  describe "GET /api/vins/:vin" do
    test "decodes a Porsche 959 VIN", %{conn: conn} do
      conn = get(conn, ~p"/api/vins/WP0ZZZ95ZJS905016")

      assert %{"status" => "ok", "decoded" => decoded} = json_response(conn, 200)
      assert decoded["marque"] == "porsche"
      assert decoded["market"] == "row"
      assert decoded["model"] == ["959", "959"]
      assert decoded["years"] == [1988]
      assert decoded["confidence"] == "inferred"
      assert decoded["check_digit"] == "not_applicable"
      assert decoded["attributes"]["variant"] == "sport"
    end

    test "decodes a generic (non-Porsche) VIN with no marque adapter", %{conn: conn} do
      conn = get(conn, ~p"/api/vins/1M8GDM9AXKP042788")

      assert %{"status" => "ok", "decoded" => decoded} = json_response(conn, 200)
      assert decoded["marque"] == nil
      assert decoded["check_digit"] == "valid"
      assert "generic_decode" in decoded["notes"]
    end

    test "decodes a pre-VIN Porsche chassis number", %{conn: conn} do
      conn = get(conn, ~p"/api/vins/9113600471")

      assert %{"status" => "ok", "decoded" => decoded} = json_response(conn, 200)
      assert decoded["marque"] == "porsche"
      assert decoded["chassis"]["type_code"] == "60"
      assert decoded["parsed"] == nil
    end

    test "returns ambiguous candidates for an ambiguous chassis number", %{conn: conn} do
      conn = get(conn, ~p"/api/vins/81192")

      assert %{"status" => "ambiguous", "candidates" => candidates} = json_response(conn, 200)
      assert length(candidates) == 2
      assert Enum.all?(candidates, &(&1["marque"] == "porsche"))
    end

    test "returns 422 with diagnosis for an unrecognized/invalid input", %{conn: conn} do
      conn = get(conn, ~p"/api/vins/12345678")

      assert %{"status" => "invalid", "reasons" => reasons} = json_response(conn, 422)
      assert "unrecognized_shape" in reasons
      assert ["bad_length", 8] in reasons
    end
  end
end
