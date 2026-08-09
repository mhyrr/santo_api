defmodule SantoApiWeb.HomeLive do
  @moduledoc "The public club front door. Signed-in members belong in their garage."

  use SantoApiWeb, :live_view

  alias SantoApi.Owners
  alias SantoApi.Registry
  alias SantoApiWeb.VehicleLive.Presenter

  @impl true
  def mount(_params, _session, socket) do
    if signed_in?(socket.assigns.current_scope) do
      {:ok, redirect(socket, to: ~p"/garage")}
    else
      counts = Registry.entry_counts()
      unpublished = Owners.unpublished_vehicle_ids()

      vehicles =
        Registry.list_vehicles()
        |> Enum.reject(&MapSet.member?(unpublished, &1.id))
        |> Enum.take(6)

      stewards = Owners.stewards_for(Enum.map(vehicles, & &1.id))

      rows =
        Enum.map(vehicles, fn vehicle ->
          latest = vehicle.id |> Registry.timeline() |> List.first()

          Presenter.car_card(vehicle,
            entries: Map.get(counts, vehicle.id, 0),
            latest: latest,
            steward: stewards[vehicle.id]
          )
        end)

      {:ok,
       socket
       |> assign(:page_title, "Cars worth remembering")
       |> assign(:empty?, rows == [])
       |> stream(:cars, rows)}
    end
  end

  defp signed_in?(%SantoApi.Accounts.Scope{user: %SantoApi.Accounts.User{}}), do: true
  defp signed_in?(_scope), do: false

  @impl true
  def render(assigns) do
    ~H"""
    <div id="club-home">
      <section class="club-home-hero">
        <img src={~p"/images/tire-arcs.svg"} alt="" class="club-home-tracks" />
        <div class="club-wrap club-home-hero-grid">
          <div>
            <p class="club-kicker club-kicker-paper">The cars we keep · the miles we add</p>
            <h1 class="club-display club-display-dark club-home-title">
              Every car has a life beyond the spec sheet.
            </h1>
            <p class="club-home-lede">
              Keep the work, the drives, the odd noises, the good days, and the proof together.
              Vin Santo turns the life of your car into a page worth sharing.
            </p>
            <div class="club-actions">
              <.button navigate={~p"/start"} variant="primary">Start your garage</.button>
              <.button navigate={~p"/cars"} variant="secondary">See the cars</.button>
            </div>
          </div>

          <aside class="club-home-note">
            <p class="club-kicker">Not a concours scorecard</p>
            <p>
              A fuel stop belongs here. So does a track day, an engine-out service, or the note
              that says the rattle only happens cold. The useful record is the one you actually keep.
            </p>
          </aside>
        </div>
      </section>

      <section id="fresh-cars" class="club-home-cars" aria-labelledby="fresh-cars-heading">
        <div class="club-wrap">
          <div class="club-section-heading">
            <p class="club-kicker club-kicker-paper">Fresh in the club</p>
            <h2 id="fresh-cars-heading" class="club-display club-display-dark">People's cars</h2>
            <p class="club-section-intro club-ink-muted">
              Machines with somebody on the other end of the logbook.
            </p>
          </div>

          <div id="home-cars" phx-update="stream" class="club-car-grid">
            <div :if={@empty?} id="home-cars-empty" class="club-empty-state">
              <p>The first garage is still waiting for its first car.</p>
              <.link navigate={~p"/start"}>Bring yours in</.link>
            </div>
            <.car_card :for={{id, row} <- @streams.cars} id={id} row={row} />
          </div>

          <p :if={not @empty?} class="mt-8">
            <.link navigate={~p"/cars"} class="club-text-link">Browse every car →</.link>
          </p>
        </div>
      </section>
    </div>
    """
  end
end
