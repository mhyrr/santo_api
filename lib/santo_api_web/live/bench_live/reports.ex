defmodule SantoApiWeb.BenchLive.Reports do
  @moduledoc """
  Operator queue for reports against public cars and updates.

  Decisions go through the authorized Bench facade. The LiveView knows how to
  collect a note and render an outcome; it never mutates Registry, Owners, or
  Repo directly.
  """

  use SantoApiWeb, :live_view

  alias SantoApi.Bench
  alias SantoApiWeb.VehicleLive.Presenter

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Reported cars and updates")
     |> assign(:error, nil)
     |> stream_configure(:reports, dom_id: &"content-report-#{&1.report.id}")
     |> assign_reports()}
  end

  defp assign_reports(socket) do
    case Bench.list_content_reports(socket.assigns.current_scope) do
      {:ok, reports} ->
        rows =
          Enum.map(reports, fn report ->
            %{
              report: report,
              hide_form: to_form(%{"note" => ""}, as: :decision),
              dismiss_form: to_form(%{"note" => ""}, as: :decision)
            }
          end)

        socket
        |> assign(:empty?, rows == [])
        |> stream(:reports, rows, reset: true)

      {:error, _reason} ->
        socket
        |> assign(:empty?, true)
        |> assign(:error, "Operator access is required.")
        |> stream(:reports, [], reset: true)
    end
  end

  @impl true
  def handle_event("hide_report", %{"id" => id, "decision" => %{"note" => note}}, socket) do
    decide_report(socket, id, :hide, note)
  end

  def handle_event("dismiss_report", %{"id" => id, "decision" => %{"note" => note}}, socket) do
    decide_report(socket, id, :dismiss, note)
  end

  def handle_event(event, _params, socket) when event in ["hide_report", "dismiss_report"] do
    {:noreply, assign(socket, :error, "Give a concise reason for the outcome.")}
  end

  defp decide_report(socket, id, decision, note) do
    case Bench.decide_content_report(socket.assigns.current_scope, id, decision, note) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> assign(:error, nil)
         |> put_flash(:info, outcome(decision))
         |> assign_reports()}

      {:error, reason} ->
        {:noreply, socket |> assign(:error, refusal(reason)) |> assign_reports()}
    end
  end

  defp outcome(:hide), do: "The reported content is no longer public."
  defp outcome(:dismiss), do: "The report was dismissed; the content remains public."

  defp refusal(:reason_required), do: "Give a concise reason for the decision."
  defp refusal(:reason_too_long), do: "Keep the decision reason under 500 characters."
  defp refusal(:already_decided), do: "Another operator already decided that target."
  defp refusal(:already_hidden), do: "That target is already hidden."
  defp refusal(:not_found), do: "That report is no longer in the queue."
  defp refusal(_reason), do: "That moderation action could not be completed."

  defp target_label(%{target_kind: :vehicle}), do: "Car"
  defp target_label(%{target_kind: :entry}), do: "Update"

  defp report_link(%{target_kind: :vehicle, vehicle: vehicle}),
    do: ~p"/v/#{vehicle.public_id}"

  defp report_link(%{target_kind: :entry, vehicle: vehicle, entry_ref: entry_ref}),
    do: ~p"/v/#{vehicle.public_id}/updates/#{entry_ref}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="content-reports-page">
        <.header>
          Reported cars and updates
          <:subtitle>
            Hide abuse, doxxing, or fraud from public view without rewriting the record.
          </:subtitle>
          <:actions>
            <.button href={~p"/bench"} variant="secondary">Back to bench</.button>
          </:actions>
        </.header>

        <p :if={@error} id="content-reports-error" class="club-notice club-notice-warning mt-5">
          {@error}
        </p>

        <div id="content-reports" phx-update="stream" class="mt-6 space-y-5">
          <p :if={@empty?} id="content-reports-empty" class="club-muted">Nothing waiting.</p>

          <article :for={{id, row} <- @streams.reports} id={id} class="club-work-panel p-5">
            <div class="flex flex-wrap items-start justify-between gap-5">
              <div>
                <p class="club-kicker">
                  {target_label(row.report)} · {String.upcase(to_string(row.report.reason))}
                </p>
                <.link
                  navigate={report_link(row.report)}
                  class="club-link mt-2 block text-lg font-semibold"
                >
                  {Presenter.title(row.report.vehicle)}
                </.link>
                <p class="club-code club-muted mt-1 text-xs">
                  reported by @{row.report.reporter_handle}
                </p>
              </div>
              <time
                class="club-code club-muted text-xs"
                datetime={DateTime.to_iso8601(row.report.inserted_at)}
              >
                {Calendar.strftime(row.report.inserted_at, "%Y-%m-%d %H:%M UTC")}
              </time>
            </div>

            <p :if={row.report.detail} class="club-muted mt-4 text-sm leading-relaxed">
              Reporter note: {row.report.detail}
            </p>

            <div
              id={"content-report-decision-#{row.report.id}"}
              class="mt-5 grid gap-4 lg:grid-cols-2"
            >
              <.form
                for={row.hide_form}
                id={"content-report-hide-#{row.report.id}"}
                phx-submit="hide_report"
                phx-value-id={row.report.id}
                class="rounded-lg border border-red-900/20 p-4"
              >
                <.input
                  field={row.hide_form[:note]}
                  id={"content-report-hide-note-#{row.report.id}"}
                  type="textarea"
                  label="Reason to hide"
                  placeholder="What public-safety issue did you verify?"
                  rows="3"
                />
                <button
                  type="submit"
                  class="club-button club-button-danger"
                  data-confirm="Remove this car or update from public view and resolve every open report against it?"
                >
                  Hide from public view
                </button>
              </.form>

              <.form
                for={row.dismiss_form}
                id={"content-report-dismiss-#{row.report.id}"}
                phx-submit="dismiss_report"
                phx-value-id={row.report.id}
                class="rounded-lg border border-[var(--club-line)] p-4"
              >
                <.input
                  field={row.dismiss_form[:note]}
                  id={"content-report-dismiss-note-#{row.report.id}"}
                  type="textarea"
                  label="Reason to dismiss"
                  placeholder="Why does the content remain public?"
                  rows="3"
                />
                <button
                  type="submit"
                  class="club-button club-button-secondary"
                >
                  Dismiss report
                </button>
              </.form>
            </div>
          </article>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
