defmodule SantoApiWeb.VehiclePhotoComponents do
  @moduledoc "Responsive first-party car-photo presentation shared across owner surfaces."

  use Phoenix.Component
  use SantoApiWeb, :verified_routes

  alias SantoApi.Owners.Photos
  alias SantoApiWeb.VehicleLive.Presenter

  attr :photo, :map, required: true
  attr :vehicle, :map, default: nil
  attr :public_id, :string, default: nil
  attr :id, :string, default: nil
  attr :sizes, :string, default: "100vw"
  attr :loading, :string, default: nil
  attr :class, :any, default: nil
  attr :fallback_alt, :string, default: "this car"

  def image(assigns) do
    public_id = assigns.public_id || assigns.vehicle.public_id

    fallback =
      if assigns.vehicle, do: Presenter.title(assigns.vehicle), else: assigns.fallback_alt

    assigns =
      assigns
      |> assign(:resolved_public_id, public_id)
      |> assign(:alt, Photos.alt(assigns.photo, fallback))

    ~H"""
    <img
      id={@id}
      class={@class}
      src={src(@resolved_public_id, @photo)}
      srcset={srcset(@resolved_public_id, @photo)}
      sizes={@sizes}
      width={width(@photo)}
      height={height(@photo)}
      alt={@alt}
      loading={@loading}
    />
    """
  end

  def src(public_id, photo) do
    case List.last(Photos.variants(photo)) do
      %{"width" => variant_width} ->
        ~p"/v/#{public_id}/photos/#{photo.id}/#{variant_width}"

      _missing ->
        nil
    end
  end

  def srcset(public_id, photo) do
    photo
    |> Photos.variants()
    |> Enum.map_join(", ", fn %{"width" => variant_width} ->
      "#{~p"/v/#{public_id}/photos/#{photo.id}/#{variant_width}"} #{variant_width}w"
    end)
  end

  def width(photo) do
    case List.last(Photos.variants(photo)) do
      %{"width" => variant_width} -> variant_width
      _missing -> nil
    end
  end

  def height(photo) do
    case List.last(Photos.variants(photo)) do
      %{"height" => variant_height} -> variant_height
      _missing -> nil
    end
  end
end
