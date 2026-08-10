defmodule SantoApiWeb.EventComponents do
  @moduledoc """
  First-party presentation for generic event participations.

  The car journal, shared event, and update permalink use the same card grammar
  so the event does not turn into a separate mini-product.
  """

  use Phoenix.Component
  use Gettext, backend: SantoApiWeb.Gettext
  use SantoApiWeb, :verified_routes

  import SantoApiWeb.CoreComponents

  alias SantoApi.Media
  alias SantoApi.Events.{EventAttachment, EventOccurrence, EventParticipation}
  alias SantoApiWeb.VehicleLive.Presenter

  attr :participation, EventParticipation, required: true
  attr :reply_count, :integer, default: 0
  attr :heading_level, :integer, default: 3
  attr :show_our_day, :boolean, default: true

  def event_journal_card(assigns) do
    assigns =
      assigns
      |> assign(:event, assigns.participation.event)
      |> assign(:vehicle, assigns.participation.vehicle)
      |> assign(:lead, lead_attachment(assigns.participation.attachments))

    ~H"""
    <article
      id={"event-card-#{@participation.id}"}
      class="theme-event-card production-event-card"
      data-event-participation
    >
      <div class="theme-event-card-head">
        <div>
          <p class="club-kicker">Event update · {event_date(@event)}</p>
          <.dynamic_heading level={@heading_level}>{@event.title}</.dynamic_heading>
          <p>{@event.place_text}</p>
        </div>
        <div :if={@participation.tags != []} class="theme-tags" aria-label="Event tags">
          <span :for={tag <- @participation.tags}>{tag}</span>
        </div>
      </div>

      <.lead_media :if={@lead} attachment={@lead} event={@event} />

      <p class="theme-event-narrative">{@participation.journal}</p>

      <dl
        :if={@participation.details != []}
        class="theme-event-details"
        aria-label="Owner-selected event details"
      >
        <div :for={detail <- @participation.details}>
          <dt>{detail.label}</dt><dd>{detail.value}</dd>
        </div>
      </dl>

      <div
        :if={@participation.attachments != []}
        class="theme-event-attachments"
        aria-label="Labeled attachments"
      >
        <a
          :for={attachment <- @participation.attachments}
          href={attachment_href(@event, attachment)}
          target="_blank"
          rel="noreferrer noopener"
        >
          <.icon name={attachment_icon(attachment)} class="size-4" /> {attachment.label}
        </a>
      </div>

      <footer class="theme-event-card-footer">
        <div class="theme-event-counts" aria-label="Event participation counts">
          <span><strong>{@event.participant_count}</strong> people &amp; cars</span>
          <span><strong>{@event.media_count}</strong> media</span>
          <span><strong>{@reply_count}</strong> replies</span>
        </div>
        <div class="theme-event-card-actions">
          <.link
            :if={@show_our_day}
            navigate={~p"/v/#{@vehicle.public_id}/updates/#{@participation.entry_ref}"}
            class="club-button club-button-primary"
          >
            Our day
          </.link>
          <.link
            navigate={~p"/events/#{@event.public_id}"}
            class="club-button club-button-secondary"
          >
            View the event
          </.link>
        </div>
      </footer>
    </article>
    """
  end

  attr :level, :integer, required: true
  slot :inner_block, required: true

  defp dynamic_heading(assigns) do
    ~H"""
    <h1 :if={@level == 1}>{render_slot(@inner_block)}</h1>
    <h2 :if={@level == 2}>{render_slot(@inner_block)}</h2>
    <h3 :if={@level == 3}>{render_slot(@inner_block)}</h3>
    <h4 :if={@level not in [1, 2, 3]}>{render_slot(@inner_block)}</h4>
    """
  end

  attr :attachment, EventAttachment, required: true
  attr :event, EventOccurrence, required: true

  defp lead_media(assigns) do
    ~H"""
    <figure class="theme-event-lead-media production-event-media">
      <img
        :if={@attachment.kind == :photo and @attachment.artifact}
        src={attachment_image_src(@event, @attachment)}
        srcset={attachment_srcset(@event, @attachment)}
        sizes="(max-width: 640px) 100vw, 720px"
        width={attachment_width(@attachment)}
        height={attachment_height(@attachment)}
        alt={@attachment.label}
      />
      <a
        :if={@attachment.kind == :video}
        href={attachment_href(@event, @attachment)}
        target="_blank"
        rel="noreferrer noopener"
        class="production-event-video"
      >
        <.icon name="hero-play" class="size-9" />
        <span>Open video</span>
      </a>
      <figcaption>
        <.icon name={attachment_icon(@attachment)} class="size-4" /> {@attachment.label}
      </figcaption>
    </figure>
    """
  end

  def attachment_href(%EventOccurrence{}, %EventAttachment{url: url})
      when is_binary(url),
      do: url

  def attachment_href(%EventOccurrence{} = event, %EventAttachment{id: id}) do
    ~p"/events/#{event.public_id}/attachments/#{id}"
  end

  def attachment_image_src(%EventOccurrence{} = event, %EventAttachment{} = attachment) do
    case attachment.artifact && List.last(Media.variants(attachment.artifact)) do
      %{"width" => width} -> attachment_variant_href(event, attachment, width)
      _missing -> attachment_href(event, attachment)
    end
  end

  def attachment_srcset(%EventOccurrence{} = event, %EventAttachment{} = attachment) do
    case attachment.artifact do
      nil ->
        nil

      artifact ->
        artifact
        |> Media.variants()
        |> Enum.map_join(", ", fn %{"width" => width} ->
          "#{attachment_variant_href(event, attachment, width)} #{width}w"
        end)
    end
  end

  def attachment_width(%EventAttachment{artifact: artifact}) when not is_nil(artifact) do
    case List.last(Media.variants(artifact)) do
      %{"width" => width} -> width
      _missing -> nil
    end
  end

  def attachment_width(_attachment), do: nil

  def attachment_height(%EventAttachment{artifact: artifact}) when not is_nil(artifact) do
    case List.last(Media.variants(artifact)) do
      %{"height" => height} -> height
      _missing -> nil
    end
  end

  def attachment_height(_attachment), do: nil

  defp attachment_variant_href(event, attachment, width) do
    ~p"/events/#{event.public_id}/attachments/#{attachment.id}/#{width}"
  end

  def event_date(%EventOccurrence{starts_on: starts_on, ends_on: nil}) do
    Calendar.strftime(starts_on, "%b %-d, %Y")
  end

  def event_date(%EventOccurrence{starts_on: starts_on, ends_on: ends_on}) do
    if starts_on.year == ends_on.year and starts_on.month == ends_on.month do
      "#{Calendar.strftime(starts_on, "%b %-d")}–#{Calendar.strftime(ends_on, "%-d, %Y")}"
    else
      "#{Calendar.strftime(starts_on, "%b %-d, %Y")}–#{Calendar.strftime(ends_on, "%b %-d, %Y")}"
    end
  end

  def event_time(%EventOccurrence{} = event) do
    date = event_date(event)

    time =
      case {event.starts_at, event.ends_at} do
        {%Time{} = starts_at, %Time{} = ends_at} ->
          "#{date} · #{clock(starts_at)}–#{clock(ends_at)}"

        {%Time{} = starts_at, nil} ->
          "#{date} · #{clock(starts_at)}"

        _date_only ->
          date
      end

    if event.timezone, do: "#{time} · #{event.timezone}", else: time
  end

  def participant_title(%EventParticipation{vehicle: vehicle}), do: Presenter.title(vehicle)

  defp clock(time), do: Calendar.strftime(time, "%-I:%M %p")

  defp lead_attachment(attachments) do
    Enum.find(attachments, fn attachment ->
      attachment.kind == :video or
        (attachment.kind == :photo and not is_nil(attachment.artifact))
    end)
  end

  defp attachment_icon(%EventAttachment{kind: :photo}), do: "hero-photo"
  defp attachment_icon(%EventAttachment{kind: :video}), do: "hero-video-camera"
  defp attachment_icon(%EventAttachment{kind: :file}), do: "hero-document-text"
  defp attachment_icon(%EventAttachment{}), do: "hero-link"
end
