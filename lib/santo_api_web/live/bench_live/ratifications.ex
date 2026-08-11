defmodule SantoApiWeb.BenchLive.Ratifications do
  @moduledoc """
  The operator half of owner claim ratification (owner_surface §3 and §9.2).

  This is a derived work queue over the claim ledger. It shows only proposed
  owner assertions whose vocabulary scope is `:factory`; resolving a row calls
  the existing Registry transition and removes it from the stream.
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
     |> stream_configure(:ratifications, dom_id: &"ratification-#{&1.id}")
     |> stream(:ratifications, [])
     |> load_queue()}
  end

  @impl true
  def handle_async(:load_ratifications, {:ok, {:ok, rows}}, socket) do
    rows = Enum.map(rows, &decorate/1)

    {:noreply,
     socket
     |> assign(:queue_state, :ready)
     |> assign(:queue_count, length(rows))
     |> assign(:error, nil)
     |> stream(:ratifications, rows, reset: true)}
  end

  def handle_async(:load_ratifications, {:ok, {:error, reason}}, socket) do
    {:noreply, load_failed(socket, reason)}
  end

  def handle_async(:load_ratifications, {:exit, reason}, socket) do
    {:noreply, load_failed(socket, reason)}
  end

  @impl true
  def handle_event("reload", _params, socket) do
    {:noreply, socket |> assign(:queue_state, :loading) |> assign(:error, nil) |> load_queue()}
  end

  def handle_event("ratify", %{"decision" => %{"claim_id" => claim_id}}, socket) do
    resolve(socket, claim_id, :ratify)
  end

  def handle_event("reject", %{"decision" => %{"claim_id" => claim_id}}, socket) do
    resolve(socket, claim_id, :reject)
  end

  def handle_event(event, _params, socket) when event in ["ratify", "reject"] do
    {:noreply, assign(socket, :error, "That decision was missing its claim. Nothing changed.")}
  end

  defp load_queue(socket) do
    scope = socket.assigns.current_scope
    start_async(socket, :load_ratifications, fn -> Bench.list_pending_ratifications(scope) end)
  end

  defp load_failed(socket, reason) do
    socket
    |> assign(:queue_state, :failed)
    |> assign(:error, "The ratification queue could not be loaded: #{inspect(reason)}")
  end

  defp decorate(row) do
    row
    |> Map.put(:title, Presenter.title(row.vehicle))
    |> Map.put(:chassis, Presenter.chassis(row.vehicle))
    |> Map.put(:decision_form, to_form(%{"claim_id" => row.claim.id}, as: :decision))
  end

  defp resolve(socket, claim_id, decision) do
    scope = socket.assigns.current_scope

    result =
      case decision do
        :ratify -> Bench.ratify_claim(scope, claim_id)
        :reject -> Bench.reject_claim(scope, claim_id)
      end

    case result do
      {:ok, claim} ->
        {:noreply, resolved(socket, claim, decision)}

      {:error, {:not_proposed, state}} ->
        {:noreply,
         socket
         |> stream_delete_by_dom_id(:ratifications, "ratification-#{claim_id}")
         |> refresh_count()
         |> assign(:last_decision, nil)
         |> assign(
           :error,
           "That claim was already resolved as #{humanize(state)}. The stale row was removed."
         )}

      {:error, :not_eligible} ->
        {:noreply,
         socket
         |> stream_delete_by_dom_id(:ratifications, "ratification-#{claim_id}")
         |> refresh_count()
         |> assign(:last_decision, nil)
         |> assign(:error, "That claim no longer belongs in this queue. Nothing changed.")}

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

  defp resolved(socket, claim, decision) do
    socket
    |> stream_delete_by_dom_id(:ratifications, "ratification-#{claim.id}")
    |> refresh_count()
    |> assign(:error, nil)
    |> assign(:last_decision, %{
      claim_id: claim.id,
      decision: decision,
      message: decision_message(decision)
    })
  end

  defp refresh_count(socket) do
    case Bench.pending_ratification_count(socket.assigns.current_scope) do
      {:ok, count} -> assign(socket, :queue_count, count)
      {:error, _reason} -> socket
    end
  end

  defp decision_message(:ratify),
    do: "Ratified. The claim is now admitted and the vehicle record has been recomputed."

  defp decision_message(:reject),
    do: "Rejected. The claim remains in ledger history and no longer affects the open queue."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Owner claim ratification
        <:subtitle>
          Core-car facts asserted by an owner and still waiting at the operator gate.
          Events and observations admit through the owner's own path and never appear here.
        </:subtitle>
        <:actions>
          <.button href={~p"/bench"} variant="secondary">Back to bench</.button>
        </:actions>
      </.header>

      <section
        id="ratification-summary"
        class="club-work-panel mt-6 grid min-w-0 gap-4 p-5 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center"
      >
        <div class="min-w-0">
          <p class="club-kicker">Decision rule</p>
          <p class="mt-1 text-sm leading-relaxed">
            Owner + proposed + factory scope. Ratify when this assertion belongs in the
            record; reject when it does not. Either action preserves the original row.
          </p>
        </div>
        <div class="sm:text-right">
          <p id="ratification-count" class="club-code text-2xl font-semibold tabular-nums">
            {@queue_count}
          </p>
          <p class="club-muted text-xs uppercase tracking-wider">open decisions</p>
        </div>
      </section>

      <div
        :if={@last_decision}
        id="ratification-success"
        data-claim-id={@last_decision.claim_id}
        data-decision={@last_decision.decision}
        class="club-notice club-notice-success mt-4"
      >
        {@last_decision.message}
      </div>

      <div :if={@error} id="ratification-error" class="club-notice club-notice-warning mt-4">
        <span>{@error}</span>
        <.button
          :if={@queue_state == :failed}
          id="ratification-retry"
          phx-click="reload"
          variant="secondary"
          class="mt-3"
        >
          Try again
        </.button>
      </div>

      <section
        :if={@queue_state == :loading}
        id="ratification-loading"
        data-state="loading"
        class="club-work-panel club-muted mt-6 p-8 text-center text-sm"
      >
        Loading the open ledger decisions…
      </section>

      <section
        :if={@queue_state == :ready and @queue_count == 0}
        id="ratification-empty"
        data-state="empty"
        class="club-work-panel mt-6 p-8 text-center"
      >
        <p class="club-control-title">The ratification queue is clear.</p>
        <p class="club-muted mx-auto mt-2 max-w-lg text-sm leading-relaxed">
          Owner updates about use and current condition bypass this queue by design. A row
          appears only when an owner proposes a core-car fact.
        </p>
      </section>

      <div id="ratification-queue" phx-update="stream" class="mt-6 space-y-5">
        <article
          :for={{dom_id, row} <- @streams.ratifications}
          id={dom_id}
          data-claim-id={row.claim.id}
          data-vehicle-id={row.vehicle.id}
          data-predicate={row.claim.predicate}
          class="club-work-panel min-w-0 overflow-hidden"
        >
          <div class="club-rule grid min-w-0 gap-4 border-b p-5 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-start">
            <div class="min-w-0">
              <div class="flex min-w-0 flex-wrap items-center gap-2">
                <span
                  id={"ratification-state-#{row.claim.id}"}
                  data-state={row.claim.state}
                  class="club-status club-status-pending"
                >
                  decision needed
                </span>
                <span class="club-code club-muted break-all text-xs">{short_id(row.claim.id)}</span>
              </div>
              <h2 class="mt-3 min-w-0 text-xl font-semibold leading-tight">
                <.link navigate={~p"/bench/vehicles/#{row.vehicle.id}"} class="club-link break-words">
                  {row.title}
                </.link>
              </h2>
              <p class="club-code club-muted mt-1 break-all text-xs">{row.chassis}</p>
            </div>

            <div class="min-w-0 lg:text-right">
              <p class="club-kicker">Why it is here</p>
              <p class="mt-1 max-w-sm text-sm leading-relaxed">
                An owner proposed a factory or delivery-provenance fact. Those claims touch
                the car's core record and cannot self-ratify.
              </p>
            </div>
          </div>

          <div class="grid min-w-0 gap-5 p-5 xl:grid-cols-[minmax(0,1.1fr)_minmax(0,0.9fr)]">
            <section id={"ratification-claim-#{row.claim.id}"} class="min-w-0">
              <p class="club-kicker">Claim</p>
              <p class="club-code mt-2 break-all text-sm font-semibold">{row.claim.predicate}</p>
              <pre class="club-rule mt-3 max-w-full whitespace-pre-wrap break-words border bg-black/10 p-4 text-sm leading-relaxed">{format_value(row.claim.value)}</pre>

              <dl class="mt-4 grid min-w-0 grid-cols-[auto_minmax(0,1fr)] gap-x-4 gap-y-2 text-sm">
                <dt class="club-muted">Asserting party</dt>
                <dd class="min-w-0 break-all font-mono">{row.party.name}</dd>
                <dt class="club-muted">Method</dt>
                <dd id={"ratification-method-#{row.claim.id}"} class="min-w-0 break-words">
                  {method_label(row.claim.method, row.claim.method_meta)}
                </dd>
                <dt class="club-muted">Proposed</dt>
                <dd class="min-w-0 tabular-nums">{format_timestamp(row.claim.inserted_at)}</dd>
                <dt class="club-muted">Effective date</dt>
                <dd class="min-w-0">{format_date(row.claim.scope_date)}</dd>
              </dl>

              <div class="mt-5 flex min-w-0 flex-wrap gap-x-4 gap-y-2 text-sm">
                <a href={~p"/v/#{row.vehicle.public_id}"} class="club-link">Public car</a>
                <.link
                  navigate={~p"/bench/vehicles/#{row.vehicle.id}" <> "#vehicle-claims"}
                  class="club-link"
                >
                  Full claim history
                </.link>
                <a
                  :if={row.source_entry && row.source_entry.public_link?}
                  href={~p"/v/#{row.vehicle.public_id}/updates/#{row.source_entry.entry_ref}"}
                  class="club-link"
                >
                  Source update
                </a>
              </div>
            </section>

            <div class="grid min-w-0 content-start gap-5">
              <section
                id={"ratification-source-#{row.claim.id}"}
                class="club-rule min-w-0 border p-4"
              >
                <p class="club-kicker">Source entry</p>
                <%= if row.source_entry do %>
                  <p class="club-code mt-2 break-all text-xs">{row.source_entry.entry_ref}</p>
                  <div :if={row.source_entry.claims != []} class="mt-3 grid min-w-0 gap-2">
                    <div
                      :for={sibling <- row.source_entry.claims}
                      class="grid min-w-0 gap-1 border-t club-rule pt-2 text-xs"
                    >
                      <div class="flex min-w-0 flex-wrap items-center justify-between gap-2">
                        <span class="club-code break-all">{sibling.predicate}</span>
                        <span class="club-status club-status-private">{sibling.state}</span>
                      </div>
                      <span class="club-muted break-words">{format_value(sibling.value)}</span>
                    </div>
                  </div>
                  <p :if={row.source_entry.claims == []} class="club-muted mt-2 text-sm">
                    This entry contains only the proposed core-car assertion.
                  </p>
                <% else %>
                  <p class="club-muted mt-2 text-sm">No composed entry reference was recorded.</p>
                <% end %>
              </section>

              <section
                id={"ratification-evidence-#{row.claim.id}"}
                class="club-rule min-w-0 border p-4"
              >
                <p class="club-kicker">Evidence and provenance</p>
                <p :if={row.evidence == []} class="club-muted mt-2 text-sm">
                  No artifact attached. This is an attributed owner assertion only.
                </p>
                <div :if={row.evidence != []} class="mt-3 grid min-w-0 gap-3">
                  <div
                    :for={evidence <- row.evidence}
                    id={"ratification-evidence-#{row.claim.id}-#{evidence.artifact.id}"}
                    class="min-w-0 border-t club-rule pt-3 text-sm"
                  >
                    <div class="flex min-w-0 flex-wrap items-start justify-between gap-2">
                      <div class="min-w-0">
                        <p class="break-words font-medium">{artifact_label(evidence.artifact)}</p>
                        <p class="club-muted mt-0.5 break-words text-xs">
                          {role_label(evidence.role)} · supplied by {artifact_party(evidence.artifact)}
                        </p>
                      </div>
                      <a
                        :if={evidence.artifact.storage_ref}
                        href={~p"/bench/artifacts/#{evidence.artifact.id}"}
                        target="_blank"
                        class="club-link shrink-0 text-xs"
                      >
                        Open evidence
                      </a>
                      <a
                        :if={
                          !evidence.artifact.storage_ref && public_url(evidence.artifact.source_url)
                        }
                        href={public_url(evidence.artifact.source_url)}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="club-link shrink-0 text-xs"
                      >
                        Open source
                      </a>
                    </div>
                  </div>
                </div>
              </section>

              <section
                id={"ratification-competing-#{row.claim.id}"}
                class="club-rule min-w-0 border p-4"
              >
                <p class="club-kicker">Existing competing claims</p>
                <p :if={row.competing_claims == []} class="club-muted mt-2 text-sm">
                  No other live source currently asserts this predicate.
                </p>
                <div :if={row.competing_claims != []} class="mt-3 grid min-w-0 gap-3">
                  <div
                    :for={competitor <- row.competing_claims}
                    id={"ratification-competitor-#{row.claim.id}-#{competitor.claim_id}"}
                    class="min-w-0 border-t club-rule pt-3 text-sm"
                  >
                    <div class="flex min-w-0 flex-wrap items-center justify-between gap-2">
                      <span class="break-all font-mono">{competitor.party}</span>
                      <span class="club-status club-status-private">{competitor.state}</span>
                    </div>
                    <p class="club-muted mt-1 whitespace-pre-wrap break-words">
                      {format_value(competitor.value)}
                    </p>
                    <a
                      :if={competitor.artifact && competitor.artifact.storage_ref}
                      href={~p"/bench/artifacts/#{competitor.artifact.id}"}
                      target="_blank"
                      class="club-link mt-2 inline-block text-xs"
                    >
                      Open competing evidence
                    </a>
                  </div>
                </div>
              </section>
            </div>
          </div>

          <div
            id={"ratification-controls-#{row.claim.id}"}
            class="club-rule flex min-w-0 flex-col gap-3 border-t p-5 sm:flex-row sm:items-center sm:justify-between"
          >
            <p class="club-muted max-w-2xl text-xs leading-relaxed">
              Ratification admits this exact claim. Rejection closes the gate on it. Neither
              action edits its value, source, party, evidence, or entry history.
            </p>
            <div class="flex min-w-0 flex-col gap-2 sm:flex-row">
              <.form
                for={row.decision_form}
                id={"ratify-form-#{row.claim.id}"}
                phx-submit="ratify"
                class="min-w-0"
              >
                <.input
                  field={row.decision_form[:claim_id]}
                  id={"ratify-claim-id-#{row.claim.id}"}
                  type="hidden"
                />
                <.button
                  id={"ratify-claim-#{row.claim.id}"}
                  variant="primary"
                  phx-disable-with="Ratifying…"
                  class="w-full sm:w-auto"
                >
                  Ratify claim
                </.button>
              </.form>
              <.form
                for={row.decision_form}
                id={"reject-form-#{row.claim.id}"}
                phx-submit="reject"
                class="min-w-0"
              >
                <.input
                  field={row.decision_form[:claim_id]}
                  id={"reject-claim-id-#{row.claim.id}"}
                  type="hidden"
                />
                <.button
                  id={"reject-claim-#{row.claim.id}"}
                  variant="danger"
                  phx-disable-with="Rejecting…"
                  data-confirm="Reject this owner claim? It will leave the open queue but remain in ledger history."
                  class="w-full sm:w-auto"
                >
                  Reject claim
                </.button>
              </.form>
            </div>
          </div>
        </article>
      </div>
    </Layouts.app>
    """
  end

  defp short_id(id), do: String.slice(id, 0, 8)

  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_value(value), do: inspect(value, pretty: true, limit: 30, printable_limit: 1_000)

  defp format_timestamp(%DateTime{} = timestamp),
    do: Calendar.strftime(timestamp, "%Y-%m-%d %H:%M UTC")

  defp format_date(%Date{} = date), do: Date.to_iso8601(date)
  defp format_date(nil), do: "Timeless factory scope"

  defp method_label(:llm_extract, %{"surface" => surface}),
    do: "LLM extract · #{surface}"

  defp method_label(method, _meta), do: method |> to_string() |> String.replace("_", " ")

  defp artifact_label(artifact) do
    artifact.metadata["filename"] || artifact.source_url ||
      "#{artifact.kind} #{short_id(artifact.id)}"
  end

  defp artifact_party(%{source_party: %{name: name}}), do: name
  defp artifact_party(_artifact), do: "unknown source"

  defp role_label(:claim_basis), do: "claim evidence"
  defp role_label(:entry_attachment), do: "source-entry attachment"

  defp public_url(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host}}
      when scheme in ["http", "https"] and is_binary(host) ->
        url

      _invalid ->
        nil
    end
  end

  defp public_url(_url), do: nil

  defp humanize(state), do: state |> to_string() |> String.replace("_", " ")
end
