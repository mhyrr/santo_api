defmodule SantoApi.AcquisitionRunsTest do
  use SantoApi.DataCase, async: false

  alias SantoApi.AcquisitionRuns
  alias SantoApi.AcquisitionRuns.{Run, Step, StepWorker}
  alias SantoApi.Accounts.Scope
  alias SantoApi.AccountsFixtures
  alias SantoApi.Nhtsa.Corpus
  alias SantoApi.Providers.Capability
  alias SantoApi.Registry
  alias SantoApi.Registry.{Artifact, Claim, Vehicle}
  alias SantoApi.VpicFixtures

  @vin "WP0CA298X5L001502"
  @cayman "WP0AB29827U782968"
  @carrera_gt "WP0CA298X5L001256"
  @ferrari "ZFF75VFA8F0205055"
  @nine_three "WP0ZZZ99ZTS392124"
  @recalls Path.expand("../fixtures/nhtsa/recalls.txt", __DIR__)
  @bulletins Path.expand("../fixtures/nhtsa/technical_bulletins.txt", __DIR__)
  @recall_url "https://static.nhtsa.gov/odi/ffdd/rcl/FLAT_RCL_PRE_2010.zip"
  @bulletin_url "https://static.nhtsa.gov/odi/ffdd/tsbs/TSBS_RECEIVED_2020-2024.zip"

  test "a new VIN snapshots the free acquisition plan and enqueues only executable steps" do
    assert {:ok, :created, %Vehicle{} = vehicle, %Run{} = created_run} =
             AcquisitionRuns.start(nil, " wp0ca298x5l001502 ")

    run = AcquisitionRuns.latest_for_vehicle(nil, vehicle)

    assert run.id == created_run.id
    assert run.status == :pending
    assert length(run.steps) == length(Capability.all())

    assert %Step{status: :complete, capability: :vin_identity, position: 0} =
             Enum.find(run.steps, &(&1.kind == :santo_decode))

    assert %Step{id: provider_step_id, status: :pending, depends_on_step_id: nil} =
             Enum.find(run.steps, &(&1.provider == :nhtsa_vpic))

    nhtsa_steps = Enum.filter(run.steps, &(&1.provider == :nhtsa_public_corpus))
    assert Enum.map(nhtsa_steps, & &1.capability) == [:recall_campaigns, :technical_bulletins]
    assert Enum.all?(nhtsa_steps, &(&1.status == :pending))
    assert Enum.all?(nhtsa_steps, &(&1.depends_on_step_id == provider_step_id))
    assert Enum.all?(nhtsa_steps, &(&1.selectors == %{}))

    gaps = Enum.filter(run.steps, &(&1.kind == :gap))
    assert length(gaps) == length(Capability.all()) - 4
    assert Enum.all?(gaps, &(&1.status == :unsupported))

    assert_enqueued(
      worker: StepWorker,
      queue: :acquisitions,
      args: %{step_id: provider_step_id}
    )

    assert {:error, :dependency_not_ready} =
             perform_job(StepWorker, %{step_id: hd(nhtsa_steps).id})
  end

  test "an existing VIN redirects to its row without creating or refreshing a run" do
    {:ok, vehicle} = Registry.ingest(@vin)

    assert {:ok, :existing, found, nil} = AcquisitionRuns.start(nil, @vin)
    assert found.id == vehicle.id
    assert Repo.aggregate(Run, :count) == 0
    assert [] = all_enqueued(worker: StepWorker)
  end

  test "an operator starts a run for an existing VIN and active submissions are idempotent" do
    operator = AccountsFixtures.operator_fixture()
    scope = Scope.for_user(operator)
    {:ok, vehicle} = Registry.ingest(@vin)

    assert {:ok, :restarted, found, %Run{} = run} =
             AcquisitionRuns.start_operator(scope, @vin)

    assert found.id == vehicle.id
    assert run.initiated_by_user_id == operator.id

    assert {:ok, :active, %Vehicle{id: vehicle_id}, %Run{id: active_run_id}} =
             AcquisitionRuns.start_operator(scope, @vin)

    assert vehicle_id == vehicle.id
    assert active_run_id == run.id
    assert Repo.aggregate(Run, :count) == 1
    assert [_job] = all_enqueued(worker: StepWorker)
  end

  test "an operator can refresh a completed acquisition with a new immutable run" do
    Req.Test.stub(SantoApi.Vpic, fn conn -> Req.Test.json(conn, VpicFixtures.cgt_response()) end)

    scope = AccountsFixtures.operator_fixture() |> Scope.for_user()

    assert {:ok, :created, vehicle, first_run} =
             AcquisitionRuns.start_operator(scope, @vin)

    assert :ok = perform_job(StepWorker, %{step_id: vpic_step(vehicle).id})

    assert {:ok, :restarted, %Vehicle{id: vehicle_id}, second_run} =
             AcquisitionRuns.start_operator(scope, @vin)

    assert vehicle_id == vehicle.id
    refute second_run.id == first_run.id
    assert Repo.aggregate(Run, :count) == 2
    assert length(all_enqueued(worker: StepWorker)) == 2
  end

  test "operator ingestion keeps chassis identities without planning VIN providers" do
    scope = AccountsFixtures.operator_fixture() |> Scope.for_user()

    assert {:ok, :registered, %Vehicle{identity_kind: :chassis}, nil} =
             AcquisitionRuns.start_operator(scope, "9113600471")

    assert Repo.aggregate(Run, :count) == 0
    assert [] = all_enqueued(worker: StepWorker)
  end

  test "operator acquisition rejects a non-operator scope" do
    scope = AccountsFixtures.user_fixture() |> Scope.for_user()

    assert {:error, :unauthorized} = AcquisitionRuns.start_operator(scope, @vin)
    assert Repo.aggregate(Vehicle, :count) == 0
    assert Repo.aggregate(Run, :count) == 0
  end

  test "duplicate submissions converge on one vehicle, run, and job" do
    supervisor = start_supervised!(Task.Supervisor)

    results =
      for _ <- 1..2 do
        Task.Supervisor.async_nolink(supervisor, fn -> AcquisitionRuns.start(nil, @vin) end)
      end
      |> Enum.map(&Task.await(&1, 5_000))

    assert Enum.sort(Enum.map(results, fn {:ok, disposition, _, _} -> disposition end)) ==
             [:created, :existing]

    assert Repo.aggregate(Vehicle, :count) == 1
    assert Repo.aggregate(Run, :count) == 1
    assert [_job] = all_enqueued(worker: StepWorker)
  end

  test "invalid and non-VIN input create nothing" do
    assert {:error, %Santo.Invalid{}} = AcquisitionRuns.start(nil, "12345678")
    assert {:error, :vin_required} = AcquisitionRuns.start(nil, "9113600471")

    assert Repo.aggregate(Vehicle, :count) == 0
    assert Repo.aggregate(Run, :count) == 0
    assert [] = all_enqueued(worker: StepWorker)
  end

  test "Carrera GT selector conflict is durable and never releases an NHTSA request" do
    response = VpicFixtures.cgt_values() |> Map.put("VIN", @carrera_gt) |> VpicFixtures.response()
    Req.Test.stub(SantoApi.Vpic, fn conn -> Req.Test.json(conn, response) end)

    assert {:ok, :created, vehicle, _run} = AcquisitionRuns.start(nil, @carrera_gt)
    assert :ok = perform_job(StepWorker, %{step_id: vpic_step(vehicle).id})

    run = AcquisitionRuns.latest_for_vehicle(nil, vehicle)
    assert run.status == :complete

    assert Enum.all?(nhtsa_steps(run), fn step ->
             step.status == :needs_input and step.missing_selectors == [] and
               step.conflicted_selectors == ["identity.model"] and
               step.selectors == %{"marque" => "porsche", "model_year" => 2005}
           end)

    assert [_vpic_job] = all_enqueued(worker: StepWorker)
  end

  test "Cayman selector conflict is durable and never releases an NHTSA request" do
    Req.Test.stub(SantoApi.Vpic, fn conn ->
      Req.Test.json(conn, VpicFixtures.cayman_response())
    end)

    assert {:ok, :created, vehicle, _run} = AcquisitionRuns.start(nil, @cayman)
    assert :ok = perform_job(StepWorker, %{step_id: vpic_step(vehicle).id})

    run = AcquisitionRuns.latest_for_vehicle(nil, vehicle)
    assert run.status == :complete

    assert Enum.all?(nhtsa_steps(run), fn step ->
             step.status == :needs_input and step.missing_selectors == [] and
               step.conflicted_selectors == ["identity.model"] and
               step.selectors == %{"marque" => "porsche", "model_year" => 2007}
           end)

    assert [_vpic_job] = all_enqueued(worker: StepWorker)
  end

  test "thin reviewed Ferrari identity finishes dependent steps as needs_input" do
    scope = AccountsFixtures.operator_fixture() |> Scope.for_user()
    assert {:ok, vehicle} = Registry.register_vin(:ferrari, @ferrari)

    Req.Test.stub(SantoApi.Vpic, fn conn ->
      Req.Test.json(conn, VpicFixtures.response(%{"VIN" => @ferrari}))
    end)

    assert {:ok, :restarted, ^vehicle, _run} = AcquisitionRuns.start_operator(scope, @ferrari)
    assert :ok = perform_job(StepWorker, %{step_id: vpic_step(vehicle).id})

    run = AcquisitionRuns.latest_for_vehicle(nil, vehicle)
    assert run.status == :complete

    assert Enum.all?(nhtsa_steps(run), fn step ->
             step.status == :needs_input and
               step.missing_selectors == [
                 "identity.marque",
                 "identity.model",
                 "identity.model_year"
               ] and step.conflicted_selectors == [] and step.selectors == %{}
           end)

    assert [_vpic_job] = all_enqueued(worker: StepWorker)
  end

  test "vPIC and Santo agreement snapshots selectors and releases dependent jobs" do
    Req.Test.stub(SantoApi.Vpic, fn conn ->
      Req.Test.json(conn, agreement_response(@nine_three))
    end)

    assert {:ok, :created, vehicle, _run} = AcquisitionRuns.start(nil, @nine_three)
    vpic = vpic_step(vehicle)

    assert :ok = perform_job(StepWorker, %{step_id: vpic.id})

    run = AcquisitionRuns.latest_for_vehicle(nil, vehicle)
    assert run.status == :running

    assert Enum.all?(nhtsa_steps(run), fn step ->
             step.status == :pending and step.depends_on_step_id == vpic.id and
               step.selectors == %{
                 "marque" => "porsche",
                 "model" => %{"code" => "911", "label" => nil},
                 "model_year" => 1996
               }
           end)

    assert length(all_enqueued(worker: StepWorker)) == 3
  end

  test "both NHTSA capabilities complete, persist no-match snapshots, and create no vehicle claims" do
    import_nhtsa_releases()

    Req.Test.stub(SantoApi.Vpic, fn conn ->
      Req.Test.json(conn, agreement_response(@nine_three))
    end)

    assert {:ok, :created, vehicle, _run} = AcquisitionRuns.start(nil, @nine_three)
    assert :ok = perform_job(StepWorker, %{step_id: vpic_step(vehicle).id})

    claim_count = Repo.aggregate(from(c in Claim, where: c.vehicle_id == ^vehicle.id), :count)

    run = AcquisitionRuns.latest_for_vehicle(nil, vehicle)
    recall = Enum.find(run.steps, &(&1.capability == :recall_campaigns))
    bulletin = Enum.find(run.steps, &(&1.capability == :technical_bulletins))

    assert :ok = perform_job(StepWorker, %{step_id: recall.id})
    assert :ok = perform_job(StepWorker, %{step_id: bulletin.id})

    run = AcquisitionRuns.latest_for_vehicle(nil, vehicle)
    recall = Enum.find(run.steps, &(&1.id == recall.id))
    bulletin = Enum.find(run.steps, &(&1.id == bulletin.id))

    assert run.status == :complete
    assert recall.status == :complete
    assert recall.diagnostics["coverage"] == "complete"
    assert bulletin.status == :no_record
    assert bulletin.diagnostics["coverage"] == "none"
    assert %Artifact{} = Repo.get(Artifact, recall.artifact_id)
    assert %Artifact{} = Repo.get(Artifact, bulletin.artifact_id)

    assert Repo.aggregate(from(c in Claim, where: c.vehicle_id == ^vehicle.id), :count) ==
             claim_count

    refute Repo.exists?(
             from(c in Claim,
               where:
                 c.vehicle_id == ^vehicle.id and
                   c.predicate in ["event.service", "open_recall_status"]
             )
           )

    findings = Registry.reference_findings([recall.artifact_id, bulletin.artifact_id])
    assert Enum.map(findings, & &1.capability) == ["recall_campaigns", "technical_bulletins"]
    assert Enum.map(findings, & &1.coverage) == ["complete", "none"]
    assert [first | _rest] = hd(findings).records
    assert first["identifier"] == "08V123000"
    assert first["source_url"] =~ "api.nhtsa.gov/recalls/campaignNumber"
  end

  test "a retry uses its selector snapshot even if live identity claims later change" do
    Req.Test.stub(SantoApi.Vpic, fn conn ->
      Req.Test.json(conn, agreement_response(@nine_three))
    end)

    assert {:ok, :created, vehicle, _run} = AcquisitionRuns.start(nil, @nine_three)
    assert :ok = perform_job(StepWorker, %{step_id: vpic_step(vehicle).id})

    run = AcquisitionRuns.latest_for_vehicle(nil, vehicle)
    recall = Enum.find(run.steps, &(&1.capability == :recall_campaigns))
    original_selectors = recall.selectors

    assert {:error, :corpus_unavailable} =
             perform_job(StepWorker, %{step_id: recall.id}, attempt: 1, max_attempts: 5)

    assert {:ok, _claim} =
             Registry.propose_claim(vehicle, %{
               predicate: "identity.model",
               value: %{"code" => "cayman", "label" => nil}
             })

    import_nhtsa_releases()

    assert :ok = perform_job(StepWorker, %{step_id: recall.id}, attempt: 2, max_attempts: 5)

    recall = Repo.get!(Step, recall.id)
    artifact = Repo.get!(Artifact, recall.artifact_id)
    assert recall.status == :complete
    assert recall.selectors == original_selectors
    assert artifact.payload["selectors"] == original_selectors

    assert Enum.map(artifact.payload["records"], & &1["identifier"]) ==
             ["08V123000", "09V456000"]
  end

  test "a successful identity step atomically persists evidence" do
    Req.Test.stub(SantoApi.Vpic, fn conn -> Req.Test.json(conn, VpicFixtures.cgt_response()) end)

    assert {:ok, :created, vehicle, _run} = AcquisitionRuns.start(nil, @vin)
    :ok = AcquisitionRuns.subscribe(nil, vehicle)
    step = vpic_step(vehicle)

    assert :ok = perform_job(StepWorker, %{step_id: step.id})
    assert_receive {:acquisition_run_updated, _run_id}
    assert_receive {:acquisition_run_updated, _run_id}

    run = AcquisitionRuns.latest_for_vehicle(nil, vehicle)
    step = Enum.find(run.steps, &(&1.id == step.id))

    assert run.status == :complete
    assert %DateTime{} = run.finished_at
    assert step.status == :complete
    assert step.attempt_count == 1
    assert step.diagnostics["coverage"] == "complete"
    assert %Artifact{} = Repo.get(Artifact, step.artifact_id)

    assert Enum.all?(nhtsa_steps(run), fn dependent ->
             dependent.status == :needs_input and
               dependent.conflicted_selectors == ["identity.model"]
           end)

    assert Repo.aggregate(
             from(c in Claim,
               where:
                 c.vehicle_id == ^vehicle.id and c.method == :structured_api and
                   c.state == :proposed
             ),
             :count
           ) == 3

    # A duplicate delivery sees the terminal step before writing another
    # acquisition snapshot.
    assert :ok = perform_job(StepWorker, %{step_id: step.id}, attempt: 2)
    assert Repo.aggregate(Artifact, :count) == 1
  end

  test "vPIC none coverage persists an artifact and releases selectors from Santo" do
    Req.Test.stub(SantoApi.Vpic, fn conn -> Req.Test.json(conn, %{"Results" => [%{}]}) end)

    assert {:ok, :created, vehicle, _run} = AcquisitionRuns.start(nil, @vin)
    step = vpic_step(vehicle)

    assert :ok = perform_job(StepWorker, %{step_id: step.id})

    run = AcquisitionRuns.latest_for_vehicle(nil, vehicle)
    step = Enum.find(run.steps, &(&1.id == step.id))

    assert run.status == :running
    assert step.status == :no_record
    assert step.diagnostics["coverage"] == "none"
    assert %Artifact{} = Repo.get(Artifact, step.artifact_id)

    refute Repo.exists?(
             from(c in Claim, where: c.vehicle_id == ^vehicle.id and c.method == :structured_api)
           )

    assert Enum.all?(nhtsa_steps(run), fn dependent ->
             dependent.status == :pending and dependent.selectors["model"]["code"] == "carrera_gt"
           end)
  end

  test "provider errors remain retryable until the final attempt, then stay visible" do
    Req.Test.stub(SantoApi.Vpic, fn conn -> Plug.Conn.send_resp(conn, 503, "down") end)

    assert {:ok, :created, vehicle, _run} = AcquisitionRuns.start(nil, @vin)
    step = vpic_step(vehicle)

    assert {:error, {:unexpected_status, 503}} =
             perform_job(StepWorker, %{step_id: step.id}, attempt: 1, max_attempts: 5)

    run = AcquisitionRuns.latest_for_vehicle(nil, vehicle)
    retrying = Enum.find(run.steps, &(&1.id == step.id))
    assert run.status == :running
    assert retrying.status == :pending
    assert retrying.attempt_count == 1
    assert retrying.last_error["reason"] =~ "unexpected_status"

    assert {:error, {:unexpected_status, 503}} =
             perform_job(StepWorker, %{step_id: step.id}, attempt: 5, max_attempts: 5)

    run = AcquisitionRuns.latest_for_vehicle(nil, vehicle)
    failed = Enum.find(run.steps, &(&1.id == step.id))
    assert run.status == :running
    assert failed.status == :failed
    assert failed.attempt_count == 5
    assert %DateTime{} = failed.finished_at

    for dependent <- nhtsa_steps(run) do
      assert {:error, :corpus_unavailable} =
               perform_job(StepWorker, %{step_id: dependent.id}, attempt: 1, max_attempts: 2)

      retrying = Repo.get!(Step, dependent.id)
      assert retrying.status == :pending
      assert retrying.selectors["model"]["code"] == "carrera_gt"

      assert {:error, :corpus_unavailable} =
               perform_job(StepWorker, %{step_id: dependent.id}, attempt: 2, max_attempts: 2)
    end

    run = AcquisitionRuns.latest_for_vehicle(nil, vehicle)
    assert run.status == :complete
    assert Enum.all?(nhtsa_steps(run), &(&1.status == :failed and &1.attempt_count == 2))
  end

  defp vpic_step(vehicle) do
    vehicle
    |> then(&AcquisitionRuns.latest_for_vehicle(nil, &1))
    |> Map.fetch!(:steps)
    |> Enum.find(&(&1.provider == :nhtsa_vpic))
  end

  defp nhtsa_steps(%Run{} = run),
    do: Enum.filter(run.steps, &(&1.provider == :nhtsa_public_corpus))

  defp agreement_response(vin) do
    VpicFixtures.response(%{
      "VIN" => vin,
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
                 "acquisition-test-recalls",
                 archive_body(recall_body, "FLAT_RCL.txt")
               )
             )

    assert {:ok, :imported, _release} =
             Corpus.import_archive(
               release_attrs(
                 :technical_bulletins,
                 "received_2020_2024",
                 "acquisition-test-bulletins",
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
