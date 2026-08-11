defmodule SantoApiWeb.DistributionPresenter do
  @moduledoc "Builds portable update URLs and copy from the public read model."

  use SantoApiWeb, :html

  alias SantoApi.{Distribution, Media}
  alias SantoApiWeb.Endpoint
  alias SantoApiWeb.VehicleLive.Presenter

  def entry(vehicle, entry) do
    parts = Presenter.entry_parts(entry)
    photo = entry |> Map.get(:photos, []) |> List.first()
    entry_path = ~p"/v/#{vehicle.public_id}/updates/#{entry.entry_ref}"
    card_path = ~p"/v/#{vehicle.public_id}/updates/#{entry.entry_ref}/share-card.jpg"
    car_path = ~p"/v/#{vehicle.public_id}"
    badge_path = ~p"/v/#{vehicle.public_id}/badge.svg"

    payload = %{
      title: Presenter.title(vehicle),
      date: Presenter.on_date(entry.date),
      headline: parts.headline,
      details: parts.details,
      url: absolute(entry_path),
      car_url: absolute(car_path),
      photo: photo,
      photo_url: photo_url(vehicle, photo),
      card_path: card_path,
      card_url: absolute(card_path),
      badge_url: absolute(badge_path),
      badge_detail: badge_detail(vehicle),
      download_name: "#{vehicle.public_id}-update.jpg"
    }

    Map.merge(payload, %{
      markdown: Distribution.forum_snippet(payload, :markdown),
      bbcode: Distribution.forum_snippet(payload, :bbcode),
      badge_html: Distribution.badge_embed(payload, :html),
      badge_bbcode: Distribution.badge_embed(payload, :bbcode)
    })
  end

  def vehicle(vehicle) do
    car_path = ~p"/v/#{vehicle.public_id}"
    badge_path = ~p"/v/#{vehicle.public_id}/badge.svg"

    %{
      title: Presenter.title(vehicle),
      car_url: absolute(car_path),
      badge_url: absolute(badge_path),
      badge_detail: badge_detail(vehicle)
    }
  end

  defp photo_url(_vehicle, nil), do: nil

  defp photo_url(vehicle, photo) do
    case photo.artifact |> Media.variants() |> List.last() do
      %{"width" => width} -> absolute(~p"/v/#{vehicle.public_id}/photos/#{photo.id}/#{width}")
      _missing -> nil
    end
  end

  defp badge_detail(vehicle) do
    case Presenter.spec_line(vehicle) do
      [] ->
        case Presenter.odometer(vehicle) do
          %{miles: miles} -> "#{Presenter.delimit(miles)} miles"
          _missing -> "Garage log · #{vehicle.public_id}"
        end

      spec ->
        Enum.join(spec, " · ")
    end
  end

  defp absolute(path), do: Endpoint.url() <> path
end
