defmodule SantoApiWeb.EventLive.Show do
  @moduledoc """
  The public page for one generic event occurrence.

  It gathers public member/car accounts and their labeled media without
  turning arbitrary owner details into a scoreboard. Replies stay on each
  car's update permalink.
  """

  use SantoApiWeb, :live_view

  alias SantoApi.Events
  alias SantoApi.Social
  alias SantoApiWeb.EventComponents

  @impl true
  def mount(%{"public_id" => public_id}, _session, socket) do
    case Events.fetch_public_event(public_id) do
      {:ok, event} ->
        counts =
          event.participations
          |> Enum.map(&{&1.vehicle, &1.entry_ref})
          |> Social.conversation_counts()

        accounts =
          Enum.map(event.participations, fn participation ->
            %{
              participation: participation,
              counts: Map.fetch!(counts, {participation.vehicle_id, participation.entry_ref})
            }
          end)

        attachments =
          for participation <- event.participations,
              attachment <- participation.attachments,
              do: %{participation: participation, attachment: attachment}

        media = Enum.filter(attachments, &(&1.attachment.kind in [:photo, :video]))

        source_links =
          attachments
          |> Enum.filter(&(&1.attachment.kind == :link))
          |> Enum.uniq_by(& &1.attachment.url)

        {:ok,
         socket
         |> assign(:page_title, event.title)
         |> assign(:event, event)
         |> assign(:accounts, accounts)
         |> assign(:media, media)
         |> assign(:source_links, source_links)}

      {:error, :not_found} ->
        raise SantoApiWeb.VehicleNotFound
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <article id="shared-event-page" class="event-page">
      <header id="shared-event-hero" class="event-page-hero">
        <img src={~p"/images/tire-arcs.svg"} alt="" class="event-page-tracks" />
        <div class="club-wrap event-page-hero-inner">
          <div>
            <div class="event-source-line">
              <span class="club-status club-status-owner">{source_label(@event.source_status)}</span>
              <span>Added by @{creator_handle(@event)}</span>
            </div>
            <p class="club-kicker">Shared event</p>
            <h1>{@event.title}</h1>
            <p class="event-page-time">{EventComponents.event_time(@event)}</p>
            <p class="event-page-place">{@event.place_text}</p>
            <p :if={@event.description} class="event-page-description">{@event.description}</p>
            <div :if={@event.tags != []} class="theme-tags" aria-label="Event tags">
              <span :for={tag <- @event.tags}>{tag}</span>
            </div>
          </div>

          <div class="event-page-tally" aria-label="Public event totals">
            <strong>{@event.participant_count}</strong>
            <span>public people &amp; cars</span>
            <small>{@event.media_count} labeled media</small>
          </div>
        </div>
      </header>

      <div class="club-wrap event-page-body">
        <section
          id="event-people-cars"
          class="event-page-section"
          aria-labelledby="event-people-heading"
        >
          <header class="theme-section-head">
            <div>
              <p class="club-kicker club-kicker-paper">People &amp; cars</p>
              <h2 id="event-people-heading">The field, in their own words</h2>
            </div>
            <span class="theme-section-count">{@event.participant_count} public accounts</span>
          </header>

          <p :if={@accounts == []} id="event-people-empty" class="event-page-empty">
            No public participant accounts yet.
          </p>

          <div :if={@accounts != []} class="theme-participation-grid">
            <article
              :for={account <- @accounts}
              id={"event-participant-#{account.participation.id}"}
              class="theme-participation-card"
            >
              <header>
                <Layouts.avatar handle={account.participation.user.handle} tone={:petrol} />
                <div>
                  <p>@{account.participation.user.handle}</p>
                  <h3>{EventComponents.participant_title(account.participation)}</h3>
                </div>
              </header>
              <p>{account.participation.journal}</p>
              <dl :if={account.participation.details != []}>
                <div :for={detail <- Enum.take(account.participation.details, 3)}>
                  <dt>{detail.label}</dt><dd>{detail.value}</dd>
                </div>
              </dl>
              <div class="event-participant-foot">
                <span>{account.counts.reply_count} replies</span>
                <.link navigate={
                  ~p"/v/#{account.participation.vehicle.public_id}/updates/#{account.participation.entry_ref}"
                }>
                  Our day →
                </.link>
              </div>
            </article>
          </div>
        </section>

        <section
          id="event-what-happened"
          class="event-page-section event-page-accounts"
          aria-labelledby="event-accounts-heading"
        >
          <header class="theme-section-head">
            <div>
              <p class="club-kicker club-kicker-paper">What happened</p>
              <h2 id="event-accounts-heading">Accounts from the day</h2>
            </div>
            <p class="event-section-note">Replies live with each car update.</p>
          </header>

          <article
            :for={account <- @accounts}
            id={"event-account-#{account.participation.id}"}
            class="event-account"
          >
            <div class="event-account-meta">
              <p>@{account.participation.user.handle}</p>
              <strong>{EventComponents.participant_title(account.participation)}</strong>
            </div>
            <div class="event-account-copy">
              <p>{account.participation.journal}</p>
              <dl :if={account.participation.details != []} class="theme-event-details">
                <div :for={detail <- account.participation.details}>
                  <dt>{detail.label}</dt><dd>{detail.value}</dd>
                </div>
              </dl>
              <div :if={account.participation.attachments != []} class="theme-event-attachments">
                <a
                  :for={attachment <- account.participation.attachments}
                  href={EventComponents.attachment_href(@event, attachment)}
                  target="_blank"
                  rel="noreferrer noopener"
                >
                  {attachment.label}
                </a>
              </div>
              <.link
                navigate={
                  ~p"/v/#{account.participation.vehicle.public_id}/updates/#{account.participation.entry_ref}"
                }
                class="event-account-link"
              >
                Read and reply to this update
              </.link>
            </div>
          </article>
        </section>

        <section
          id="event-media"
          class="event-page-section"
          aria-labelledby="event-media-heading"
        >
          <header class="theme-section-head">
            <div>
              <p class="club-kicker club-kicker-paper">Media</p>
              <h2 id="event-media-heading">Labeled by the people who added it</h2>
            </div>
          </header>

          <p :if={@media == []} id="event-media-empty" class="event-page-empty">
            No public media has been attached yet.
          </p>

          <div :if={@media != []} class="event-media-grid">
            <a
              :for={item <- @media}
              id={"event-media-#{item.attachment.id}"}
              href={EventComponents.attachment_href(@event, item.attachment)}
              target="_blank"
              rel="noreferrer noopener"
              class="event-media-card"
            >
              <img
                :if={item.attachment.kind == :photo and item.attachment.artifact}
                src={EventComponents.attachment_image_src(@event, item.attachment)}
                srcset={EventComponents.attachment_srcset(@event, item.attachment)}
                sizes="(max-width: 640px) 100vw, 33vw"
                width={EventComponents.attachment_width(item.attachment)}
                height={EventComponents.attachment_height(item.attachment)}
                alt={item.attachment.label}
              />
              <div :if={item.attachment.kind != :photo or is_nil(item.attachment.artifact)}>
                <.icon name={media_icon(item.attachment.kind)} class="size-8" />
              </div>
              <span>{item.attachment.label}</span>
              <small>@{item.participation.user.handle}</small>
            </a>
          </div>
        </section>

        <section
          id="event-about"
          class="event-page-section event-about"
          aria-labelledby="event-about-heading"
        >
          <div>
            <p class="club-kicker club-kicker-paper">About &amp; source</p>
            <h2 id="event-about-heading">A shared coordinate, not an official result</h2>
          </div>
          <div>
            <p>
              This event was {source_sentence(@event.source_status)} by <strong>@{creator_handle(@event)}</strong>. Participant details are owner-named text.
              Vin Santo does not calculate standings or compare unlike details from them.
            </p>
            <p>
              Corrections and replies belong to each participant's car update, where the subject
              and author remain clear.
            </p>
            <div :if={@source_links != []} id="event-source-links" class="event-source-links">
              <p class="club-kicker club-kicker-paper">Links supplied by participants</p>
              <a
                :for={item <- @source_links}
                id={"event-source-#{item.attachment.id}"}
                href={EventComponents.attachment_href(@event, item.attachment)}
                target="_blank"
                rel="noreferrer noopener"
              >
                <span>{item.attachment.label}</span>
                <small>@{item.participation.user.handle}</small>
              </a>
            </div>
          </div>
        </section>
      </div>
    </article>
    """
  end

  defp creator_handle(%{creator_user: %{handle: handle}}) when is_binary(handle), do: handle
  defp creator_handle(_event), do: "member"

  defp source_label(:organizer), do: "Organizer supplied"
  defp source_label(:imported), do: "Imported source"
  defp source_label(_community), do: "Community created"

  defp source_sentence(:organizer), do: "supplied by an organizer"
  defp source_sentence(:imported), do: "imported from a cited source"
  defp source_sentence(_community), do: "created by a community member"

  defp media_icon(:video), do: "hero-video-camera"
  defp media_icon(:file), do: "hero-document-text"
  defp media_icon(:photo), do: "hero-photo"
  defp media_icon(_link), do: "hero-link"
end
