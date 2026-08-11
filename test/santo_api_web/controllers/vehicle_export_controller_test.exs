defmodule SantoApiWeb.VehicleExportControllerTest do
  use SantoApiWeb.ConnCase, async: false

  import SantoApi.AccountsFixtures

  alias SantoApi.Owners
  alias SantoApi.Registry

  setup :register_and_log_in_user

  setup ctx do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    {:ok, _stewardship} = Owners.grant_stewardship(ctx.user, vehicle)
    %{vehicle: vehicle}
  end

  test "an active steward downloads a private no-store ZIP", ctx do
    conn = get(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/export")

    assert <<0x50, 0x4B, _rest::binary>> = response(conn, 200)
    assert get_resp_header(conn, "content-type") == ["application/zip"]
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]

    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "vin-santo-#{ctx.vehicle.public_id}-record.zip"
  end

  test "the route requires a signed-in session", ctx do
    conn = get(build_conn(), ~p"/v/#{ctx.vehicle.public_id}/export")
    assert redirected_to(conn) == ~p"/users/log-in"
  end

  test "a signed-in stranger gets the same 404 as a missing car", ctx do
    stranger_conn = log_in_user(build_conn(), user_fixture(%{handle: "exportstranger"}))

    assert_error_sent 404, fn ->
      get(stranger_conn, ~p"/v/#{ctx.vehicle.public_id}/export")
    end
  end
end
