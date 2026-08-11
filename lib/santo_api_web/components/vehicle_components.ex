defmodule SantoApiWeb.VehicleComponents do
  @moduledoc "Shared presentation components for cars and their activity."

  use Phoenix.Component
  use Gettext, backend: SantoApiWeb.Gettext

  use SantoApiWeb, :verified_routes

  attr :row, :map, required: true
  attr :id, :string, default: nil
  attr :actions, :boolean, default: false

  def car_card(assigns) do
    assigns = assign_new(assigns, :resolved_id, fn -> assigns.id || "car-#{assigns.row.id}" end)

    ~H"""
    <article id={@resolved_id} class="club-car-tile">
      <.link navigate={~p"/v/#{@row.public_id}"} class="club-car-tile-main">
        <div class="club-car-plate" aria-hidden="true">
          <span class="club-car-plate-marque">{@row.marque}</span>
          <span class="club-car-plate-code">{@row.public_id}</span>
        </div>
        <div class="club-car-tile-copy">
          <p class="club-kicker club-kicker-paper">{@row.identity}</p>
          <h2 class="club-car-tile-title">{@row.title}</h2>
          <p :if={@row.spec != ""} class="club-car-tile-spec">{@row.spec}</p>
          <p :if={@row.latest} class="club-car-tile-latest">
            <span>Latest update</span>
            {@row.latest}
          </p>
          <div class="club-car-tile-meta">
            <span :if={@row.odometer} class="club-code">
              {format_miles(@row.odometer.miles)} mi
            </span>
            <span class="club-code">{entry_count(@row.entries)}</span>
            <span :if={@row.steward} class="club-car-maintainer">@{@row.steward}</span>
          </div>
        </div>
      </.link>

      <div :if={@actions} class="club-car-tile-actions">
        <.link navigate={~p"/v/#{@row.public_id}/log"}>Log an update</.link>
        <.link navigate={~p"/v/#{@row.public_id}/spec"}>As it sits</.link>
      </div>
    </article>
    """
  end

  defp entry_count(1), do: "1 update"
  defp entry_count(count), do: "#{count} updates"

  defp format_miles(miles) do
    miles
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end
end
