defmodule SantoApiWeb.VehicleControllerTest do
  use SantoApiWeb.ConnCase, async: true

  describe "POST /api/vehicles" do
    test "ingests a VIN and returns the registry record", %{conn: conn} do
      conn = post(conn, ~p"/api/vehicles", %{"input" => "WP0CA298X5L001502"})

      assert %{
               "vehicle" => %{
                 "id" => id,
                 "identity_kind" => "vin",
                 "identity_key" => "vin:WP0CA298X5L001502"
               },
               "claims" => claims,
               "evidence_requests" => []
             } = json_response(conn, 201)

      assert is_binary(id)

      assert %{"predicate" => "identity.model_year", "value" => 2005, "state" => "admitted"} =
               Enum.find(claims, &(&1["predicate"] == "identity.model_year"))
    end

    test "a disputed identity returns candidates and its open evidence request", %{conn: conn} do
      conn = post(conn, ~p"/api/vehicles", %{"input" => "81192"})

      assert %{
               "vehicle" => %{"identity_kind" => "disputed", "candidates" => [_, _]},
               "claims" => [],
               "evidence_requests" => [request]
             } = json_response(conn, 201)

      assert request["subject"] == "identity"
      assert "kardex" in request["evidence_classes"]
    end

    test "invalid input gets santo's diagnosis as 422", %{conn: conn} do
      conn = post(conn, ~p"/api/vehicles", %{"input" => "12345678"})

      assert %{"status" => "invalid", "reasons" => reasons} = json_response(conn, 422)
      assert "unrecognized_shape" in reasons
    end
  end

  describe "GET /api/vehicles/:id" do
    test "returns the persisted record", %{conn: conn} do
      created =
        post(conn, ~p"/api/vehicles", %{"input" => "WP0ZZZ95ZJS905016"})
        |> json_response(201)

      conn = get(conn, ~p"/api/vehicles/#{created["vehicle"]["id"]}")

      assert %{"vehicle" => %{"identity_key" => "vin:WP0ZZZ95ZJS905016"}, "claims" => claims} =
               json_response(conn, 200)

      assert length(claims) == 6
    end

    test "unknown id is a 404", %{conn: conn} do
      conn = get(conn, ~p"/api/vehicles/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end
end
