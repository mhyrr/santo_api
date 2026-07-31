defmodule SantoApiWeb.BenchLiveTest do
  use SantoApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias SantoApi.Registry

  @nine_three "WP0ZZZ99ZTS392124"
  @cgt "WP0CA298X5L001502"

  describe "Index" do
    test "renders the ingest form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/bench")

      assert html =~ "Bench"
      assert html =~ "ingest-form"
    end

    test "submitting a resolvable VIN navigates to the vehicle page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/bench")

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form("#ingest-form", %{"input" => @nine_three})
               |> render_submit()

      assert to =~ "/bench/vehicles/"
    end

    test "submitting an unrecognized shape shows santo's diagnosis", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/bench")

      html =
        view
        |> form("#ingest-form", %{"input" => "12345678"})
        |> render_submit()

      assert html =~ "unrecognized_shape"
    end
  end

  describe "Show" do
    test "renders identity and facts with status badges", %{conn: conn} do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      {:ok, _view, html} = live(conn, ~p"/bench/vehicles/#{vehicle.id}")

      assert html =~ "vin:WP0ZZZ99ZTS392124"
      assert html =~ "badge-success"
    end

    test "ratifying a proposed claim turns its fact verified", %{conn: conn} do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      {:ok, claim} =
        Registry.propose_claim(vehicle, %{predicate: "build.variant", value: "coupe"})

      {:ok, view, _html} = live(conn, ~p"/bench/vehicles/#{vehicle.id}")

      assert has_element?(view, "tr[data-predicate='build.variant'] .badge-neutral")

      view
      |> element("button[phx-value-id='#{claim.id}']", "Ratify")
      |> render_click()

      assert has_element?(view, "tr[data-predicate='build.variant'] .badge-success")
    end

    test "uploading a file creates an artifact row", %{conn: conn} do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      {:ok, view, _html} = live(conn, ~p"/bench/vehicles/#{vehicle.id}")

      file_upload =
        file_input(view, "#artifact-upload-form", :file, [
          %{
            name: "invoice.pdf",
            content: "receipt body",
            type: "application/pdf"
          }
        ])

      assert render_upload(file_upload, "invoice.pdf") =~ "100"

      html =
        view
        |> form("#artifact-upload-form", %{"kind" => "receipt"})
        |> render_submit()

      assert html =~ "invoice.pdf"
    end

    test "running vPIC surfaces proposed claims", %{conn: conn} do
      Req.Test.stub(SantoApi.Vpic, fn conn ->
        Req.Test.json(conn, SantoApi.VpicFixtures.cgt_response())
      end)

      {:ok, vehicle} = Registry.ingest(@cgt)

      {:ok, view, _html} = live(conn, ~p"/bench/vehicles/#{vehicle.id}")
      Req.Test.allow(SantoApi.Vpic, self(), view.pid)

      html =
        view
        |> element("button", "Run vPIC")
        |> render_click()

      assert html =~ "structured_api"
    end

    test "unknown vehicle id redirects to the bench index", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/bench"}}} =
               live(conn, ~p"/bench/vehicles/#{Ecto.UUID.generate()}")
    end
  end
end
