defmodule SantoApiWeb.VehicleBuildControllerTest do
  use SantoApiWeb.ConnCase, async: false

  alias SantoApi.AcquisitionRuns.Run
  alias SantoApi.AcquisitionRuns.StepWorker
  alias SantoApi.Registry
  alias SantoApi.Registry.Vehicle
  alias SantoApi.Repo

  @vin "WP0CA298X5L001502"

  test "POST /builds creates a new public record and redirects immediately", %{conn: conn} do
    conn = post(conn, ~p"/builds", %{"vin" => " wp0ca298x5l001502 "})
    vehicle = Repo.get_by!(Vehicle, identity_key: "vin:#{@vin}")

    assert redirected_to(conn) == "/v/#{vehicle.public_id}"
    assert get_resp_header(conn, "x-ratelimit-limit") == ["1000000"]
    assert Repo.aggregate(Run, :count) == 1
    assert_enqueued(worker: StepWorker)
  end

  test "POST /builds sends an existing VIN to its page without starting work", %{conn: conn} do
    {:ok, vehicle} = Registry.ingest(@vin)

    conn = post(conn, ~p"/builds", %{"vin" => @vin})

    assert redirected_to(conn) == "/v/#{vehicle.public_id}"
    assert Repo.aggregate(Run, :count) == 0
    refute_enqueued(worker: StepWorker)
  end

  test "POST /builds rejects invalid and missing VINs without creating a row", %{conn: conn} do
    invalid = post(conn, ~p"/builds", %{"vin" => "12345678"})
    assert redirected_to(invalid) == "/"
    assert Phoenix.Flash.get(invalid.assigns.flash, :error) == "That VIN is not valid."

    missing = post(build_conn(), ~p"/builds", %{})
    assert redirected_to(missing) == "/"

    assert Repo.aggregate(Vehicle, :count) == 0
    assert Repo.aggregate(Run, :count) == 0
    refute_enqueued(worker: StepWorker)
  end

  test "GET /vin/:vin remains read-only for an unknown VIN", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/vin/#{@vin}") end

    assert Repo.aggregate(Vehicle, :count) == 0
    assert Repo.aggregate(Run, :count) == 0
    refute_enqueued(worker: StepWorker)
  end
end
