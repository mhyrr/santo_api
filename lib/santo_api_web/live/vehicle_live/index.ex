defmodule SantoApiWeb.VehicleLive.Index do
  @moduledoc """
  The registry index: every car we hold, grouped by marque.

  Provisional by intent — the real front door is a lookup ("is my car in
  here?"), and this is the directory that makes the registry navigable while
  the surfaces around it get built. It hides nothing: a car with an empty
  record is listed as plainly as a documented one, with its thinness on show.
  """
  use SantoApiWeb, :live_view

  alias SantoApi.Registry
  alias SantoApiWeb.VehicleLive.Presenter

  @impl true
  def mount(_params, _session, socket) do
    counts = Registry.entry_counts()
    vehicles = Registry.list_vehicles()

    groups =
      vehicles
      |> Enum.map(&row(&1, counts))
      |> Enum.group_by(& &1.marque)
      |> Enum.sort_by(fn {marque, _rows} -> marque end)
      |> Enum.map(fn {marque, rows} -> {marque, Enum.sort_by(rows, & &1.sort_key)} end)

    {:ok,
     socket
     |> assign(:page_title, "The registry")
     |> assign(:count, length(vehicles))
     |> assign(:groups, groups)}
  end

  defp row(vehicle, counts) do
    %{
      public_id: vehicle.public_id,
      title: Presenter.title(vehicle),
      marque: Presenter.marque(vehicle) || "Unattributed",
      chassis: Presenter.chassis(vehicle),
      identity_label: Presenter.identity_label(vehicle),
      facts: map_size(vehicle.facts),
      entries: Map.get(counts, vehicle.id, 0),
      sort_key: {Presenter.title(vehicle), vehicle.public_id}
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl px-5 py-16 sm:px-8 sm:py-24">
      <header>
        <p class="vs-eyebrow" style="color: var(--vs-dim)">Vin Santo</p>

        <h1 class="vs-spec mt-4 text-4xl sm:text-5xl">The registry</h1>

        <p class="mt-4 max-w-xl text-base leading-relaxed" style="color: var(--vs-dim)">
          Every car we hold a record for. Each one is a ledger of dated, attributed
          claims — what the factory built, what has happened since, and what backs
          each line.
        </p>
      </header>

      <p :if={@count == 0} class="mt-12 text-base" style="color: var(--vs-dim)">
        No cars in the registry yet. The first one arrives by VIN.
      </p>

      <section :for={{marque, rows} <- @groups} class="mt-14">
        <h2 class="vs-eyebrow pb-4" style="color: var(--vs-dim)">
          {marque}
          <span class="ml-2" style="color: var(--vs-dim)">{length(rows)}</span>
        </h2>

        <ul class="divide-y" style="border-color: var(--vs-hairline)">
          <li :for={row <- rows}>
            <.link
              navigate={~p"/v/#{row.public_id}"}
              class="group flex flex-wrap items-baseline justify-between gap-x-6 gap-y-1 py-4"
            >
              <span class="min-w-0">
                <span class="block text-lg leading-snug group-hover:underline underline-offset-4">
                  {row.title}
                </span>
                <span class="vs-code mt-0.5 block text-xs" style="color: var(--vs-dim)">
                  {row.chassis}
                </span>
              </span>

              <span class="vs-eyebrow shrink-0" style="color: var(--vs-dim)">
                {row.facts} facts · {entries(row.entries)}
              </span>
            </.link>
          </li>
        </ul>
      </section>
    </div>
    """
  end

  defp entries(1), do: "1 entry"
  defp entries(count), do: "#{count} entries"
end
