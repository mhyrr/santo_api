defmodule SantoApi.AcquisitionRuns.StepWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :acquisitions,
    max_attempts: 5,
    unique: [period: :infinity, keys: [:step_id], states: :incomplete]

  alias SantoApi.AcquisitionRuns

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"step_id" => step_id},
        attempt: attempt,
        max_attempts: max_attempts
      }) do
    case AcquisitionRuns.perform_step(nil, step_id, attempt, max_attempts) do
      {:ok, _status} ->
        :ok

      {:error, :not_found} ->
        {:cancel, "acquisition step not found"}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    exception ->
      stacktrace = __STACKTRACE__

      _ =
        AcquisitionRuns.record_exception(
          nil,
          step_id,
          attempt,
          max_attempts,
          exception
        )

      reraise exception, stacktrace
  end
end
