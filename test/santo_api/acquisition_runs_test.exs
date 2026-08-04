defmodule SantoApi.AcquisitionRunsTest do
  use SantoApi.DataCase, async: false

  alias SantoApi.AcquisitionRuns
  alias SantoApi.AcquisitionRuns.{Run, Step, StepWorker}
  alias SantoApi.Providers.Capability
  alias SantoApi.Registry
  alias SantoApi.Registry.{Artifact, Claim, Vehicle}
  alias SantoApi.VpicFixtures

  @vin "WP0CA298X5L001502"

  test "a new VIN snapshots the free acquisition plan and enqueues only executable steps" do
    assert {:ok, :created, %Vehicle{} = vehicle, %Run{} = created_run} =
             AcquisitionRuns.start(nil, " wp0ca298x5l001502 ")

    run = AcquisitionRuns.latest_for_vehicle(nil, vehicle)

    assert run.id == created_run.id
    assert run.status == :pending
    assert length(run.steps) == length(Capability.all())

    assert %Step{status: :complete, capability: :vin_identity, position: 0} =
             Enum.find(run.steps, &(&1.kind == :santo_decode))

    assert %Step{id: provider_step_id, status: :pending} =
             Enum.find(run.steps, &(&1.provider == :nhtsa_vpic))

    gaps = Enum.filter(run.steps, &(&1.kind == :gap))
    assert length(gaps) == length(Capability.all()) - 2
    assert Enum.all?(gaps, &(&1.status == :unsupported))

    assert_enqueued(
      worker: StepWorker,
      queue: :acquisitions,
      args: %{step_id: provider_step_id}
    )
  end

  test "an existing VIN redirects to its row without creating or refreshing a run" do
    {:ok, vehicle} = Registry.ingest(@vin)

    assert {:ok, :existing, found, nil} = AcquisitionRuns.start(nil, @vin)
    assert found.id == vehicle.id
    assert Repo.aggregate(Run, :count) == 0
    assert [] = all_enqueued(worker: StepWorker)
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

  test "a successful provider step atomically persists evidence and completes the run" do
    Req.Test.stub(SantoApi.Vpic, fn conn -> Req.Test.json(conn, VpicFixtures.cgt_response()) end)

    assert {:ok, :created, vehicle, _run} = AcquisitionRuns.start(nil, @vin)
    :ok = AcquisitionRuns.subscribe(nil, vehicle)
    step = provider_step(vehicle)

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

  test "none coverage is retained as no_record rather than a clean-history claim" do
    Req.Test.stub(SantoApi.Vpic, fn conn -> Req.Test.json(conn, %{"Results" => [%{}]}) end)

    assert {:ok, :created, vehicle, _run} = AcquisitionRuns.start(nil, @vin)
    step = provider_step(vehicle)

    assert :ok = perform_job(StepWorker, %{step_id: step.id})

    run = AcquisitionRuns.latest_for_vehicle(nil, vehicle)
    step = Enum.find(run.steps, &(&1.id == step.id))

    assert run.status == :complete
    assert step.status == :no_record
    assert step.diagnostics["coverage"] == "none"
    assert %Artifact{} = Repo.get(Artifact, step.artifact_id)

    refute Repo.exists?(
             from(c in Claim, where: c.vehicle_id == ^vehicle.id and c.method == :structured_api)
           )
  end

  test "provider errors remain retryable until the final attempt, then stay visible" do
    Req.Test.stub(SantoApi.Vpic, fn conn -> Plug.Conn.send_resp(conn, 503, "down") end)

    assert {:ok, :created, vehicle, _run} = AcquisitionRuns.start(nil, @vin)
    step = provider_step(vehicle)

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
    assert run.status == :complete
    assert failed.status == :failed
    assert failed.attempt_count == 5
    assert %DateTime{} = failed.finished_at
  end

  defp provider_step(vehicle) do
    vehicle
    |> then(&AcquisitionRuns.latest_for_vehicle(nil, &1))
    |> Map.fetch!(:steps)
    |> Enum.find(&(&1.provider == :nhtsa_vpic))
  end
end
