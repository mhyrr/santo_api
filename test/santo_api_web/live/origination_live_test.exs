defmodule SantoApiWeb.OriginationLiveTest do
  @moduledoc """
  The seven-screen flow (owner_surface §7b.3), and what it leaves behind:
  the one box, the read-back, registration, the minute-one panel, the
  publish gate, and resolution from the page.
  """

  # Ingest-heavy: real VINs and shared parties deadlock under async (CLAUDE.md).
  use SantoApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import SantoApi.AccountsFixtures

  alias SantoApi.Accounts
  alias SantoApi.Origination
  alias SantoApi.Owners
  alias SantoApi.Registry

  @sentence "2024 Lexus GX 550, green, 35,000 miles"

  defp stub_extraction(fields) do
    Req.Test.stub(SantoApi.Extraction, fn conn ->
      Req.Test.json(conn, %{
        "stop_reason" => "end_turn",
        "content" => [%{"type" => "text", "text" => Jason.encode!(fields)}]
      })
    end)
  end

  defp gx550(overrides \\ %{}) do
    Map.merge(
      %{
        "vin" => nil,
        "year" => 2024,
        "marque" => "Lexus",
        "model" => "GX 550",
        "color" => "green",
        "mileage" => 35_000
      },
      overrides
    )
  end

  defp originate(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          email: unique_user_email(),
          handle: unique_user_handle(),
          sentence: @sentence,
          claims: [
            %{predicate: "identity.model_year", value: 2024},
            %{predicate: "identity.marque", value: "lexus"},
            %{predicate: "identity.model", value: %{"code" => "gx_550", "label" => "GX 550"}},
            %{predicate: "observation.mileage", value: 35_000}
          ]
        },
        overrides
      )

    {:ok, created} = Origination.originate(attrs, &"http://localhost/users/log-in/#{&1}")
    created
  end

  defp confirm(user) do
    {encoded_token, _raw} = generate_user_magic_link_token(user)
    {:ok, {confirmed, _expired}} = Accounts.login_user_by_magic_link(encoded_token)
    confirmed
  end

  describe "the box" do
    test "renders one field for a VIN or a sentence", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/start")

      assert html =~ "Add your car"
      assert html =~ "origination_q"
    end

    test "a bare VIN persists immediately and lands on the page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/start")

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form("#origination-form", %{origination: %{q: "WP0AB29827U782968"}})
               |> render_submit()

      assert to =~ ~r{^/v/}
      assert {:ok, vehicle} = Registry.resolve_vin("WP0AB29827U782968")
      assert to == "/v/#{vehicle.public_id}"
    end

    test "a sentence with an embedded VIN is still the VIN path", %{conn: conn} do
      stub_extraction(gx550(%{"vin" => "WP0AB29827U782968"}))

      {:ok, view, _html} = live(conn, ~p"/start")

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form("#origination-form", %{
                 origination: %{q: "found WP0AB29827U782968 in a barn"}
               })
               |> render_submit()

      assert to =~ ~r{^/v/}
    end

    test "the same door serves a signed-in owner", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())

      {:ok, _view, html} = live(conn, ~p"/start")
      assert html =~ "Add your car"
    end
  end

  describe "a signed-in owner adding a car" do
    test "skips registration and lands on the published page", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      stub_extraction(gx550())

      {:ok, view, _html} = live(conn, ~p"/start")

      html =
        view
        |> form("#origination-form", %{origination: %{q: @sentence}})
        |> render_submit()

      # The read-back, then straight to the page — no registration screen.
      assert html =~ "GX 550"

      assert {:error, {:live_redirect, %{to: to}}} =
               view |> form("#read-back-form", %{reading: %{}}) |> render_submit()

      assert to =~ ~r{^/v/}

      [vehicle] = Owners.list_stewarded_vehicles(SantoApi.Accounts.Scope.for_user(user))
      assert vehicle.identity_kind == :asserted
      assert Owners.steward(vehicle).name == user.handle

      # Public immediately — the owner confirmed their email long ago.
      {:ok, _view, page} = live(build_conn(), to)
      assert page =~ "2024 Lexus GX 550"
    end

    test "collectors have lots of cars — a second origination is a second record", %{conn: conn} do
      user = user_fixture()
      scope = SantoApi.Accounts.Scope.for_user(user)

      {:ok, _first} =
        Origination.originate_for(user, %{sentence: "the first car", claims: []})

      conn = log_in_user(conn, user)
      stub_extraction(gx550())

      {:ok, view, _html} = live(conn, ~p"/start")
      view |> form("#origination-form", %{origination: %{q: @sentence}}) |> render_submit()

      assert {:error, {:live_redirect, %{to: _to}}} =
               view |> form("#read-back-form", %{reading: %{}}) |> render_submit()

      assert length(Owners.list_stewarded_vehicles(scope)) == 2
    end

    test "a legacy account is asked for its handle, once", %{conn: conn} do
      legacy = legacy_user_fixture()
      conn = log_in_user(conn, legacy)
      stub_extraction(gx550())

      {:ok, view, _html} = live(conn, ~p"/start")
      view |> form("#origination-form", %{origination: %{q: @sentence}}) |> render_submit()

      html = view |> form("#read-back-form", %{reading: %{}}) |> render_submit()
      assert html =~ "Choose your handle"
      assert html =~ "permanent"

      assert {:error, {:live_redirect, %{to: _to}}} =
               view
               |> form("#handle-form", %{handle: %{handle: "legacy-collector"}})
               |> render_submit()

      assert Owners.party(legacy).name == "legacy-collector"
    end

    test "a legacy account cannot take a handle someone else reserved", %{conn: conn} do
      %{handle: reserved} = user_fixture()
      legacy = legacy_user_fixture()
      conn = log_in_user(conn, legacy)
      stub_extraction(gx550())

      {:ok, view, _html} = live(conn, ~p"/start")
      view |> form("#origination-form", %{origination: %{q: @sentence}}) |> render_submit()
      view |> form("#read-back-form", %{reading: %{}}) |> render_submit()

      html =
        view
        |> form("#handle-form", %{handle: %{handle: reserved}})
        |> render_submit()

      assert html =~ "already taken"
      assert Owners.party(legacy) == nil
    end
  end

  describe "the flow, end to end" do
    test "sentence → read-back → registration → minute one", %{conn: conn} do
      stub_extraction(gx550())

      {:ok, view, _html} = live(conn, ~p"/start")

      # Screen 2: the read-back, the sentence still on screen.
      html =
        view
        |> form("#origination-form", %{origination: %{q: @sentence}})
        |> render_submit()

      assert html =~ @sentence
      assert html =~ "GX 550"
      assert html =~ "35000"

      # The owner corrects a line — the read-back is editable in place.
      html =
        view
        |> form("#read-back-form", %{
          reading: %{
            year: "2024",
            marque: "Lexus",
            model: "GX 550",
            color: "Nori Green",
            mileage: "35000"
          }
        })
        |> render_submit()

      # Screen 3: registration, permanence stated on the screen.
      assert html =~ "Who keeps this record?"
      assert html =~ "permanent"

      email = unique_user_email()
      handle = unique_user_handle()

      html =
        view
        |> form("#origination-registration", %{user: %{email: email, handle: handle}})
        |> render_submit()

      # Screen 4: the page, minute one — named car, banner, one lit tick.
      assert html =~ "2024 Lexus GX 550"
      assert html =~ "Started this record"
      assert html =~ "confirm your email to make it public"
      assert html =~ handle

      # What it left behind: an unconfirmed account and an asserted car with
      # the owner's edit, not the extractor's line.
      user = Accounts.get_user_by_email(email)
      assert user.handle == handle
      assert is_nil(user.confirmed_at)

      [vehicle] = Owners.list_stewarded_vehicles(SantoApi.Accounts.Scope.for_user(user))
      assert vehicle.identity_kind == :asserted
      assert vehicle.current_state["state.exterior"]["value"]["summary"] == "Nori Green"
    end

    test "extraction failure is the same screen with empty lines, method :human", %{conn: conn} do
      Req.Test.stub(SantoApi.Extraction, fn conn ->
        Plug.Conn.send_resp(conn, 500, "boom")
      end)

      {:ok, view, _html} = live(conn, ~p"/start")

      html =
        view
        |> form("#origination-form", %{origination: %{q: "a car words fail"}})
        |> render_submit()

      assert html =~ "reading_year"

      view
      |> form("#read-back-form", %{
        reading: %{year: "1987", marque: "Porsche", model: "", color: "", mileage: ""}
      })
      |> render_submit()

      email = unique_user_email()

      view
      |> form("#origination-registration", %{
        user: %{email: email, handle: unique_user_handle()}
      })
      |> render_submit()

      user = Accounts.get_user_by_email(email)
      [vehicle] = Owners.list_stewarded_vehicles(SantoApi.Accounts.Scope.for_user(user))

      year = Enum.find(Registry.list_claims(vehicle.id), &(&1.predicate == "identity.model_year"))
      assert year.value == 1987
      assert year.method == :human
    end

    test "a taken email shows the error on the registration screen", %{conn: conn} do
      %{email: taken} = user_fixture()
      stub_extraction(gx550())

      {:ok, view, _html} = live(conn, ~p"/start")

      view |> form("#origination-form", %{origination: %{q: @sentence}}) |> render_submit()
      view |> form("#read-back-form", %{reading: %{}}) |> render_submit()

      html =
        view
        |> form("#origination-registration", %{
          user: %{email: taken, handle: unique_user_handle()}
        })
        |> render_submit()

      assert html =~ "has already been taken"
      assert html =~ "Who keeps this record?"
    end

    test "links are the last onboarding step", %{conn: conn} do
      stub_extraction(gx550())

      {:ok, view, _html} = live(conn, ~p"/start")

      view |> form("#origination-form", %{origination: %{q: @sentence}}) |> render_submit()
      view |> form("#read-back-form", %{reading: %{}}) |> render_submit()

      email = unique_user_email()

      view
      |> form("#origination-registration", %{user: %{email: email, handle: unique_user_handle()}})
      |> render_submit()

      html =
        view
        |> form("#onboarding-link-form", %{
          link: %{url: "https://www.youtube.com/watch?v=abc123", label: "Build video"}
        })
        |> render_submit()

      assert html =~ "Build video"

      user = Accounts.get_user_by_email(email)
      [vehicle] = Owners.list_stewarded_vehicles(SantoApi.Accounts.Scope.for_user(user))
      assert [link] = SantoApi.Owners.Links.list_links(vehicle)
      assert link.label == "Build video"
    end
  end

  describe "the publish gate" do
    test "an unconfirmed origination is nobody's business but the steward's", %{conn: conn} do
      created = originate()

      # Anonymous: indistinguishable from a missing car.
      assert_raise SantoApiWeb.VehicleNotFound, fn ->
        live(conn, ~p"/v/#{created.vehicle.public_id}")
      end

      # And absent from the directory.
      {:ok, _view, html} = live(build_conn(), ~p"/")
      refute html =~ created.vehicle.public_id

      # The steward sees their own page, with the banner.
      steward_conn = log_in_user(build_conn(), created.user)
      {:ok, _view, html} = live(steward_conn, ~p"/v/#{created.vehicle.public_id}")
      assert html =~ "confirm your email to make it public"
    end

    test "the magic-link click publishes", %{conn: conn} do
      created = originate()
      confirm(created.user)

      {:ok, _view, html} = live(conn, ~p"/v/#{created.vehicle.public_id}")
      assert html =~ "2024 Lexus GX 550"
      refute html =~ "confirm your email"

      {:ok, _view, index} = live(build_conn(), ~p"/")
      assert index =~ created.vehicle.public_id
    end
  end

  describe "the asserted page" do
    setup %{conn: conn} do
      created = originate()
      confirm(created.user)
      steward_conn = log_in_user(build_conn(), created.user)
      %{conn: conn, steward_conn: steward_conn, created: created}
    end

    test "the paper ground does not render — the page ends at the owner's word", ctx do
      {:ok, _view, html} = live(ctx.conn, ~p"/v/#{ctx.created.vehicle.public_id}")

      refute html =~ "vehicle-record"
      assert html =~ "Add the VIN when you have it"
      # The visitor is told, but only the steward gets the form.
      refute html =~ "resolve-form"
    end

    test "the steward resolves the VIN in place and the record unrolls", ctx do
      {:ok, view, html} = live(ctx.steward_conn, ~p"/v/#{ctx.created.vehicle.public_id}")
      assert html =~ "resolve-form"

      html =
        view
        |> form("#resolve-form", %{resolve: %{vin: "WP0AB29827U782968"}})
        |> render_submit()

      assert html =~ "vehicle-record"
      refute html =~ "resolve-form"

      {:ok, resolved} = Registry.fetch_vehicle(ctx.created.vehicle.id)
      assert resolved.identity_kind == :vin
    end

    test "a bad VIN is told what it is", ctx do
      {:ok, view, _html} = live(ctx.steward_conn, ~p"/v/#{ctx.created.vehicle.public_id}")

      html = view |> form("#resolve-form", %{resolve: %{vin: "NOT A VIN"}}) |> render_submit()
      assert html =~ "not valid"
    end

    test "the collision routes to the counter-claim, never a refusal", ctx do
      {:ok, occupied} = Registry.ingest("WP0AB29827U782968")

      {:ok, view, _html} = live(ctx.steward_conn, ~p"/v/#{ctx.created.vehicle.public_id}")

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form("#resolve-form", %{resolve: %{vin: "WP0AB29827U782968"}})
               |> render_submit()

      assert to == "/v/#{occupied.public_id}/claim"
      assert Owners.challenge(ctx.created.user, occupied)
    end

    test "links render for everyone; only the steward curates", ctx do
      scope = SantoApi.Accounts.Scope.for_user(ctx.created.user)

      {:ok, _link} =
        SantoApi.Owners.Links.add_link(scope, ctx.created.vehicle, %{
          "url" => "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
          "label" => "Walkaround"
        })

      {:ok, _view, html} = live(ctx.conn, ~p"/v/#{ctx.created.vehicle.public_id}")
      assert html =~ "youtube.com/embed/dQw4w9WgXcQ"
      refute html =~ "link-form"

      {:ok, view, html} = live(ctx.steward_conn, ~p"/v/#{ctx.created.vehicle.public_id}")
      assert html =~ "link-form"

      html =
        view
        |> form("#link-form", %{link: %{url: "https://rennlist.com/thread", label: "The thread"}})
        |> render_submit()

      assert html =~ "The thread"
    end
  end
end
