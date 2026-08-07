defmodule SantoApi.AcquisitionRuns do
  @moduledoc """
  Durable orchestration for building a public vehicle record.

  Runs and steps are the product ledger: they say what Santo tried and what is
  still unknown. Oban supplies delivery and retry mechanics without becoming
  the public read model.
  """

  import Ecto.Query, warn: false

  alias SantoApi.Accounts
  alias SantoApi.Accounts.{Scope, User}
  alias SantoApi.AcquisitionRuns.{Run, Step, StepWorker}
  alias SantoApi.Providers
  alias SantoApi.Providers.{Acquisition, Capability, Request, Selector}
  alias SantoApi.Registry
  alias SantoApi.Registry.Vehicle
  alias SantoApi.Repo

  @terminal_step_statuses [:complete, :no_record, :needs_input, :failed, :unsupported]
  @pubsub SantoApi.PubSub

  @doc """
  Start the free public build for a normalized standard VIN.

  Existing vehicles are returned without a run. For a new vehicle, creation of
  the registry row, plan, and provider jobs is one transaction.
  """
  def start(%Scope{} = scope, input), do: do_start(scope, input)
  def start(nil, input), do: do_start(nil, input)

  @doc """
  Start the free acquisition plan from the operator bench.

  Unlike the anonymous public action, an operator may refresh an existing VIN.
  An already-active run is returned rather than duplicated. Non-VIN identities
  are still registered for bench work, but receive no VIN-only provider plan.
  """
  def start_operator(%Scope{} = scope, input) do
    with :ok <- authorize_operator(scope) do
      case normalize_vin(input) do
        {:ok, vin} -> do_start_operator(scope, vin)
        {:error, :vin_required} -> register_non_vin(input)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def start_operator(_scope, _input), do: {:error, :unauthorized}

  @doc """
  The newest run and its ordered step ledger for a public vehicle.
  """
  def latest_for_vehicle(%Scope{} = _scope, %Vehicle{} = vehicle),
    do: do_latest_for_vehicle(vehicle)

  def latest_for_vehicle(nil, %Vehicle{} = vehicle), do: do_latest_for_vehicle(vehicle)

  @doc """
  Subscribe the caller to durable run changes for a public vehicle.
  """
  def subscribe(%Scope{} = _scope, %Vehicle{} = vehicle), do: subscribe_vehicle(vehicle)
  def subscribe(nil, %Vehicle{} = vehicle), do: subscribe_vehicle(vehicle)

  @doc false
  def perform_step(scope, step_id, attempt, max_attempts)
      when (is_nil(scope) or is_struct(scope, Scope)) and is_binary(step_id) and attempt > 0 and
             max_attempts > 0 do
    case claim_step(step_id, attempt) do
      {:ok, {:finished, run}} ->
        broadcast(run)
        {:ok, :already_finished}

      {:ok, {:execute, step, vehicle, run}} ->
        broadcast(run)
        acquire_step(step, vehicle, attempt, max_attempts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  def record_exception(scope, step_id, attempt, max_attempts, exception)
      when (is_nil(scope) or is_struct(scope, Scope)) and is_binary(step_id) do
    payload = %{
      "exception" => exception.__struct__ |> Module.split() |> Enum.join("."),
      "message" => Exception.message(exception)
    }

    settle_error(step_id, attempt, max_attempts, payload)
  end

  defp do_start(scope, input) do
    with {:ok, vin} <- normalize_vin(input) do
      case Repo.transaction(fn -> start_locked(scope, vin) end) do
        {:ok, {:created, vehicle, run}} ->
          broadcast(run)
          {:ok, :created, vehicle, run}

        {:ok, {:existing, vehicle}} ->
          {:ok, :existing, vehicle, nil}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp do_start_operator(scope, vin) do
    case Repo.transaction(fn -> start_operator_locked(scope, vin) end) do
      {:ok, {disposition, vehicle, run}} ->
        broadcast(run)
        {:ok, disposition, vehicle, run}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_vin(input) when is_binary(input) do
    normalized = Santo.Normalize.normalize(input)

    case Santo.Identity.key(normalized) do
      {:ok, {:vin, ^normalized}} -> {:ok, normalized}
      {:ok, _other_identity} -> {:error, :vin_required}
      {:error, %Santo.Invalid{} = invalid} -> {:error, invalid}
    end
  end

  defp normalize_vin(_input), do: {:error, :vin_required}

  defp authorize_operator(scope) do
    if Accounts.operator?(scope), do: :ok, else: {:error, :unauthorized}
  end

  defp register_non_vin(input) do
    case Registry.ingest(input) do
      {:ok, %Vehicle{identity_kind: :vin}} -> {:error, :vin_required}
      {:ok, %Vehicle{} = vehicle} -> {:ok, :registered, vehicle, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp start_locked(scope, vin) do
    identity_key = "vin:" <> vin
    lock_identity(identity_key)

    case Registry.resolve_vin(vin) do
      {:ok, vehicle} ->
        {:existing, vehicle}

      {:error, :not_found} ->
        {:ok, vehicle} = Registry.ingest(vin)
        {:created, vehicle, create_run(scope, vin, vehicle)}
    end
  end

  defp start_operator_locked(scope, vin) do
    lock_identity("vin:" <> vin)

    case Registry.resolve_vin(vin) do
      {:ok, vehicle} ->
        case active_run_for_vehicle(vehicle) do
          %Run{} = run -> {:active, vehicle, run}
          nil -> {:restarted, vehicle, create_run(scope, vin, vehicle)}
        end

      {:error, :not_found} ->
        {:ok, vehicle} = Registry.ingest(vin)
        {:created, vehicle, create_run(scope, vin, vehicle)}
    end
  end

  defp create_run(scope, vin, vehicle) do
    now = DateTime.utc_now()
    plan = plan_steps({:vin, vin}, vehicle, now)
    pending? = Enum.any?(plan, &(&1.status == :pending))

    run =
      %Run{
        vehicle_id: vehicle.id,
        initiated_by_user_id: initiated_by_user_id(scope),
        policy: :free_public_v1,
        status: if(pending?, do: :pending, else: :complete),
        finished_at: if(pending?, do: nil, else: now)
      }
      |> Repo.insert!()

    steps_with_dependencies =
      plan
      |> Enum.with_index()
      |> Enum.map(fn {attrs, position} ->
        {depends_on_step_key, attrs} = Map.pop(attrs, :depends_on_step_key)

        step =
          attrs
          |> Map.merge(%{run_id: run.id, position: position})
          |> then(&struct!(Step, &1))
          |> Repo.insert!()

        {step, depends_on_step_key}
      end)

    by_key = Map.new(steps_with_dependencies, fn {step, _dependency} -> {step.step_key, step} end)

    steps =
      Enum.map(steps_with_dependencies, fn
        {step, nil} ->
          step

        {step, depends_on_step_key} ->
          dependency = Map.fetch!(by_key, depends_on_step_key)

          step
          |> Ecto.Changeset.change(depends_on_step_id: dependency.id)
          |> Repo.update!()
      end)

    steps
    |> Enum.filter(&(&1.status == :pending and is_nil(&1.depends_on_step_id)))
    |> Enum.each(&enqueue_step!/1)

    %{run | steps: steps}
  end

  # The lock closes the get-then-create race in Registry.ingest/1 for this
  # caller. The vehicles identity-key unique index remains the final guard.
  defp lock_identity(identity_key) do
    Ecto.Adapters.SQL.query!(
      Repo,
      "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
      [identity_key]
    )
  end

  defp initiated_by_user_id(%Scope{user: %User{id: id}}), do: id
  defp initiated_by_user_id(_anonymous), do: nil

  defp plan_steps(identity, vehicle, now) do
    provider_steps =
      for capability <- Capability.all(),
          provider <- Providers.all(),
          descriptor = provider.descriptor(),
          descriptor.billing == :free,
          capability in descriptor.capabilities,
          {:ok, request} <- [Request.new(capability, identity)],
          provider.supports?(request) == :ok do
        %{
          step_key: "provider:#{descriptor.id}:#{capability}",
          kind: :provider,
          provider: descriptor.id,
          capability: capability,
          status: :pending,
          depends_on_step_key: selector_dependency(descriptor),
          diagnostics: %{
            "fulfillment" => to_string(descriptor.fulfillment),
            "billing" => to_string(descriptor.billing),
            "access_class" => to_string(descriptor.access_class),
            "required_selectors" => Enum.map(descriptor.required_selectors, &to_string/1)
          }
        }
      end

    covered_capabilities =
      provider_steps
      |> Enum.map(& &1.capability)
      |> MapSet.new()
      |> MapSet.put(:vin_identity)

    gaps =
      for capability <- Capability.all(),
          not MapSet.member?(covered_capabilities, capability) do
        %{
          step_key: "gap:#{capability}",
          kind: :gap,
          provider: nil,
          capability: capability,
          status: :unsupported,
          diagnostics: %{"reason" => "no_free_provider"},
          finished_at: now
        }
      end

    santo_step = %{
      step_key: "santo_decode",
      kind: :santo_decode,
      provider: nil,
      capability: :vin_identity,
      status: :complete,
      diagnostics: %{
        "decode" => decode_outcome(vehicle),
        "santo_version" => vehicle.santo_version
      },
      finished_at: now
    }

    [santo_step | provider_steps ++ gaps]
  end

  defp decode_outcome(%Vehicle{decode_snapshot: %{"ambiguous" => _}}), do: "ambiguous"
  defp decode_outcome(%Vehicle{decode_snapshot: snapshot}) when is_map(snapshot), do: "decoded"
  defp decode_outcome(%Vehicle{}), do: "unavailable"

  defp selector_dependency(%{required_selectors: []}), do: nil

  defp selector_dependency(%{required_selectors: required}) when is_list(required),
    do: "provider:nhtsa_vpic:generic_specifications"

  defp do_latest_for_vehicle(vehicle) do
    Repo.one(
      from(r in Run,
        where: r.vehicle_id == ^vehicle.id,
        order_by: [desc: r.inserted_at],
        limit: 1,
        preload: [steps: ^ordered_steps_query()]
      )
    )
  end

  defp active_run_for_vehicle(vehicle) do
    Repo.one(
      from(r in Run,
        where: r.vehicle_id == ^vehicle.id and r.status in [:pending, :running],
        limit: 1,
        preload: [steps: ^ordered_steps_query()]
      )
    )
  end

  defp ordered_steps_query, do: from(s in Step, order_by: [asc: s.position])

  defp subscribe_vehicle(vehicle) do
    Phoenix.PubSub.subscribe(@pubsub, topic(vehicle.id))
  end

  defp acquire_step(step, vehicle, attempt, max_attempts) do
    with {:ok, selectors} <- Selector.new(step.selectors),
         {:ok, request} <- Request.new(step.capability, {:vin, vehicle.input}, selectors) do
      case Providers.acquire(step.provider, request) do
        {:ok, %Acquisition{} = acquisition} ->
          settle_acquisition(step.id, acquisition)

        {:pending, metadata} ->
          settle_pending(step.id, metadata, attempt, max_attempts)

        {:error, reason} ->
          settle_provider_error(step.id, reason, attempt, max_attempts)
      end
    else
      {:error, reason} ->
        settle_provider_error(step.id, reason, attempt, max_attempts)
    end
  end

  defp settle_acquisition(step_id, acquisition) do
    result =
      Repo.transaction(fn ->
        {run, step} = lock_run_and_step(step_id)

        if terminal?(step) do
          {:finished, run, step.status}
        else
          vehicle = Repo.get!(Vehicle, run.vehicle_id)

          artifact =
            case Registry.record_acquisition(vehicle, acquisition) do
              {:ok, artifact} -> artifact
              {:error, reason} -> Repo.rollback(reason)
            end

          status = if acquisition.coverage == :none, do: :no_record, else: :complete
          now = DateTime.utc_now()

          step =
            step
            |> Ecto.Changeset.change(
              artifact_id: artifact.id,
              status: status,
              diagnostics: %{
                "coverage" => to_string(acquisition.coverage),
                "provider" => acquisition.diagnostics
              },
              last_error: nil,
              finished_at: now
            )
            |> Repo.update!()

          run = release_dependents(run, step, now)
          run = maybe_finish_run(run, now)
          {:finished, run, step.status}
        end
      end)

    case result do
      {:ok, {:finished, run, status}} ->
        broadcast(run)
        {:ok, status}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp settle_pending(step_id, metadata, attempt, max_attempts) do
    case missing_selectors(metadata) do
      [] -> settle_provider_error(step_id, {:provider_pending, metadata}, attempt, max_attempts)
      selectors -> settle_needs_input(step_id, selectors, metadata)
    end
  end

  defp missing_selectors(%{missing_selectors: selectors}) when is_list(selectors),
    do: Enum.map(selectors, &to_string/1)

  defp missing_selectors(%{"missing_selectors" => selectors}) when is_list(selectors),
    do: Enum.map(selectors, &to_string/1)

  defp missing_selectors(_metadata), do: []

  defp settle_needs_input(step_id, selectors, metadata) do
    result =
      Repo.transaction(fn ->
        {run, step} = lock_run_and_step(step_id)

        if terminal?(step) do
          {:finished, run, step.status}
        else
          now = DateTime.utc_now()

          step =
            step
            |> Ecto.Changeset.change(
              status: :needs_input,
              missing_selectors: selectors,
              diagnostics: %{"provider" => metadata},
              last_error: nil,
              finished_at: now
            )
            |> Repo.update!()

          run = release_dependents(run, step, now)
          run = maybe_finish_run(run, now)
          {:finished, run, step.status}
        end
      end)

    case result do
      {:ok, {:finished, run, status}} ->
        broadcast(run)
        {:ok, status}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp settle_provider_error(step_id, reason, attempt, max_attempts) do
    payload = %{"reason" => inspect(reason, limit: 20, printable_limit: 1_000)}

    case settle_error(step_id, attempt, max_attempts, payload) do
      {:ok, _status} -> {:error, reason}
      {:error, transition_reason} -> {:error, transition_reason}
    end
  end

  defp settle_error(step_id, attempt, max_attempts, payload) do
    result =
      Repo.transaction(fn ->
        {run, step} = lock_run_and_step(step_id)

        if terminal?(step) do
          {:settled, run, step.status}
        else
          final_attempt? = attempt >= max_attempts
          now = DateTime.utc_now()

          step =
            step
            |> Ecto.Changeset.change(
              status: if(final_attempt?, do: :failed, else: :pending),
              attempt_count: max(step.attempt_count, attempt),
              last_error: payload,
              finished_at: if(final_attempt?, do: now, else: nil)
            )
            |> Repo.update!()

          run = if final_attempt?, do: release_dependents(run, step, now), else: run
          run = if final_attempt?, do: maybe_finish_run(run, now), else: run
          {:settled, run, step.status}
        end
      end)

    case result do
      {:ok, {:settled, run, status}} ->
        broadcast(run)
        {:ok, status}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp claim_step(step_id, attempt) do
    Repo.transaction(fn ->
      {run, step} = lock_run_and_step(step_id)

      cond do
        terminal?(step) ->
          {:finished, run}

        step.kind != :provider ->
          Repo.rollback(:step_not_executable)

        !dependency_terminal?(step) ->
          Repo.rollback(:dependency_not_ready)

        !selector_snapshot_ready?(step) ->
          Repo.rollback(:selectors_unresolved)

        true ->
          now = DateTime.utc_now()

          run =
            if run.status == :running do
              run
            else
              run
              |> Ecto.Changeset.change(status: :running, started_at: run.started_at || now)
              |> Repo.update!()
            end

          step =
            step
            |> Ecto.Changeset.change(
              status: :running,
              attempt_count: max(step.attempt_count, attempt),
              started_at: step.started_at || now,
              finished_at: nil
            )
            |> Repo.update!()

          vehicle = Repo.get!(Vehicle, run.vehicle_id)
          {:execute, step, vehicle, run}
      end
    end)
  end

  # Lock the aggregate first. Two provider workers finishing together must not
  # both observe the other's old state and leave the run permanently running.
  defp lock_run_and_step(step_id) do
    case Repo.get(Step, step_id) do
      nil ->
        Repo.rollback(:not_found)

      %Step{run_id: run_id} ->
        run = Repo.one!(from(r in Run, where: r.id == ^run_id, lock: "FOR UPDATE"))
        step = Repo.one!(from(s in Step, where: s.id == ^step_id, lock: "FOR UPDATE"))
        {run, step}
    end
  end

  defp maybe_finish_run(run, now) do
    unfinished? =
      Repo.exists?(
        from(s in Step,
          where: s.run_id == ^run.id and s.status in [:pending, :running]
        )
      )

    if unfinished? do
      run
    else
      run
      |> Ecto.Changeset.change(status: :complete, finished_at: now)
      |> Repo.update!()
    end
  end

  defp release_dependents(run, completed_step, now) do
    dependents =
      Repo.all(
        from(s in Step,
          where: s.depends_on_step_id == ^completed_step.id and s.status == :pending,
          order_by: s.position,
          lock: "FOR UPDATE"
        )
      )

    case dependents do
      [] ->
        run

      dependents ->
        case Registry.resolve_identity_selectors(run.vehicle_id) do
          {:ok, selectors} ->
            selector_map = Selector.to_map(selectors)

            Enum.each(dependents, fn step ->
              step =
                step
                |> Ecto.Changeset.change(
                  selectors: selector_map,
                  missing_selectors: [],
                  conflicted_selectors: [],
                  diagnostics:
                    Map.put(step.diagnostics, "selector_resolution", %{
                      "resolved_after" => completed_step.step_key,
                      "selectors" => selector_map
                    })
                )
                |> Repo.update!()

              enqueue_step!(step)
            end)

            run

          {:needs_input, resolution} ->
            selector_map = Selector.to_map(resolution.selectors)

            Enum.each(dependents, fn step ->
              step
              |> Ecto.Changeset.change(
                status: :needs_input,
                selectors: selector_map,
                missing_selectors: resolution.missing_predicates,
                conflicted_selectors: resolution.conflicted_predicates,
                diagnostics:
                  Map.put(step.diagnostics, "selector_resolution", %{
                    "resolved_after" => completed_step.step_key,
                    "selectors" => selector_map,
                    "missing_predicates" => resolution.missing_predicates,
                    "conflicted_predicates" => resolution.conflicted_predicates
                  }),
                finished_at: now
              )
              |> Repo.update!()
            end)

            run
        end
    end
  end

  defp dependency_terminal?(%Step{depends_on_step_id: nil}), do: true

  defp dependency_terminal?(%Step{depends_on_step_id: dependency_id}) do
    case Repo.get(Step, dependency_id) do
      %Step{status: status} -> status in @terminal_step_statuses
      nil -> false
    end
  end

  defp selector_snapshot_ready?(step) do
    with {:ok, provider} <- Providers.provider(step.provider),
         {:ok, selectors} <- Selector.new(step.selectors) do
      Selector.required_missing(selectors, provider.descriptor().required_selectors) == []
    else
      _error -> false
    end
  end

  defp enqueue_step!(step) do
    %{step_id: step.id}
    |> StepWorker.new()
    |> Oban.insert!()
  end

  defp terminal?(%Step{status: status}), do: status in @terminal_step_statuses

  defp broadcast(run) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      topic(run.vehicle_id),
      {:acquisition_run_updated, run.id}
    )
  end

  defp topic(vehicle_id), do: "acquisition:vehicle:#{vehicle_id}"
end
