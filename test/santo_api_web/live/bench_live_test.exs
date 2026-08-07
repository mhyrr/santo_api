defmodule SantoApiWeb.BenchLiveTest do
  use SantoApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias SantoApi.AcquisitionRuns
  alias SantoApi.AcquisitionRuns.{Run, StepWorker}
  alias SantoApi.Nhtsa.Corpus
  alias SantoApi.Registry

  @nine_three "WP0ZZZ99ZTS392124"
  @cgt "WP0CA298X5L001502"
  @recalls Path.expand("../../fixtures/nhtsa/recalls.txt", __DIR__)
  @bulletins Path.expand("../../fixtures/nhtsa/technical_bulletins.txt", __DIR__)
  @recall_url "https://static.nhtsa.gov/odi/ffdd/rcl/FLAT_RCL_PRE_2010.zip"
  @bulletin_url "https://static.nhtsa.gov/odi/ffdd/tsbs/TSBS_RECEIVED_2020-2024.zip"

  setup :register_and_log_in_operator

  describe "access" do
    test "anonymous visitors are sent to the log in page" do
      conn = build_conn()

      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/bench")

      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/bench/vehicles/#{Ecto.UUID.generate()}")
    end

    test "authenticated non-operators are turned away" do
      conn = log_in_user(build_conn(), SantoApi.AccountsFixtures.user_fixture())

      assert {:error, {:redirect, %{to: "/", flash: %{"error" => error}}}} =
               live(conn, ~p"/bench")

      assert error =~ "not authorized"
    end
  end

  describe "Index" do
    test "renders the ingest form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/bench")

      assert has_element?(view, "#vin-lookup-form")
      assert has_element?(view, "#build-record-button")
      assert has_element?(view, "#registry-vehicles")
    end

    test "submitting a fresh VIN starts its durable acquisition and navigates", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/bench")

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form("#vin-lookup-form", lookup: %{vin: @nine_three})
               |> render_submit()

      assert to =~ "/bench/vehicles/"

      {:ok, vehicle} = Registry.resolve_vin(@nine_three)
      assert %Run{status: :pending} = AcquisitionRuns.latest_for_vehicle(nil, vehicle)
      assert_enqueued(worker: StepWorker)
    end

    test "submitting an existing VIN starts a fresh operator run", %{conn: conn} do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      {:ok, view, _html} = live(conn, ~p"/bench")

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form("#vin-lookup-form", lookup: %{vin: @nine_three})
               |> render_submit()

      assert to == "/bench/vehicles/#{vehicle.id}"
      assert %Run{vehicle_id: vehicle_id} = AcquisitionRuns.latest_for_vehicle(nil, vehicle)
      assert vehicle_id == vehicle.id
    end

    test "submitting an unrecognized shape shows santo's diagnosis", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/bench")

      view
      |> form("#vin-lookup-form", lookup: %{vin: "12345678"})
      |> render_submit()

      assert has_element?(view, "#vin-lookup-error", "unrecognized_shape")
    end

    test "submitting a chassis preserves bench ingestion without a provider run", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/bench")

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form("#vin-lookup-form", lookup: %{vin: "9113600471"})
               |> render_submit()

      [vehicle] = Registry.list_vehicles()
      assert vehicle.identity_kind == :chassis
      assert to == "/bench/vehicles/#{vehicle.id}"
      assert is_nil(AcquisitionRuns.latest_for_vehicle(nil, vehicle))
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

    test "renders the durable acquisition ledger", %{conn: conn, scope: scope} do
      assert {:ok, :created, vehicle, run} = AcquisitionRuns.start_operator(scope, @cgt)

      {:ok, view, _html} = live(conn, ~p"/bench/vehicles/#{vehicle.id}")

      assert has_element?(view, "#acquisition-run[data-run-id='#{run.id}']")
      assert has_element?(view, "#acquisition-run-status", "pending")
      assert has_element?(view, "#acquisition-steps article[data-step-status='pending']")
      assert has_element?(view, "#acquisition-steps article[data-step-status='unsupported']")
    end

    test "provider completion refreshes the ledger, artifacts, and claims through PubSub", %{
      conn: conn,
      scope: scope
    } do
      Req.Test.stub(SantoApi.Vpic, fn conn ->
        Req.Test.json(conn, SantoApi.VpicFixtures.cgt_response())
      end)

      assert {:ok, :created, vehicle, _run} = AcquisitionRuns.start_operator(scope, @cgt)
      run = AcquisitionRuns.latest_for_vehicle(scope, vehicle)
      step = Enum.find(run.steps, &(&1.provider == :nhtsa_vpic))

      {:ok, view, _html} = live(conn, ~p"/bench/vehicles/#{vehicle.id}")

      assert :ok = perform_job(StepWorker, %{step_id: step.id})
      _html = render(view)

      assert has_element?(view, "#acquisition-run[data-run-status='complete']")

      assert has_element?(
               view,
               "article[data-step-key='#{step.step_key}'][data-step-status='complete']"
             )

      assert has_element?(view, "a[href^='/bench/artifacts/']", "Open snapshot")
      assert has_element?(view, "tr[data-claim-id][data-state='proposed']")

      assert has_element?(
               view,
               "article[data-step-status='needs_input']",
               "Conflicted: identity.model"
             )
    end

    test "renders corpus findings, counts, applicability warning, release, and official links", %{
      conn: conn,
      scope: scope
    } do
      import_nhtsa_releases()

      Req.Test.stub(SantoApi.Vpic, fn conn ->
        Req.Test.json(conn, agreement_response())
      end)

      assert {:ok, :created, vehicle, _run} =
               AcquisitionRuns.start_operator(scope, @nine_three)

      run = AcquisitionRuns.latest_for_vehicle(scope, vehicle)
      vpic = Enum.find(run.steps, &(&1.provider == :nhtsa_vpic))
      assert :ok = perform_job(StepWorker, %{step_id: vpic.id})

      run = AcquisitionRuns.latest_for_vehicle(scope, vehicle)

      for step <- Enum.filter(run.steps, &(&1.provider == :nhtsa_public_corpus)) do
        assert :ok = perform_job(StepWorker, %{step_id: step.id})
      end

      {:ok, view, _html} = live(conn, ~p"/bench/vehicles/#{vehicle.id}")

      assert has_element?(view, "#nhtsa-reference-findings")
      assert has_element?(view, "#recall-campaign-count", "2")
      assert has_element?(view, "#technical-bulletin-count", "0")

      assert has_element?(
               view,
               "article[data-step-status='no_record']",
               "Provider returned no record"
             )

      assert has_element?(
               view,
               "#reference-findings article[data-capability='recall_campaigns']",
               "model applicability; vehicle completion unknown"
             )

      assert has_element?(view, "[id^='reference-record-']", "08V123000")
      assert has_element?(view, "[id^='reference-record-']", "1996 PORSCHE 911")
      assert has_element?(view, "[id^='reference-record-']", "Corpus release 2026-08-06")

      assert has_element?(
               view,
               "a[href='https://api.nhtsa.gov/recalls/campaignNumber?campaignNumber=08V123000']",
               "Official source"
             )
    end

    test "renders terminal provider failures in the acquisition ledger", %{
      conn: conn,
      scope: scope
    } do
      Req.Test.stub(SantoApi.Vpic, fn conn -> Plug.Conn.send_resp(conn, 503, "down") end)

      assert {:ok, :created, vehicle, _run} =
               AcquisitionRuns.start_operator(scope, @nine_three)

      run = AcquisitionRuns.latest_for_vehicle(scope, vehicle)
      vpic = Enum.find(run.steps, &(&1.provider == :nhtsa_vpic))

      assert {:error, {:unexpected_status, 503}} =
               perform_job(StepWorker, %{step_id: vpic.id}, attempt: 5, max_attempts: 5)

      {:ok, view, _html} = live(conn, ~p"/bench/vehicles/#{vehicle.id}")

      assert has_element?(
               view,
               "article[data-step-key='#{vpic.step_key}'][data-step-status='failed']",
               "Lookup failed after retries"
             )

      assert has_element?(view, "article[data-step-status='failed']", "unexpected_status")
    end

    test "run-all action starts a durable run for an existing VIN", %{conn: conn} do
      {:ok, vehicle} = Registry.ingest(@cgt)
      {:ok, view, _html} = live(conn, ~p"/bench/vehicles/#{vehicle.id}")

      view
      |> element("#run-acquisition-button")
      |> render_click()

      assert %Run{status: :pending} = AcquisitionRuns.latest_for_vehicle(nil, vehicle)
      assert has_element?(view, "#acquisition-run[data-run-status='pending']")
      assert_enqueued(worker: StepWorker)
    end

    test "adjudicates a two-claim conflict with an evidencing artifact", %{conn: conn} do
      Req.Test.stub(SantoApi.Vpic, fn conn ->
        Req.Test.json(conn, SantoApi.VpicFixtures.cgt_response())
      end)

      {:ok, vehicle} = Registry.ingest(@cgt)
      {:ok, _snapshot} = Registry.ingest_vpic(vehicle)

      path = Path.expand("../../../priv/corpus/carrera_gt/window_sticker.jpg", __DIR__)

      {:ok, artifact} =
        Registry.create_upload_artifact(%{
          vehicle_id: vehicle.id,
          path: path,
          filename: "window_sticker.jpg",
          mime: "image/jpeg",
          kind: :document
        })

      claims = Registry.list_claims(vehicle.id)
      santo = Enum.find(claims, &(&1.predicate == "identity.model" and &1.method == :santo))

      vpic =
        Enum.find(claims, &(&1.predicate == "identity.model" and &1.method == :structured_api))

      {:ok, view, _html} = live(conn, ~p"/bench/vehicles/#{vehicle.id}")

      view
      |> form("#adjudicate-identity-model", %{
        "prevailing_claim_id" => santo.id,
        "evidence_artifact_ids" => [artifact.id],
        "note" => "The original window sticker identifies the Carrera GT."
      })
      |> render_submit()

      assert has_element?(view, "tr[data-claim-id='#{vpic.id}'][data-state='superseded']")
      assert has_element?(view, "#adjudications tr[data-adjudication-id]")
      refute has_element?(view, "#adjudicate-identity-model")
    end

    test "unknown vehicle id redirects to the bench index", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/bench"}}} =
               live(conn, ~p"/bench/vehicles/#{Ecto.UUID.generate()}")
    end
  end

  defp agreement_response do
    SantoApi.VpicFixtures.response(%{
      "VIN" => @nine_three,
      "Make" => "PORSCHE",
      "Model" => "911",
      "ModelYear" => "1996",
      "ErrorCode" => "0",
      "ErrorText" => "0 - VIN decoded clean"
    })
  end

  defp import_nhtsa_releases do
    recall_body =
      @recalls
      |> File.read!()
      |> drop_malformed_fixture_row()
      |> String.replace("PORSCHE\tCAYMAN\t2007", "PORSCHE\t911\t1996")

    bulletin_body = @bulletins |> File.read!() |> drop_malformed_fixture_row()

    assert {:ok, :imported, _release} =
             Corpus.import_archive(
               release_attrs(
                 :recall_campaigns,
                 "pre_2010",
                 "bench-recalls",
                 archive_body(recall_body, "FLAT_RCL.txt")
               )
             )

    assert {:ok, :imported, _release} =
             Corpus.import_archive(
               release_attrs(
                 :technical_bulletins,
                 "received_2020_2024",
                 "bench-bulletins",
                 archive_body(bulletin_body, "TSBS.txt")
               )
             )
  end

  defp release_attrs(dataset, source_key, release_key, body) do
    %{
      dataset: dataset,
      source_key: source_key,
      release_key: release_key,
      released_on: ~D[2026-08-06],
      source_url: if(dataset == :recall_campaigns, do: @recall_url, else: @bulletin_url),
      acquired_at: ~U[2026-08-06 12:00:00Z],
      media_type: "application/zip",
      rights_profile: "nhtsa-open-data-v1",
      body: body
    }
  end

  defp archive_body(body, name) do
    assert {:ok, {_filename, archive}} =
             :zip.create(~c"fixture.zip", [{String.to_charlist(name), body}], [:memory])

    archive
  end

  defp drop_malformed_fixture_row(body) do
    body
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "malformed\t"))
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end
end
