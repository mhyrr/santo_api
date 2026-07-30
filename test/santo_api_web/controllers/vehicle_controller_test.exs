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

  describe "POST /api/vehicles/:id/vpic" do
    setup do
      Req.Test.stub(SantoApi.Vpic, fn conn ->
        Req.Test.json(conn, SantoApi.VpicFixtures.cgt_response())
      end)

      :ok
    end

    test "runs the lookup and returns artifact, claims, and comparison", %{conn: conn} do
      %{"vehicle" => %{"id" => id}} =
        post(conn, ~p"/api/vehicles", %{"input" => "WP0CA298X5L001502"})
        |> json_response(201)

      conn = post(conn, ~p"/api/vehicles/#{id}/vpic")

      assert %{
               "artifact" => %{"kind" => "api_snapshot", "sha256" => _},
               "claims" => claims,
               "comparison" => comparison
             } = json_response(conn, 201)

      proposed = Enum.filter(claims, &(&1["state"] == "proposed"))
      assert length(proposed) == 3

      model = Enum.find(comparison, &(&1["predicate"] == "identity.model"))
      assert model["status"] == "conflict"
    end

    test "unknown vehicle is a 404", %{conn: conn} do
      conn = post(conn, ~p"/api/vehicles/#{Ecto.UUID.generate()}/vpic")
      assert json_response(conn, 404)
    end

    test "a chassis-number vehicle is unprocessable for vPIC", %{conn: conn} do
      %{"vehicle" => %{"id" => id}} =
        post(conn, ~p"/api/vehicles", %{"input" => "81192"})
        |> json_response(201)

      conn = post(conn, ~p"/api/vehicles/#{id}/vpic")
      assert %{"status" => "unsupported_identity"} = json_response(conn, 422)
    end

    test "vPIC being down is a 502", %{conn: conn} do
      %{"vehicle" => %{"id" => id}} =
        post(conn, ~p"/api/vehicles", %{"input" => "WP0ZZZ95ZJS905016"})
        |> json_response(201)

      Req.Test.stub(SantoApi.Vpic, fn conn -> Plug.Conn.send_resp(conn, 503, "down") end)

      conn = post(conn, ~p"/api/vehicles/#{id}/vpic")
      assert %{"status" => "vpic_unavailable"} = json_response(conn, 502)
    end
  end
end
