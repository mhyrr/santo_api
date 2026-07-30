defmodule SantoApiWeb.BenchLive.Index do
  @moduledoc """
  Operator bench: paste an identifier, get a vehicle. No auth — this is
  an internal tool, deliberately.
  """

  use SantoApiWeb, :live_view

  alias SantoApi.Registry

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:input, "")
     |> assign(:error, nil)
     |> stream(:vehicles, Registry.list_vehicles())}
  end

  @impl true
  def handle_event("ingest", %{"input" => input}, socket) do
    case Registry.ingest(input) do
      {:ok, vehicle} ->
        {:noreply, push_navigate(socket, to: ~p"/bench/vehicles/#{vehicle.id}")}

      {:error, %Santo.Invalid{} = invalid} ->
        {:noreply, assign(socket, input: input, error: invalid)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>Vehicle Registry Bench</.header>

      <form id="ingest-form" phx-submit="ingest">
        <.input
          type="text"
          name="input"
          value={@input}
          label="VIN or chassis number"
          placeholder="Paste an identifier"
        />
        <.button variant="primary">Ingest</.button>
      </form>

      <div :if={@error} id="ingest-error" class="alert alert-error mt-4">
        <pre class="whitespace-pre-wrap">{inspect(@error)}</pre>
      </div>

      <.table id="vehicles" rows={@streams.vehicles}>
        <:col :let={{_id, vehicle}} label="identity">
          <.link navigate={~p"/bench/vehicles/#{vehicle.id}"} class="link">
            {vehicle.identity_key}
          </.link>
        </:col>
        <:col :let={{_id, vehicle}} label="kind">{vehicle.identity_kind}</:col>
        <:col :let={{_id, vehicle}} label="ingested">{vehicle.inserted_at}</:col>
      </.table>
    </Layouts.app>
    """
  end
end
