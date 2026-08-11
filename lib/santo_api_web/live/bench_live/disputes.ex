defmodule SantoApiWeb.BenchLive.Disputes do
  @moduledoc """
  The operator queue for contested possession challenges (owner_surface §4, §9.2).

  These are authorization disputes, not Registry claim conflicts. The queue is
  derived from submitted possession challenges that face a different active
  steward. A decision keeps the incumbent or atomically transfers stewardship;
  it never writes an ownership claim or edits either person's ledger history.
  """

  use SantoApiWeb, :live_view

  alias SantoApi.Bench
  alias SantoApiWeb.VehicleLive.Presenter

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:queue_state, :loading)
     |> assign(:queue_count, 0)
     |> assign(:error, nil)
     |> assign(:last_decision, nil)
     |> stream_configure(:disputes, dom_id: &"dispute-#{&1.id}")
     |> stream(:disputes, [])
     |> load_queue()}
  end

  @impl true
  def handle_async(:load_disputes, {:ok, {:ok, rows}}, socket) do
    rows = Enum.map(rows, &decorate/1)

    {:noreply,
     socket
     |> assign(:queue_state, :ready)
     |> assign(:queue_count, length(rows))
     |> assign(:error, nil)
     |> stream(:disputes, rows, reset: true)}
  end

  def handle_async(:load_disputes, {:ok, {:error, reason}}, socket) do
    {:noreply, load_failed(socket, reason)}
  end

  def handle_async(:load_disputes, {:exit, reason}, socket) do
    {:noreply, load_failed(socket, reason)}
  end

  @impl true
  def handle_event("reload", _params, socket) do
    {:noreply, socket |> assign(:queue_state, :loading) |> assign(:error, nil) |> load_queue()}
  end

  def handle_event(
        "resolve",
        %{
          "decision" => %{
            "challenge_id" => challenge_id,
            "outcome" => outcome,
            "reason" => reason
          }
        },
        socket
      ) do
    with {:ok, outcome} <- cast_outcome(outcome),
         :ok <- validate_reason(reason) do
      resolve(socket, challenge_id, outcome, String.trim(reason))
    else
      {:error, message} ->
        {:noreply, socket |> assign(:last_decision, nil) |> assign(:error, message)}
    end
  end

  def handle_event("resolve", _params, socket) do
    {:noreply,
     socket
     |> assign(:last_decision, nil)
     |> assign(:error, "That decision was incomplete. Nothing changed.")}
  end

  defp load_queue(socket) do
    scope = socket.assigns.current_scope
    start_async(socket, :load_disputes, fn -> Bench.list_pending_disputes(scope) end)
  end

  defp load_failed(socket, reason) do
    socket
    |> assign(:queue_state, :failed)
    |> assign(:error, "The dispute queue could not be loaded: #{inspect(reason)}")
  end

  defp decorate(%{challenge: challenge, incumbent: incumbent} = row) do
    row
    |> Map.put(:id, challenge.id)
    |> Map.put(:title, Presenter.title(challenge.vehicle))
    |> Map.put(:chassis, Presenter.chassis(challenge.vehicle))
    |> Map.put(
      :decision_form,
      to_form(%{"challenge_id" => challenge.id, "reason" => ""}, as: :decision)
    )
    |> Map.put(:incumbent_since, incumbent.decided_at || incumbent.inserted_at)
  end

  defp cast_outcome("keep_incumbent"), do: {:ok, :keep_incumbent}
  defp cast_outcome("transfer_to_claimant"), do: {:ok, :transfer_to_claimant}
  defp cast_outcome(_outcome), do: {:error, "Choose a valid dispute outcome."}

  defp validate_reason(reason) when is_binary(reason) do
    if String.trim(reason) == "",
      do: {:error, "A concise decision reason is required."},
      else: :ok
  end

  defp validate_reason(_reason), do: {:error, "A concise decision reason is required."}

  defp resolve(socket, challenge_id, outcome, reason) do
    case Bench.resolve_dispute(
           socket.assigns.current_scope,
           challenge_id,
           outcome,
           reason
         ) do
      {:ok, resolution} ->
        {:noreply, resolved(socket, resolution)}

      {:error, {:not_pending, state}} ->
        {:noreply,
         stale(socket, challenge_id, "That challenge was already resolved as #{humanize(state)}.")}

      {:error, :not_contested} ->
        {:noreply,
         stale(socket, challenge_id, "That challenge is no longer contested. Nothing changed.")}

      {:error, :not_found} ->
        {:noreply,
         stale(socket, challenge_id, "That challenge no longer exists in the open queue.")}

      {:error, :not_authorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "Operator access is required.")
         |> push_navigate(to: ~p"/")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:last_decision, nil)
         |> assign(:error, "The decision was refused: #{inspect(reason)}")}
    end
  end

  defp resolved(socket, resolution) do
    socket
    |> stream_delete_by_dom_id(:disputes, "dispute-#{resolution.challenge.id}")
    |> refresh_count()
    |> assign(:error, nil)
    |> assign(:last_decision, %{
      challenge_id: resolution.challenge.id,
      outcome: resolution.outcome,
      message: decision_message(resolution.outcome)
    })
  end

  defp stale(socket, challenge_id, message) do
    socket
    |> stream_delete_by_dom_id(:disputes, "dispute-#{challenge_id}")
    |> refresh_count()
    |> assign(:last_decision, nil)
    |> assign(:error, message <> " The stale row was removed.")
  end

  defp refresh_count(socket) do
    case Bench.pending_dispute_count(socket.assigns.current_scope) do
      {:ok, count} -> assign(socket, :queue_count, count)
      {:error, _reason} -> socket
    end
  end

  defp decision_message(:keep_incumbent),
    do: "Resolved. The incumbent keeps stewardship and the claimant was notified."

  defp decision_message(:transfer_to_claimant),
    do: "Transferred. The prior stewardship was revoked and the claimant now maintains the log."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Stewardship disputes
        <:subtitle>
          Two people have demonstrated access to the same car. Decide who maintains the log;
          this does not decide legal ownership or rewrite either person's entries.
        </:subtitle>
        <:actions>
          <.button href={~p"/bench"} variant="secondary">Back to bench</.button>
        </:actions>
      </.header>

      <section
        id="dispute-summary"
        class="club-work-panel mt-6 grid min-w-0 gap-4 p-5 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center"
      >
        <div class="min-w-0">
          <p class="club-kicker">Decision rule</p>
          <p class="mt-1 text-sm leading-relaxed">
            Compare the two possession records and any supporting vehicle evidence. Keep the
            incumbent or transfer stewardship in one transaction. State the reason either way.
          </p>
        </div>
        <div class="sm:text-right">
          <p id="dispute-count" class="club-code text-2xl font-semibold tabular-nums">
            {@queue_count}
          </p>
          <p class="club-muted text-xs uppercase tracking-wider">open disputes</p>
        </div>
      </section>

      <div
        :if={@last_decision}
        id="dispute-success"
        data-challenge-id={@last_decision.challenge_id}
        data-outcome={@last_decision.outcome}
        class="club-notice club-notice-success mt-4"
      >
        {@last_decision.message}
      </div>

      <div :if={@error} id="dispute-error" class="club-notice club-notice-warning mt-4">
        <span>{@error}</span>
        <.button
          :if={@queue_state == :failed}
          id="dispute-retry"
          phx-click="reload"
          variant="secondary"
          class="mt-3"
        >
          Try again
        </.button>
      </div>

      <section
        :if={@queue_state == :loading}
        id="dispute-loading"
        data-state="loading"
        class="club-work-panel club-muted mt-6 p-8 text-center text-sm"
      >
        Loading contested stewardship records…
      </section>

      <section
        :if={@queue_state == :ready and @queue_count == 0}
        id="dispute-empty"
        data-state="empty"
        class="club-work-panel mt-6 p-8 text-center"
      >
        <p class="club-control-title">No stewardship disputes are waiting.</p>
        <p class="club-muted mx-auto mt-2 max-w-lg text-sm leading-relaxed">
          Ordinary possession claims stay in the claiming queue. This queue appears only when
          a submitted challenge faces a different active steward.
        </p>
      </section>

      <div id="dispute-queue" phx-update="stream" class="mt-6 space-y-5">
        <article
          :for={{dom_id, row} <- @streams.disputes}
          id={dom_id}
          data-challenge-id={row.challenge.id}
          data-vehicle-id={row.challenge.vehicle.id}
          class="club-work-panel min-w-0 overflow-hidden"
        >
          <div class="club-rule grid min-w-0 gap-4 border-b p-5 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-start">
            <div class="min-w-0">
              <span
                id={"dispute-state-#{row.challenge.id}"}
                data-state="contested"
                class="club-status club-status-pending"
              >
                decision needed
              </span>
              <h2 class="mt-3 min-w-0 text-xl font-semibold leading-tight">
                <.link
                  navigate={~p"/bench/vehicles/#{row.challenge.vehicle.id}"}
                  class="club-link break-words"
                >
                  {row.title}
                </.link>
              </h2>
              <p class="club-code club-muted mt-1 break-all text-xs">{row.chassis}</p>
            </div>
            <div class="min-w-0 lg:text-right">
              <p class="club-kicker">Why it is here</p>
              <p class="mt-1 max-w-sm text-sm leading-relaxed">
                {row.challenge.handle} submitted possession proof while {incumbent_handle(
                  row.incumbent
                )} already maintained this log.
              </p>
            </div>
          </div>

          <div class="grid min-w-0 gap-5 p-5 lg:grid-cols-2">
            <section
              id={"dispute-incumbent-#{row.challenge.id}"}
              class="club-rule min-w-0 border p-4"
            >
              <div class="flex min-w-0 flex-wrap items-center justify-between gap-2">
                <p class="club-kicker">Current steward</p>
                <span class="club-status club-status-success">active</span>
              </div>
              <p class="mt-3 break-all font-mono text-base font-semibold">
                {incumbent_handle(row.incumbent)}
              </p>
              <p class="club-muted mt-1 break-all text-xs">{row.incumbent.user.email}</p>
              <p class="club-muted mt-3 text-xs tabular-nums">
                Maintaining since {format_timestamp(row.incumbent_since)}
              </p>
              <a
                :if={row.incumbent.proof_artifact_id}
                id={"dispute-incumbent-proof-#{row.challenge.id}"}
                href={~p"/bench/artifacts/#{row.incumbent.proof_artifact_id}"}
                target="_blank"
                class="club-link mt-4 inline-block text-sm"
              >
                Open incumbent proof
              </a>
              <p :if={!row.incumbent.proof_artifact_id} class="club-muted mt-4 text-sm">
                No possession artifact is attached to the original stewardship.
              </p>
            </section>

            <section
              id={"dispute-claimant-#{row.challenge.id}"}
              class="club-rule min-w-0 border p-4"
            >
              <div class="flex min-w-0 flex-wrap items-center justify-between gap-2">
                <p class="club-kicker">Claimant</p>
                <span class="club-status club-status-private">submitted</span>
              </div>
              <p class="mt-3 break-all font-mono text-base font-semibold">
                {row.challenge.handle}
              </p>
              <p class="club-muted mt-1 break-all text-xs">{row.challenge.user.email}</p>
              <p class="club-muted mt-3 text-xs tabular-nums">
                Submitted {format_timestamp(row.challenge.inserted_at)}
              </p>
              <p class="club-code mt-3 text-lg tracking-[0.18em]">
                {SantoApi.Owners.Challenge.spaced(row.challenge.code)}
              </p>
              <a
                id={"dispute-claimant-proof-#{row.challenge.id}"}
                href={~p"/bench/artifacts/#{row.challenge.proof_artifact_id}"}
                target="_blank"
                class="club-link mt-4 inline-block text-sm"
              >
                Open claimant proof
              </a>
            </section>
          </div>

          <div class="px-5 pb-2 text-sm">
            <div class="flex min-w-0 flex-wrap gap-x-4 gap-y-2">
              <a href={~p"/v/#{row.challenge.vehicle.public_id}"} class="club-link">Public car</a>
              <.link
                navigate={~p"/bench/vehicles/#{row.challenge.vehicle.id}"}
                class="club-link"
              >
                Vehicle workbench
              </.link>
            </div>
          </div>

          <.form
            for={row.decision_form}
            id={"dispute-form-#{row.challenge.id}"}
            phx-submit="resolve"
            class="club-rule grid min-w-0 gap-4 border-t p-5 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-end"
          >
            <.input
              field={row.decision_form[:challenge_id]}
              id={"dispute-challenge-id-#{row.challenge.id}"}
              type="hidden"
            />
            <.input
              field={row.decision_form[:reason]}
              id={"dispute-reason-#{row.challenge.id}"}
              type="text"
              label="Decision reason"
              placeholder="Evidence considered and why this person should maintain the log"
              required
            />
            <div
              id={"dispute-controls-#{row.challenge.id}"}
              class="flex min-w-0 flex-col gap-2 sm:flex-row"
            >
              <.button
                id={"keep-incumbent-#{row.challenge.id}"}
                name="decision[outcome]"
                value="keep_incumbent"
                variant="secondary"
                phx-disable-with="Resolving…"
                class="w-full sm:w-auto"
              >
                Keep incumbent
              </.button>
              <.button
                id={"transfer-stewardship-#{row.challenge.id}"}
                name="decision[outcome]"
                value="transfer_to_claimant"
                variant="danger"
                phx-disable-with="Transferring…"
                data-confirm="Transfer stewardship to this claimant? The incumbent will lose maintenance access, but every prior entry will remain attributed."
                class="w-full sm:w-auto"
              >
                Transfer stewardship
              </.button>
            </div>
          </.form>
        </article>
      </div>
    </Layouts.app>
    """
  end

  defp format_timestamp(%DateTime{} = timestamp),
    do: Calendar.strftime(timestamp, "%Y-%m-%d %H:%M UTC")

  defp incumbent_handle(%{user: %{handle: handle}}) when is_binary(handle), do: handle
  defp incumbent_handle(%{user: %{party: %{name: name}}}), do: name
  defp incumbent_handle(_stewardship), do: "unknown maintainer"

  defp humanize(state), do: state |> to_string() |> String.replace("_", " ")
end
