defmodule SantoApiWeb.BenchLive.Comments do
  @moduledoc """
  Operator moderation queue for reported update replies.

  The operator may hide a reply or dismiss a report. Car maintainers never see
  these controls, and neither action touches the claim ledger.
  """

  use SantoApiWeb, :live_view

  alias SantoApi.Social
  alias SantoApiWeb.VehicleLive.Presenter

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Reported replies")
     |> assign(:error, nil)
     |> assign_reports()}
  end

  defp assign_reports(socket) do
    reports = Social.list_open_reports(socket.assigns.current_scope)

    socket
    |> assign(:empty?, reports == [])
    |> stream(:reports, reports, reset: true)
  end

  @impl true
  def handle_event("hide_comment", %{"id" => id}, socket) do
    case Social.hide_reported_comment(
           socket.assigns.current_scope,
           id,
           "Hidden from the operator report queue"
         ) do
      {:ok, _comment} ->
        {:noreply, socket |> assign(:error, nil) |> assign_reports()}

      {:error, reason} ->
        {:noreply, socket |> assign(:error, refusal(reason)) |> assign_reports()}
    end
  end

  def handle_event("dismiss_report", %{"id" => id}, socket) do
    case Social.dismiss_report(socket.assigns.current_scope, id, "Dismissed from report queue") do
      {:ok, _report} ->
        {:noreply, socket |> assign(:error, nil) |> assign_reports()}

      {:error, reason} ->
        {:noreply, socket |> assign(:error, refusal(reason)) |> assign_reports()}
    end
  end

  defp refusal(:already_decided), do: "Another operator already decided that report."
  defp refusal(:not_found), do: "That report is no longer in the queue."
  defp refusal(_reason), do: "That moderation action could not be completed."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="reported-replies-page">
        <.header>
          Reported replies
          <:subtitle>
            Conversation outside the ledger. Hide abuse; dismiss disagreement that belongs on the page.
          </:subtitle>
        </.header>

        <p :if={@error} id="reported-replies-error" class="club-notice club-notice-warning mt-5">
          {@error}
        </p>

        <div id="reported-replies" phx-update="stream" class="mt-6 space-y-5">
          <p :if={@empty?} id="reported-replies-empty" class="club-muted">Nothing waiting.</p>

          <article :for={{id, report} <- @streams.reports} id={id} class="club-work-panel p-5">
            <div class="flex flex-wrap items-start justify-between gap-5">
              <div>
                <p class="club-kicker">{String.upcase(to_string(report.reason))}</p>
                <.link
                  navigate={
                    ~p"/v/#{report.comment.vehicle.public_id}/updates/#{report.comment.entry_ref}"
                  }
                  class="club-link mt-2 block text-lg font-semibold"
                >
                  {Presenter.title(report.comment.vehicle)}
                </.link>
                <p class="club-code club-muted mt-1 text-xs">
                  reported by @{report.reporter_handle}
                </p>
              </div>
              <p class="club-code club-muted text-xs">
                {Calendar.strftime(report.inserted_at, "%Y-%m-%d %H:%M UTC")}
              </p>
            </div>

            <blockquote class="mt-5 border-l-4 border-[var(--club-orange)] pl-4 leading-relaxed">
              <p class="club-code club-muted mb-2 text-xs">@{report.comment.author_handle}</p>
              {report.comment.body}
            </blockquote>

            <p :if={report.detail} class="club-muted mt-4 text-sm">
              Reporter note: {report.detail}
            </p>

            <div class="mt-5 flex flex-wrap gap-3">
              <button
                type="button"
                class="club-button club-button-danger"
                phx-click="hide_comment"
                phx-value-id={report.id}
                data-confirm="Hide this reply and resolve every open report against it?"
              >
                Hide reply
              </button>
              <button
                type="button"
                class="club-button club-button-secondary"
                phx-click="dismiss_report"
                phx-value-id={report.id}
              >
                Leave it up
              </button>
            </div>
          </article>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
