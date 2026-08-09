defmodule SantoApiWeb.VehicleLive.Index do
  @moduledoc """
  The complete public car directory.

  This is the broad lookup surface, not the product's emotional front door.
  Cars remain honest about thin records, while cards name their maintainer and
  latest update so the directory still feels inhabited.
  """

  use SantoApiWeb, :live_view

  alias SantoApi.Owners
  alias SantoApi.Registry
  alias SantoApiWeb.VehicleLive.Presenter

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Cars")
     |> assign(:query, "")
     |> assign(:count, 0)
     |> assign(:empty?, true)
     |> assign(:search_form, to_form(%{"q" => ""}, as: :search))
     |> stream(:cars, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = params |> Map.get("q", "") |> String.trim()
    unpublished = Owners.unpublished_vehicle_ids()

    vehicles =
      query
      |> Registry.search_vehicles()
      |> Enum.reject(&MapSet.member?(unpublished, &1.id))

    counts = Registry.entry_counts()
    stewards = Owners.stewards_for(Enum.map(vehicles, & &1.id))

    rows =
      Enum.map(vehicles, fn vehicle ->
        Presenter.car_card(vehicle,
          entries: Map.get(counts, vehicle.id, 0),
          latest: vehicle.id |> Registry.timeline() |> List.first(),
          steward: stewards[vehicle.id]
        )
      end)

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:count, length(rows))
     |> assign(:empty?, rows == [])
     |> assign(:search_form, to_form(%{"q" => query}, as: :search))
     |> stream(:cars, rows, reset: true)}
  end

  @impl true
  def handle_event("search", %{"search" => %{"q" => query}}, socket) do
    {:noreply, push_patch(socket, to: ~p"/cars?#{[q: String.trim(query)]}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="cars-page" class="club-directory-page">
      <div class="club-wrap">
        <header class="club-directory-header">
          <div>
            <p class="club-kicker club-kicker-paper">The whole club</p>
            <h1 class="club-display club-display-dark">Cars</h1>
            <p class="club-page-subtitle club-ink-muted">
              Find a car by model, marque, VIN, or chassis. Then see the work and miles that made
              it somebody's car.
            </p>
          </div>
          <.button navigate={~p"/start"} variant="primary">Add your car</.button>
        </header>

        <.form
          for={@search_form}
          id="car-search-form"
          phx-change="search"
          phx-submit="search"
          class="club-directory-search"
        >
          <.input
            field={@search_form[:q]}
            type="search"
            label="Search the cars"
            placeholder="911 GT3, Porsche, WP0…"
            phx-debounce="250"
            autocomplete="off"
          />
          <button type="submit" class="club-search-submit" aria-label="Search">
            <.icon name="hero-magnifying-glass" class="size-5" />
          </button>
        </.form>

        <p id="car-search-count" class="club-directory-count">
          <%= cond do %>
            <% @query != "" and @count == 0 -> %>
              No cars match “{@query}”.
            <% @query != "" -> %>
              {result_count(@count)} for “{@query}”
            <% true -> %>
              {result_count(@count)}
          <% end %>
        </p>

        <div id="cars" phx-update="stream" class="club-car-grid">
          <div :if={@empty?} id="cars-empty" class="club-empty-state">
            <%= if @query == "" do %>
              <p>No cars are here yet. Somebody gets to be first.</p>
              <.link navigate={~p"/start"}>Start a garage</.link>
            <% else %>
              <p>Try a shorter model name, marque, VIN, or chassis number.</p>
              <.link patch={~p"/cars"}>Clear the search</.link>
            <% end %>
          </div>
          <.car_card :for={{id, row} <- @streams.cars} id={id} row={row} />
        </div>
      </div>
    </div>
    """
  end

  defp result_count(1), do: "1 car"
  defp result_count(count), do: "#{count} cars"
end
