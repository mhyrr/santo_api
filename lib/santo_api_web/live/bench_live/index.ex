defmodule SantoApiWeb.BenchLive.Index do
  @moduledoc """
  Operator bench: register an identifier, run the free acquisition plan for a
  VIN, or open an existing registry vehicle.
  """

  use SantoApiWeb, :live_view

  alias SantoApi.AcquisitionRuns
  alias SantoApi.Owners
  alias SantoApi.Registry

  @impl true
  def mount(_params, _session, socket) do
    vehicles = Registry.list_vehicles()
    reported_replies = SantoApi.Social.list_open_reports(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:lookup_form, to_form(%{"vin" => ""}, as: :lookup))
     |> assign(:error, nil)
     |> assign(:waiting_claims, length(Owners.list_pending_challenges()))
     |> assign(:reported_replies, length(reported_replies))
     |> assign(:vehicle_count, length(vehicles))
     |> stream(:vehicles, vehicles)}
  end

  @impl true
  def handle_event("build_record", %{"lookup" => %{"vin" => input}}, socket) do
    scope = socket.assigns.current_scope

    case AcquisitionRuns.start_operator(scope, input) do
      {:ok, disposition, vehicle, _run} ->
        {:noreply,
         socket
         |> put_flash(:info, disposition_message(disposition))
         |> push_navigate(to: ~p"/bench/vehicles/#{vehicle.id}")}

      {:error, %Santo.Invalid{} = invalid} ->
        {:noreply,
         socket
         |> assign(:lookup_form, to_form(%{"vin" => input}, as: :lookup))
         |> assign(:error, invalid_message(invalid))}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "Operator access is required.")
         |> push_navigate(to: ~p"/")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Build failed: #{inspect(reason)}")}
    end
  end

  defp disposition_message(:created), do: "Vehicle added. Free provider lookups are running."
  defp disposition_message(:restarted), do: "Fresh free-provider acquisition started."
  defp disposition_message(:active), do: "The active acquisition is already running."

  defp disposition_message(:registered),
    do: "Chassis registered. VIN-only provider lookups were not run."

  defp invalid_message(%Santo.Invalid{reasons: reasons}) do
    "That identifier could not be resolved: #{inspect(reasons)}"
  end

  defp claims_waiting(0), do: "No claims waiting"
  defp claims_waiting(1), do: "1 claim waiting"
  defp claims_waiting(count), do: "#{count} claims waiting"

  defp reports_waiting(0), do: "No reported replies"
  defp reports_waiting(1), do: "1 reported reply"
  defp reports_waiting(count), do: "#{count} reported replies"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Vehicle Registry Bench
        <:subtitle>
          Build and inspect the best record the configured free providers can support.
        </:subtitle>
      </.header>

      <!-- Somebody has been waiting since they took that photograph, so the
           count is on the way in rather than behind a menu. -->
      <p class="mb-6">
        <.link
          navigate={~p"/bench/claims"}
          class="club-link club-code text-xs uppercase tracking-wider"
        >
          {claims_waiting(@waiting_claims)}
        </.link>
      </p>

      <p class="-mt-4 mb-6">
        <.link
          navigate={~p"/bench/comments"}
          class="club-link club-code text-xs uppercase tracking-wider"
        >
          {reports_waiting(@reported_replies)}
        </.link>
      </p>

      <section
        id="vin-lookup"
        class="club-work-panel p-5"
      >
        <.form
          for={@lookup_form}
          id="vin-lookup-form"
          phx-submit="build_record"
          class="grid gap-4 md:grid-cols-[minmax(0,1fr)_auto] md:items-end"
        >
          <.input
            field={@lookup_form[:vin]}
            type="text"
            label="VIN or chassis number"
            placeholder="WP0CA298X5L001502"
            autocomplete="off"
          />
          <.button id="build-record-button" variant="primary" class="mb-2 px-5">
            Build record
          </.button>
        </.form>

        <p class="club-muted mt-1 text-sm leading-relaxed">
          Standard VINs run Santo and every configured free provider. Pre-standard chassis
          numbers are registered without VIN-only searches.
        </p>

        <div
          :if={@error}
          id="vin-lookup-error"
          class="club-notice club-notice-warning mt-4"
        >
          {@error}
        </div>
      </section>

      <div class="mt-10 flex items-end justify-between gap-4">
        <div>
          <h2 class="club-control-title">Registry vehicles</h2>
          <p class="club-muted mt-1 text-sm">
            Open a VIN to inspect facts, sources, and acquisition work.
          </p>
        </div>
        <span id="vehicle-count" class="club-code club-muted text-sm">
          {@vehicle_count} total
        </span>
      </div>

      <.table id="registry-vehicles" rows={@streams.vehicles}>
        <:col :let={{_id, vehicle}} label="identifier">
          <.link navigate={~p"/bench/vehicles/#{vehicle.id}"} class="club-link">
            {vehicle.identity_key}
          </.link>
        </:col>
        <:col :let={{_id, vehicle}} label="kind">{vehicle.identity_kind}</:col>
        <:col :let={{_id, vehicle}} label="ingested">{vehicle.inserted_at}</:col>
        <:action :let={{_id, vehicle}}>
          <a href={~p"/v/#{vehicle.public_id}"} class="club-link">Public record</a>
        </:action>
      </.table>
    </Layouts.app>
    """
  end
end
