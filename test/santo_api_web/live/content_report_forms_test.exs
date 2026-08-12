defmodule SantoApiWeb.ContentReportFormsTest do
  use SantoApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query

  alias SantoApi.Accounts.Scope
  alias SantoApi.Owners
  alias SantoApi.Registry
  alias SantoApi.Repo
  alias SantoApi.Social.ContentReport

  setup do
    owner = SantoApi.AccountsFixtures.user_fixture()
    reporter = SantoApi.AccountsFixtures.user_fixture()

    {:ok, vehicle} =
      Registry.register_chassis(
        :porsche,
        :pre_vin,
        "PUBLIC-REPORT-#{System.unique_integer([:positive])}"
      )

    {:ok, _stewardship} = Owners.grant_stewardship(owner, vehicle)

    {:ok, entry} =
      Owners.compose_entry(Scope.for_user(owner), vehicle, %{
        date: ~D[2026-08-11],
        claims: [%{predicate: "event.note", value: %{"text" => "Public update"}}]
      })

    %{owner: owner, reporter: reporter, vehicle: vehicle, entry: entry}
  end

  test "anonymous readers see no report mutations", ctx do
    {:ok, car, _html} = live(build_conn(), ~p"/v/#{ctx.vehicle.public_id}")
    refute has_element?(car, "#vehicle-report-form")

    {:ok, update, _html} =
      live(build_conn(), ~p"/v/#{ctx.vehicle.public_id}/updates/#{ctx.entry.entry_ref}")

    refute has_element?(update, "#update-report-form")
  end

  test "a signed-in member can report the car and one update through stable forms", ctx do
    conn = log_in_user(build_conn(), ctx.reporter)
    {:ok, car, _html} = live(conn, ~p"/v/#{ctx.vehicle.public_id}")

    assert has_element?(car, "#vehicle-report-control")
    assert has_element?(car, "#vehicle-report-form")
    assert has_element?(car, "#vehicle-report-submit")

    car
    |> form("#vehicle-report-form", %{
      "content_report" => %{
        "reason" => "fraud",
        "detail" => "The car identity appears fabricated."
      }
    })
    |> render_submit()

    assert Repo.exists?(
             from(r in ContentReport,
               where:
                 r.vehicle_id == ^ctx.vehicle.id and r.target_kind == :vehicle and
                   r.reporter_user_id == ^ctx.reporter.id and r.status == :open
             )
           )

    {:ok, update, _html} =
      live(conn, ~p"/v/#{ctx.vehicle.public_id}/updates/#{ctx.entry.entry_ref}")

    assert has_element?(update, "#update-report-control")
    assert has_element?(update, "#update-report-form")
    assert has_element?(update, "#update-report-submit")

    update
    |> form("#update-report-form", %{
      "content_report" => %{
        "reason" => "abuse",
        "detail" => "The update targets another member."
      }
    })
    |> render_submit()

    assert Repo.exists?(
             from(r in ContentReport,
               where:
                 r.vehicle_id == ^ctx.vehicle.id and r.entry_ref == ^ctx.entry.entry_ref and
                   r.reporter_user_id == ^ctx.reporter.id and r.status == :open
             )
           )
  end
end
