defmodule SantoApiWeb.VehicleLive.Show do
  @moduledoc """
  The public record for one car (owner_surface §6).

  Render order is the ratified hierarchy: the living car leads — what it is
  now, what has happened to it — and the factory record is the foundation
  underneath, quiet until someone needs it.

  Every number on this page is read from the ledger. Where the ledger is
  silent the page says so; it never fills a gap with a zero or a reassurance.
  """
  use SantoApiWeb, :live_view

  alias SantoApi.{Events, Owners, Social}
  alias SantoApi.Owners.Links
  alias SantoApi.Owners.Photos
  alias SantoApi.Owners.Stories
  alias SantoApi.Owners.VehicleLink
  alias SantoApi.Owners.VehicleStory
  alias SantoApi.Registry
  alias SantoApiWeb.EventComponents
  alias SantoApiWeb.OwnerLive.Composer
  alias SantoApiWeb.VehiclePhotoComponents
  alias SantoApiWeb.VehicleLive.Presenter

  @impl true
  def mount(%{"public_id" => public_id}, _session, socket) do
    case Registry.fetch_by_public_id(public_id) do
      {:ok, vehicle} ->
        scope = socket.assigns.current_scope
        stewarding? = Owners.stewarding?(scope, vehicle)
        published? = Owners.published?(vehicle)
        timeline = Owners.timeline(scope, vehicle)
        story = Stories.get_story(vehicle)
        photos = timeline_photos(timeline)

        # An unconfirmed origination is nobody's business but its steward's —
        # the magic-link click publishes (owner_surface §7b.1 decision 6).
        # Indistinguishable from a missing car on purpose: a 403 would
        # confirm the record exists.
        if not published? and not stewarding?, do: raise(SantoApiWeb.VehicleNotFound)

        {:ok,
         socket
         |> assign(:page_title, Presenter.title(vehicle))
         |> assign(:vehicle, vehicle)
         |> assign(:published?, published?)
         |> assign(:timeline, timeline)
         |> assign(:photos, photos)
         |> assign(:hero_photo, Enum.find(photos, & &1.hero))
         |> assign(:event_updates, event_updates(scope, vehicle))
         |> assign(:record_provenance, Registry.public_fact_provenance(vehicle.id))
         |> assign(:steward, Owners.steward(vehicle))
         |> assign(:stewarding?, stewarding?)
         |> assign(:story, story)
         |> assign(:story_form, story_form(story, scope, vehicle, stewarding?))
         |> assign(:links, Links.list_links(vehicle))
         |> assign(:resolve_error, nil)
         |> assign(:my_handle, my_handle(scope))
         |> assign(:signed_in?, signed_in?(scope))}

      {:error, :not_found} ->
        raise SantoApiWeb.VehicleNotFound
    end
  end

  defp signed_in?(%SantoApi.Accounts.Scope{user: %SantoApi.Accounts.User{}}), do: true
  defp signed_in?(_anonymous), do: false

  # Which entries this caller may correct, matched on the asserting handle
  # rather than on stewardship alone: a previous steward's entries share
  # `party_kind: :owner` and are not this owner's to remove.
  defp my_handle(%SantoApi.Accounts.Scope{user: %SantoApi.Accounts.User{} = user}) do
    case Owners.party(user) do
      %SantoApi.Registry.Party{name: name} -> name
      nil -> nil
    end
  end

  defp my_handle(_anonymous), do: nil

  defp story_form(_story, _scope, _vehicle, false), do: nil

  defp story_form(story, scope, vehicle, true) do
    story = story || %VehicleStory{vehicle_id: vehicle.id, author_user_id: scope.user.id}

    story
    |> Stories.change_story()
    |> to_form(as: :story)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <article>
      <.unpublished_banner :if={not @published?} />
      <.hero
        vehicle={@vehicle}
        steward={@steward}
        story={@story}
        timeline={@timeline}
        stewarding?={@stewarding?}
        photo={@hero_photo}
      />
      <.claim_bar
        :if={not @stewarding? and @vehicle.identity_kind != :asserted}
        vehicle={@vehicle}
        signed_in?={@signed_in?}
      />
      <.car_nav
        story?={not is_nil(@story) or @stewarding?}
        gallery?={@photos != [] or @stewarding?}
        provenance?={@vehicle.identity_kind != :asserted}
      />
      <.owner_story story={@story} story_form={@story_form} stewarding?={@stewarding?} />
      <.gallery photos={@photos} vehicle={@vehicle} stewarding?={@stewarding?} />
      <div class="club-wrap car-page-body">
        <.logbook
          entries={@timeline}
          event_updates={@event_updates}
          my_handle={@my_handle}
          public_id={@vehicle.public_id}
        />
        <.current_spec vehicle={@vehicle} />
      </div>
      <.links_section links={@links} stewarding?={@stewarding?} />
      <.owner_data_controls
        :if={@stewarding?}
        public_id={@vehicle.public_id}
        handle={@my_handle}
      />
      <%= if @vehicle.identity_kind == :asserted do %>
        <.your_word stewarding?={@stewarding?} resolve_error={@resolve_error} />
      <% else %>
        <.record vehicle={@vehicle} provenance={@record_provenance} />
        <.colophon vehicle={@vehicle} />
      <% end %>
    </article>
    """
  end

  # The steward's own view of a page the world cannot see yet. Only they can
  # be here — everyone else got a 404 at mount.
  defp unpublished_banner(assigns) do
    ~H"""
    <div
      id="unpublished-banner"
      class="mx-auto max-w-3xl px-5 pt-6 text-sm sm:px-8"
      style="color: var(--vs-dim)"
    >
      Your page is live — confirm your email to make it public.
    </div>
    """
  end

  # The honest statement of a tier-1 record and the strongest next action in
  # the product, in one line (owner_surface §7b.3). The §6 paper ground does
  # not render at all on an :asserted car — the page simply ends, and the
  # VIN is what unrolls it.
  attr :stewarding?, :boolean, required: true
  attr :resolve_error, :string, default: nil

  defp your_word(assigns) do
    ~H"""
    <section id="your-word" class="mx-auto max-w-3xl px-5 pb-20 sm:px-8">
      <p class="max-w-xl text-sm leading-relaxed" style="color: var(--vs-dim)">
        Add the VIN when you have it. We’ll use it to fill in the factory details.
      </p>

      <form :if={@stewarding?} id="resolve-form" phx-submit="resolve_vin" class="mt-5">
        <div class="flex flex-wrap items-center gap-3">
          <input
            type="text"
            id="resolve_vin"
            name="resolve[vin]"
            placeholder="17-character VIN"
            autocomplete="off"
            spellcheck="false"
            class="vs-field vs-code w-64 text-sm"
          />
          <button type="submit" class="vs-commit">Add the VIN</button>
        </div>
        <p
          :if={@resolve_error}
          id="resolve-error"
          class="mt-2 text-sm"
          style="color: var(--vs-needle)"
        >
          {@resolve_error}
        </p>
      </form>
    </section>
    """
  end

  # --- links ----------------------------------------------------------------

  # Curation, not evidence (owner_surface §7b.1 decision 8): links sit in
  # their own section, never on the timeline spine, and carry no date.
  # Per-platform honesty renders literally — YouTube gets a real embed,
  # everything else a bare link card that does not pretend to a richness we
  # lack the rights to.
  attr :links, :list, required: true
  attr :stewarding?, :boolean, required: true

  defp links_section(assigns) do
    ~H"""
    <section
      :if={@links != [] or @stewarding?}
      id="vehicle-links"
      class="mx-auto max-w-3xl px-5 pb-16 sm:px-8"
      aria-labelledby="links-heading"
    >
      <h2 id="links-heading" class="vs-eyebrow pb-6" style="color: var(--vs-dim)">
        Elsewhere
      </h2>

      <ul :if={@links != []} class="space-y-6">
        <li :for={link <- @links} id={"link-#{link.id}"}>
          <%= case VehicleLink.provider(link.url) do %>
            <% {:youtube, video_id} -> %>
              <div
                class="aspect-video max-w-xl overflow-hidden border"
                style="border-color: var(--vs-hairline)"
              >
                <iframe
                  src={"https://www.youtube.com/embed/#{video_id}"}
                  title={link.label || "YouTube video"}
                  class="h-full w-full"
                  frameborder="0"
                  allowfullscreen
                ></iframe>
              </div>
              <p :if={link.label} class="mt-2 text-sm" style="color: var(--vs-dim)">{link.label}</p>
            <% _other -> %>
              <a
                href={link.url}
                target="_blank"
                rel="noreferrer noopener"
                class="underline underline-offset-4 transition-opacity hover:opacity-65"
              >
                {link.label || link.url}
              </a>
          <% end %>

          <button
            :if={@stewarding?}
            type="button"
            class="mt-1 text-xs underline underline-offset-4"
            style="color: var(--vs-dim)"
            phx-click="remove_link"
            phx-value-link_id={link.id}
          >
            Remove
          </button>
        </li>
      </ul>

      <form :if={@stewarding?} id="link-form" phx-submit="add_link" class="mt-6">
        <div class="flex flex-wrap items-center gap-3">
          <input
            type="url"
            name="link[url]"
            placeholder="https://…"
            class="vs-field w-72 text-sm"
          />
          <input
            type="text"
            name="link[label]"
            placeholder="Label (optional)"
            class="vs-field w-48 text-sm"
          />
          <button type="submit" class="vs-quiet">Add a link</button>
        </div>
      </form>
    </section>
    """
  end

  attr :public_id, :string, required: true
  attr :handle, :string, default: nil

  defp owner_data_controls(assigns) do
    ~H"""
    <section
      id="vehicle-data-controls"
      class="car-data-controls"
      aria-labelledby="vehicle-data-heading"
    >
      <div>
        <p class="club-kicker club-kicker-paper">Your copy</p>
        <h2 id="vehicle-data-heading">Take the record with you</h2>
        <p>
          Download this car’s record as JSON with every original file you added.
          Your private updates are included.
        </p>
        <a
          id="vehicle-record-export"
          href={~p"/v/#{@public_id}/export"}
          class="club-button club-button-primary"
        >
          <.icon name="hero-arrow-down-tray" class="size-4" /> Download full record
        </a>
      </div>

      <div class="car-data-privacy">
        <h3>Journal privacy</h3>
        <p>
          Change every update written by @{@handle || "you"}. Factory history and
          other people’s entries stay as they are.
        </p>
        <div>
          <button
            id="all-entries-private"
            type="button"
            class="vs-quiet"
            phx-click="all_entry_visibility"
            phx-value-visibility="private"
            data-confirm="Hide every update you wrote on this car from the public page?"
          >
            Hide all my updates
          </button>
          <button
            id="all-entries-public"
            type="button"
            class="vs-quiet"
            phx-click="all_entry_visibility"
            phx-value-visibility="public"
            data-confirm="Put every update you wrote on this car, including its photos, on the public page?"
          >
            Publish all my updates
          </button>
        </div>
      </div>
    </section>
    """
  end

  attr :story?, :boolean, required: true
  attr :gallery?, :boolean, required: true
  attr :provenance?, :boolean, required: true

  defp car_nav(assigns) do
    assigns =
      assign(
        assigns,
        :count,
        2 + if(assigns.story?, do: 1, else: 0) + if(assigns.gallery?, do: 1, else: 0) +
          if(assigns.provenance?, do: 1, else: 0)
      )

    ~H"""
    <nav
      id="car-page-nav"
      class={["car-page-nav", "car-page-nav-#{@count}"]}
      aria-label="Car page sections"
    >
      <a :if={@story?} href="#vehicle-owner-story">Story</a>
      <a :if={@gallery?} href="#vehicle-gallery">Gallery</a>
      <a href="#vehicle-logbook">Journal</a>
      <a href="#vehicle-current-state">As it sits</a>
      <a :if={@provenance?} href="#vehicle-record">Provenance</a>
    </nav>
    """
  end

  attr :story, :map, default: nil
  attr :story_form, :map, default: nil
  attr :stewarding?, :boolean, required: true

  defp owner_story(assigns) do
    ~H"""
    <section
      :if={@story || @stewarding?}
      id="vehicle-owner-story"
      class="club-wrap car-owner-story"
      aria-labelledby="owner-story-heading"
    >
      <div :if={@story} class="car-owner-story-copy">
        <p class="club-kicker club-kicker-paper">The story</p>
        <h2 id="owner-story-heading">{@story.tagline}</h2>
        <p :if={@story.body} class="car-story-body">{@story.body}</p>
        <p class="car-story-byline">
          Written by @{story_handle(@story)} · edited {Presenter.on_date(
            DateTime.to_date(@story.updated_at)
          )}
        </p>
      </div>

      <div :if={is_nil(@story)} class="car-owner-story-empty">
        <p class="club-kicker club-kicker-paper">The story</p>
        <h2 id="owner-story-heading">Why this car?</h2>
        <p>Start with why you bought it. You can add the rest later.</p>
      </div>

      <details :if={@stewarding?} id="story-editor" class="car-story-editor">
        <summary>{if @story, do: "Edit story", else: "Add your story"}</summary>
        <.form for={@story_form} id="story-form" phx-submit="save_story">
          <.input
            field={@story_form[:tagline]}
            type="text"
            label="Headline"
            placeholder="Bought for the roads, slowly made my own."
            maxlength="180"
            required
          />
          <.input
            field={@story_form[:body]}
            type="textarea"
            label="The story (optional)"
            placeholder="How you found it, why it matters, and where you want to take it."
            rows="6"
          />
          <button type="submit" class="club-button club-button-primary">Save story</button>
        </.form>
      </details>
    </section>
    """
  end

  defp story_handle(%VehicleStory{author_user: %{handle: handle}}) when is_binary(handle),
    do: handle

  defp story_handle(_story), do: "maintainer"

  # The gallery is mutable presentation over immutable upload artifacts. Order,
  # hero choice, alt text, and removal belong to the owner surface; none of them
  # rewrites the provenance record or the bytes it retains.
  attr :photos, :list, required: true
  attr :vehicle, :map, required: true
  attr :stewarding?, :boolean, required: true

  defp gallery(assigns) do
    items =
      Enum.map(assigns.photos, fn photo ->
        %{
          photo: photo,
          form: to_form(%{"alt_text" => photo.alt_text || ""}, as: :photo)
        }
      end)

    assigns =
      assigns
      |> assign(:items, items)
      |> assign(:first_id, assigns.photos |> List.first() |> photo_id())
      |> assign(:last_id, assigns.photos |> List.last() |> photo_id())

    ~H"""
    <section
      :if={@photos != [] or @stewarding?}
      id="vehicle-gallery"
      class="club-wrap car-gallery"
      aria-labelledby="vehicle-gallery-heading"
    >
      <header class="car-section-heading car-gallery-heading">
        <div>
          <p class="club-kicker club-kicker-paper">Photos</p>
          <h2 id="vehicle-gallery-heading">From the garage</h2>
        </div>
        <.link
          :if={@stewarding?}
          navigate={~p"/v/#{@vehicle.public_id}/log?mode=note"}
          class="club-button club-button-secondary"
        >
          <.icon name="hero-camera" class="size-4" /> Add photos
        </.link>
      </header>

      <p :if={@photos == []} id="vehicle-gallery-empty" class="car-gallery-empty">
        Add the first photo. It will lead the page until you choose another.
      </p>

      <div :if={@photos != []} class="car-gallery-grid">
        <figure
          :for={item <- @items}
          id={"vehicle-photo-#{item.photo.id}"}
          class={["car-gallery-item", item.photo.hero && "car-gallery-item-hero"]}
          data-visibility={item.photo.visibility}
        >
          <VehiclePhotoComponents.image
            vehicle={@vehicle}
            photo={item.photo}
            sizes="(max-width: 640px) 100vw, 33vw"
            loading="lazy"
          />
          <figcaption>
            <span :if={item.photo.hero} class="car-gallery-badge">
              <.icon name="hero-star" class="size-3.5" /> Hero
            </span>
            <span :if={item.photo.visibility == :private} class="car-gallery-badge">
              <.icon name="hero-eye-slash" class="size-3.5" /> Private
            </span>
            <span class="vs-code">{Presenter.on_date(item.photo.entry_date)}</span>
          </figcaption>

          <div :if={@stewarding?} class="car-gallery-editor">
            <.form
              for={item.form}
              id={"photo-alt-form-#{item.photo.id}"}
              phx-submit="photo_alt"
            >
              <input type="hidden" name="photo[id]" value={item.photo.id} />
              <.input
                field={item.form[:alt_text]}
                type="text"
                label="Alt text"
                placeholder={"Describe this #{Presenter.title(@vehicle)}"}
                maxlength="240"
              />
              <button type="submit" class="vs-quiet">Save description</button>
            </.form>

            <div class="car-gallery-controls">
              <button
                :if={not item.photo.hero and item.photo.visibility == :public}
                type="button"
                phx-click="photo_hero"
                phx-value-id={item.photo.id}
              >
                Use as hero
              </button>
              <button
                type="button"
                phx-click="photo_move"
                phx-value-id={item.photo.id}
                phx-value-direction="earlier"
                disabled={item.photo.id == @first_id}
              >
                Earlier
              </button>
              <button
                type="button"
                phx-click="photo_move"
                phx-value-id={item.photo.id}
                phx-value-direction="later"
                disabled={item.photo.id == @last_id}
              >
                Later
              </button>
              <button
                type="button"
                phx-click="photo_remove"
                phx-value-id={item.photo.id}
                data-confirm="Remove this photo from the car page? The original upload stays retained."
              >
                Remove
              </button>
            </div>
          </div>
        </figure>
      </div>
    </section>
    """
  end

  defp photo_id(nil), do: nil
  defp photo_id(photo), do: photo.id

  # The seeded-but-incomplete page is the bait (§4): the one thing an owner who
  # stumbles onto their own car should be able to do is say so. It stays quiet
  # on a car somebody else maintains — the claim page explains that a second
  # claim goes to an operator, and the invitation should not imply otherwise.
  attr :vehicle, :map, required: true
  attr :signed_in?, :boolean, required: true

  defp claim_bar(assigns) do
    ~H"""
    <div class="mx-auto -mt-6 mb-12 flex max-w-3xl flex-wrap items-baseline gap-3 px-5 sm:px-8">
      <.link :if={@signed_in?} navigate={~p"/v/#{@vehicle.public_id}/claim"} class="vs-quiet">
        This is my car
      </.link>

      <p :if={not @signed_in?} class="text-sm" style="color: var(--vs-dim)">
        Is this your car? <.link navigate={~p"/users/log-in"} class="underline">Sign in</.link>
        and prove it with a photo of the VIN plate.
      </p>
    </div>
    """
  end

  # --- the living car -------------------------------------------------------

  attr :vehicle, :map, required: true
  attr :steward, :map, default: nil
  attr :story, :map, default: nil
  attr :timeline, :list, required: true
  attr :stewarding?, :boolean, required: true
  attr :photo, :map, default: nil

  defp hero(assigns) do
    assigns =
      assigns
      |> assign(:spec, Presenter.spec_line(assigns.vehicle))
      |> assign(:odometer, Presenter.odometer(assigns.vehicle))
      |> assign(:latest, List.first(assigns.timeline))

    ~H"""
    <header id="vehicle-hero" class="car-showpiece-hero">
      <img src={~p"/images/tire-arcs.svg"} alt="" class="car-showpiece-tracks" />
      <div class="club-wrap car-showpiece-inner">
        <div class="car-showpiece-copy">
          <p id="vehicle-identity" class="club-kicker vs-rise">
            {Presenter.identity_label(@vehicle)}
            <span class="club-code">{Presenter.chassis(@vehicle)}</span>
          </p>

          <h1 id="vehicle-title" class="vs-rise">{Presenter.title(@vehicle)}</h1>

          <p :if={@story} id="vehicle-storyline" class="car-showpiece-story vs-rise">
            {@story.tagline}
          </p>

          <p
            :if={is_nil(@story) and @spec == []}
            id="vehicle-description-gap"
            class="car-showpiece-story vs-rise"
          >
            Nobody has described this car yet.
          </p>

          <p :if={@spec != []} id="vehicle-spec" class="car-showpiece-spec vs-rise">
            {Enum.join(@spec, " · ")}
          </p>

          <!-- Maintained by, never owned by: possession proof gates the log,
               while title is evidence for the provenance layer to hold. -->
          <p :if={@steward} class="car-showpiece-maintainer vs-rise">
            Maintained by <strong>@{@steward.name}</strong>
          </p>

          <dl class="car-showpiece-metrics vs-rise">
            <div :if={@odometer}>
              <dt>Odometer</dt>
              <dd>
                {Presenter.delimit(@odometer.miles)} <span>mi</span>
              </dd>
              <small :if={@odometer.as_of}>read {Presenter.on_date(@odometer.as_of)}</small>
            </div>
            <div :if={@latest}>
              <dt>Last update</dt>
              <dd>{Presenter.on_date(@latest.date) || "Undated"}</dd>
              <small>{Presenter.entry_headline(@latest)}</small>
            </div>
          </dl>

          <div class="car-showpiece-actions">
            <.link
              :if={@stewarding?}
              navigate={~p"/v/#{@vehicle.public_id}/log"}
              class="club-button club-button-primary"
            >
              <.icon name="hero-pencil-square" class="size-4" /> Log an update
            </.link>
            <.link
              :if={@stewarding?}
              navigate={~p"/v/#{@vehicle.public_id}/events/new"}
              class="club-button club-button-secondary"
            >
              <.icon name="hero-calendar-days" class="size-4" /> Add an event
            </.link>
            <button
              id="vehicle-share"
              type="button"
              phx-hook=".SharePage"
              data-path={~p"/v/#{@vehicle.public_id}"}
              data-title={Presenter.title(@vehicle)}
              class="club-button club-button-secondary"
            >
              <.icon name="hero-arrow-up-on-square" class="size-4" /> Share
            </button>
          </div>
        </div>

        <div
          class={["car-showpiece-field", @photo && "car-showpiece-field-photo"]}
          aria-hidden={if is_nil(@photo), do: "true", else: nil}
        >
          <VehiclePhotoComponents.image
            :if={@photo}
            id="vehicle-hero-photo"
            vehicle={@vehicle}
            photo={@photo}
            sizes="(max-width: 767px) 100vw, 50vw"
          />
          <span :if={is_nil(@photo)} class="car-showpiece-line"></span>
          <span class="car-showpiece-public-id">{@vehicle.public_id}</span>
          <.link
            :if={is_nil(@photo) and @stewarding?}
            navigate={~p"/v/#{@vehicle.public_id}/log?mode=note"}
            class="car-hero-photo-nudge"
          >
            <.icon name="hero-camera" class="size-4" /> Add a hero photo
          </.link>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".SharePage">
        export default {
          mounted() {
            this.el.addEventListener("click", async () => {
              const url = new URL(this.el.dataset.path, window.location.origin).toString()
              try {
                if (navigator.share) {
                  await navigator.share({title: this.el.dataset.title, url})
                } else if (navigator.clipboard) {
                  await navigator.clipboard.writeText(url)
                }
              } catch (_error) {
                // Closing the native share sheet is not a product error.
              }
            })
          }
        }
      </script>
    </header>
    """
  end

  # --- the logbook ----------------------------------------------------------

  attr :entries, :list, required: true
  attr :event_updates, :map, required: true
  attr :public_id, :string, required: true

  attr :my_handle, :string, default: nil

  defp logbook(assigns) do
    assigns = assign(assigns, :entries, Enum.map(assigns.entries, &own(&1, assigns.my_handle)))

    ~H"""
    <section
      id="vehicle-logbook"
      class="car-journal"
      aria-labelledby="logbook-heading"
    >
      <header class="car-section-heading">
        <p class="club-kicker club-kicker-paper">Living build thread</p>
        <h2 id="logbook-heading">Journal</h2>
      </header>

      <p :if={@entries == []} id="logbook-empty" class="text-base" style="color: var(--vs-dim)">
        No updates yet. A service, a fill-up, a set of wheels, or a memorable drive
        can be the first one.
      </p>

      <ol :if={@entries != []} class="vs-spine space-y-9 pl-6">
        <li
          :for={entry <- @entries}
          id={entry_dom_id(entry)}
          class="vs-tick relative"
          data-owner={owner_entry?(entry)}
          data-plan={plan_entry?(entry)}
        >
          <%= case Map.get(@event_updates, entry.entry_ref) do %>
            <% %{participation: participation, reply_count: reply_count} -> %>
              <EventComponents.event_journal_card
                participation={participation}
                reply_count={reply_count}
                heading_level={3}
              />

              <p :if={entry.mine?} class="mt-3 text-xs">
                <span :if={participation.visibility == :private} class="vs-eyebrow mr-3">
                  Not on the public page
                </span>
                <button
                  id={"entry-visibility-#{entry.entry_ref}"}
                  type="button"
                  class="mr-3 underline underline-offset-4 transition-opacity hover:opacity-65"
                  style="color: var(--vs-dim)"
                  phx-click="entry_visibility"
                  phx-value-entry_ref={entry.entry_ref}
                  phx-value-visibility={opposite_visibility(participation.visibility)}
                  data-confirm={visibility_confirmation(participation.visibility)}
                >
                  {visibility_label(participation.visibility)}
                </button>
                <button
                  type="button"
                  class="underline underline-offset-4 transition-opacity hover:opacity-65"
                  style="color: var(--vs-dim)"
                  phx-click="delete_entry"
                  phx-value-entry_ref={entry.entry_ref}
                  data-confirm="Remove this event account from the car and shared event?"
                >
                  Remove
                </button>
              </p>
            <% nil -> %>
              <p class="vs-code text-xs" style="color: var(--vs-dim)">
                {Presenter.on_date(entry.date) || "Undated"}
              </p>

              <h3 class="mt-1.5 text-lg leading-snug">
                <.link
                  :if={entry.entry_ref}
                  navigate={~p"/v/#{@public_id}/updates/#{entry.entry_ref}"}
                  class="underline-offset-4 hover:underline"
                >
                  {entry.parts.headline}
                </.link>
                <span :if={is_nil(entry.entry_ref)}>{entry.parts.headline}</span>
              </h3>

              <div
                :if={Map.get(entry, :photos, []) != []}
                class={["car-journal-media", length(entry.photos) == 1 && "car-journal-media-single"]}
              >
                <VehiclePhotoComponents.image
                  :for={photo <- entry.photos}
                  id={"#{entry_dom_id(entry)}-photo-#{photo.id}"}
                  public_id={@public_id}
                  photo={photo}
                  sizes="(max-width: 640px) 100vw, 620px"
                  fallback_alt="this car"
                  loading="lazy"
                />
              </div>

              <ul
                :if={entry.parts.details != []}
                class="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-sm"
              >
                <li :for={detail <- entry.parts.details} style="color: var(--vs-dim)">
                  <span class="vs-eyebrow">{detail.label}</span>
                  <span class="ml-1.5">{detail.value}</span>
                </li>
              </ul>

              <p class="mt-2 text-xs" style="color: var(--vs-dim)">
                Recorded by {entry.party}
                <!-- Only the steward is ever handed a private entry, so this line
                     marks their own view rather than announcing a hole to a visitor. -->
                <span :if={entry.visibility == :private} class="vs-eyebrow ml-2">
                  Not on the public page
                </span>
              </p>

              <p :if={entry.mine?} class="mt-2 flex flex-wrap gap-x-4 text-xs">
                <button
                  id={"entry-visibility-#{entry.entry_ref}"}
                  type="button"
                  class="underline underline-offset-4 transition-opacity hover:opacity-65"
                  style="color: var(--vs-dim)"
                  phx-click="entry_visibility"
                  phx-value-entry_ref={entry.entry_ref}
                  phx-value-visibility={opposite_visibility(entry.visibility)}
                  data-confirm={visibility_confirmation(entry.visibility)}
                >
                  {visibility_label(entry.visibility)}
                </button>

                <.link
                  :if={entry.correctable?}
                  navigate={~p"/v/#{@public_id}/log/#{entry.entry_ref}"}
                  class="underline underline-offset-4 transition-opacity hover:opacity-65"
                  style="color: var(--vs-dim)"
                >
                  Edit
                </.link>

                <button
                  type="button"
                  class="underline underline-offset-4 transition-opacity hover:opacity-65"
                  style="color: var(--vs-dim)"
                  phx-click="delete_entry"
                  phx-value-entry_ref={entry.entry_ref}
                  data-confirm="Remove this update from the car's history?"
                >
                  Remove
                </button>
              </p>

              <p :if={entry.evidence != []} class="mt-2 flex flex-wrap gap-x-3 gap-y-1 text-xs">
                <a
                  :for={{evidence, index} <- Enum.with_index(entry.evidence)}
                  id={"#{entry_dom_id(entry)}-evidence-#{index}"}
                  href={evidence.url}
                  target="_blank"
                  rel="noreferrer noopener"
                  class="underline underline-offset-4 transition-opacity hover:opacity-65"
                  aria-label={"Source evidence from #{evidence.source}"}
                >
                  Source evidence
                </a>
              </p>
          <% end %>
        </li>
      </ol>
    </section>
    """
  end

  @impl true
  def handle_event("resolve_vin", %{"resolve" => %{"vin" => vin}}, socket) do
    %{current_scope: scope, vehicle: vehicle} = socket.assigns

    case Owners.resolve_asserted(scope, vehicle, vin) do
      {:ok, :resolved, resolved} ->
        {:noreply,
         socket
         |> assign(:vehicle, resolved)
         |> assign(:page_title, Presenter.title(resolved))
         |> assign(:timeline, Owners.timeline(scope, resolved))
         |> assign(:record_provenance, Registry.public_fact_provenance(resolved.id))
         |> assign(:resolve_error, nil)
         |> put_flash(:info, "The factory record is filling in underneath your word.")}

      # The collision (§7b.3 screen 7): the assertion is recorded — the
      # counter-claim now exists on the row that holds the VIN — and the copy
      # says what happened rather than saying no.
      {:ok, :counter_claim, occupied, _challenge} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "We've recorded that you say this is your car. Another record already " <>
             "holds this VIN, so an operator will decide — your log stays here meanwhile."
         )
         |> push_navigate(to: ~p"/v/#{occupied.public_id}/claim")}

      {:error, %Santo.Invalid{}} ->
        {:noreply, assign(socket, :resolve_error, "That VIN is not valid.")}

      {:error, :vin_required} ->
        {:noreply, assign(socket, :resolve_error, "Enter a standard 17-character VIN.")}

      {:error, _reason} ->
        {:noreply, assign(socket, :resolve_error, "That could not be done.")}
    end
  end

  def handle_event("save_story", %{"story" => params}, socket) do
    %{current_scope: scope, vehicle: vehicle} = socket.assigns

    case Stories.save_story(scope, vehicle, params) do
      {:ok, _story} ->
        story = Stories.get_story(vehicle)

        {:noreply,
         socket
         |> assign(:story, story)
         |> assign(:story_form, story_form(story, scope, vehicle, true))
         |> put_flash(:info, "Story updated.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :story_form, to_form(changeset, as: :story))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "That story is not yours to change.")}
    end
  end

  def handle_event("add_link", %{"link" => params}, socket) do
    %{current_scope: scope, vehicle: vehicle} = socket.assigns

    case Links.add_link(scope, vehicle, params) do
      {:ok, _link} ->
        {:noreply, assign(socket, :links, Links.list_links(vehicle))}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "A link needs a full http(s) address.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "That could not be added.")}
    end
  end

  def handle_event("remove_link", %{"link_id" => link_id}, socket) do
    %{current_scope: scope, vehicle: vehicle} = socket.assigns

    case Links.remove_link(scope, vehicle, link_id) do
      {:ok, _link} ->
        {:noreply, assign(socket, :links, Links.list_links(vehicle))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "That link is not yours to remove.")}
    end
  end

  def handle_event("photo_alt", %{"photo" => %{"id" => id, "alt_text" => alt_text}}, socket) do
    %{current_scope: scope, vehicle: vehicle} = socket.assigns

    case Photos.update_alt(scope, vehicle, id, alt_text) do
      {:ok, _photo} ->
        {:noreply, socket |> reload_media() |> put_flash(:info, "Photo description saved.")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "Keep the description under 240 characters.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "That photo is not yours to change.")}
    end
  end

  def handle_event("photo_hero", %{"id" => id}, socket) do
    %{current_scope: scope, vehicle: vehicle} = socket.assigns

    case Photos.set_hero(scope, vehicle, id) do
      {:ok, _photo} ->
        {:noreply, socket |> reload_media() |> put_flash(:info, "Hero photo updated.")}

      {:error, :private_photo} ->
        {:noreply, put_flash(socket, :error, "A private photo cannot lead the public page.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "That photo is not yours to change.")}
    end
  end

  def handle_event("photo_move", %{"id" => id, "direction" => direction}, socket) do
    %{current_scope: scope, vehicle: vehicle} = socket.assigns
    direction = if direction == "earlier", do: :earlier, else: :later

    case Photos.move(scope, vehicle, id, direction) do
      {:ok, _photo} -> {:noreply, reload_media(socket)}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, "That photo could not move.")}
    end
  end

  def handle_event("photo_remove", %{"id" => id}, socket) do
    %{current_scope: scope, vehicle: vehicle} = socket.assigns

    case Photos.remove(scope, vehicle, id) do
      {:ok, _photo} ->
        {:noreply, socket |> reload_media() |> put_flash(:info, "Photo removed from the page.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "That photo is not yours to remove.")}
    end
  end

  def handle_event(
        "entry_visibility",
        %{"entry_ref" => entry_ref, "visibility" => visibility_value},
        socket
      ) do
    %{current_scope: scope, vehicle: vehicle} = socket.assigns

    with {:ok, visibility} <- visibility_from_param(visibility_value),
         {:ok, _result} <- set_entry_visibility(socket, scope, vehicle, entry_ref, visibility) do
      {:noreply,
       socket
       |> assign(:event_updates, event_updates(scope, vehicle))
       |> reload_media()
       |> put_flash(:info, visibility_flash(visibility))}
    else
      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "That update's privacy could not be changed.")}
    end
  end

  def handle_event("all_entry_visibility", %{"visibility" => visibility_value}, socket) do
    %{current_scope: scope, vehicle: vehicle} = socket.assigns

    with {:ok, visibility} <- visibility_from_param(visibility_value),
         {:ok, _counts} <-
           Events.set_all_contribution_visibility(scope, vehicle, visibility) do
      {:noreply,
       socket
       |> assign(:event_updates, event_updates(scope, vehicle))
       |> reload_media()
       |> put_flash(:info, all_visibility_flash(visibility))}
    else
      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Your journal privacy could not be changed.")}
    end
  end

  def handle_event("delete_entry", %{"entry_ref" => entry_ref}, socket) do
    %{current_scope: scope, vehicle: vehicle} = socket.assigns

    result =
      if Map.has_key?(socket.assigns.event_updates, entry_ref) do
        Events.retract_participation(scope, vehicle, entry_ref)
      else
        Owners.retract_entry(scope, vehicle, entry_ref)
      end

    case result do
      {:ok, _count} ->
        {:ok, vehicle} = Registry.fetch_vehicle(vehicle.id)

        {:noreply,
         socket
         |> assign(:vehicle, vehicle)
         |> assign(:timeline, Owners.timeline(scope, vehicle))
         |> assign(:event_updates, event_updates(scope, vehicle))
         |> reload_media()
         |> put_flash(:info, "Entry removed.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "That entry is not yours to remove.")}
    end
  end

  defp event_updates(scope, vehicle) do
    participations = Events.participations_for_vehicle(scope, vehicle)

    counts =
      if map_size(participations) == 0 do
        %{}
      else
        participations
        |> Map.values()
        |> Enum.map(&{vehicle, &1.entry_ref})
        |> Social.conversation_counts()
      end

    Map.new(participations, fn {entry_ref, participation} ->
      reply_count = counts |> Map.fetch!({vehicle.id, entry_ref}) |> Map.fetch!(:reply_count)
      {entry_ref, %{participation: participation, reply_count: reply_count}}
    end)
  end

  defp reload_media(socket) do
    %{current_scope: scope, vehicle: vehicle} = socket.assigns
    timeline = Owners.timeline(scope, vehicle)
    photos = timeline_photos(timeline)

    socket
    |> assign(:photos, photos)
    |> assign(:hero_photo, Enum.find(photos, & &1.hero))
    |> assign(:timeline, timeline)
  end

  defp set_entry_visibility(socket, scope, vehicle, entry_ref, visibility) do
    if Map.has_key?(socket.assigns.event_updates, entry_ref) do
      Events.set_participation_visibility(scope, vehicle, entry_ref, visibility)
    else
      Owners.set_entry_visibility(scope, vehicle, entry_ref, visibility)
    end
  end

  defp visibility_from_param("public"), do: {:ok, :public}
  defp visibility_from_param("private"), do: {:ok, :private}
  defp visibility_from_param(_value), do: {:error, :invalid_visibility}

  defp opposite_visibility(:private), do: "public"
  defp opposite_visibility(_public), do: "private"

  defp visibility_label(:private), do: "Put on the public page"
  defp visibility_label(_public), do: "Hide this update"

  defp visibility_confirmation(:private),
    do: "Put this entire update, including its photos, on the public page?"

  defp visibility_confirmation(_public), do: nil

  defp visibility_flash(:private), do: "Update is now private."
  defp visibility_flash(:public), do: "Update is back on the public page."

  defp all_visibility_flash(:private), do: "All of your updates are now private."
  defp all_visibility_flash(:public), do: "All of your updates are back on the public page."

  defp timeline_photos(timeline) do
    timeline
    |> Enum.flat_map(&Map.get(&1, :photos, []))
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(&{&1.position, &1.inserted_at})
  end

  # What this caller may do to one entry, decided once per render rather than
  # in the markup. Both controls are gated on the asserting handle — stewarding
  # the car is not the question, having written the line is. Edit asks a second
  # one: the composer only offers to correct an entry it can restate exactly,
  # so an outing logged through the agent surface keeps Remove and loses Edit
  # rather than being quietly reshaped into a note.
  defp own(entry, my_handle) do
    mine? = entry.party == my_handle

    entry
    |> Map.put(:parts, Presenter.entry_parts(entry))
    |> Map.put(:mine?, mine?)
    |> Map.put(:correctable?, mine? and Composer.editable?(entry.claims))
  end

  # Owner-logged entries get the lit tick; registry-sourced ones stay grey.
  # Keyed on the asserting party, not the method (§6): a service event typed in
  # at the bench off an invoice is `method: :human` too, and it is the registry
  # speaking, not the owner. Attribution is the honesty, so the page shows it
  # before it shows anything else.
  defp owner_entry?(%{party_kind: :owner}), do: "true"
  defp owner_entry?(_entry), do: "false"

  defp plan_entry?(%{claims: claims}),
    do: to_string(Enum.any?(claims, &(&1.predicate == "event.plan")))

  defp entry_dom_id(%{entry_ref: entry_ref}) when is_binary(entry_ref),
    do: "entry-#{entry_ref}"

  defp entry_dom_id(%{claims: [%{claim_id: claim_id} | _claims]}),
    do: "entry-#{claim_id}"

  # --- current spec ---------------------------------------------------------

  attr :vehicle, :map, required: true

  defp current_spec(assigns) do
    assigns = assign(assigns, :rows, Presenter.spec_rows(assigns.vehicle))

    ~H"""
    <section
      id="vehicle-current-state"
      class="car-current-state"
      aria-labelledby="spec-heading"
    >
      <p class="club-kicker club-kicker-paper">Useful now, quiet by design</p>
      <h2 id="spec-heading">As it sits</h2>

      <p :if={@rows == []} class="car-current-state-empty">
        No durable current-state details have been logged yet.
      </p>
      <dl :if={@rows != []} class="divide-y" style="border-color: var(--vs-hairline)">
        <div
          :for={row <- @rows}
          class={["grid gap-1 py-4 sm:grid-cols-[11rem_1fr] sm:gap-6", row.as_built && "vs-diverged"]}
        >
          <dt class="vs-eyebrow pt-1" style="color: var(--vs-dim)">{row.label}</dt>
          <dd>
            <span>{row.current}</span>
            <span :if={row.as_built} class="vs-was ml-2 text-sm">{row.as_built}</span>
            <p :if={row.as_of} class="vs-code mt-1 text-xs" style="color: var(--vs-dim)">
              since {Presenter.on_date(row.as_of)}
            </p>
          </dd>
        </div>
      </dl>
      <p class="car-current-state-note">
        Event-local notes stay with that day. Only a lasting car update changes this summary.
      </p>
    </section>
    """
  end

  # --- the record -----------------------------------------------------------

  attr :vehicle, :map, required: true
  attr :provenance, :map, required: true

  defp record(assigns) do
    assigns =
      assigns
      |> assign(:rows, Presenter.record_rows(assigns.vehicle, assigns.provenance))
      |> assign(:strength, Presenter.record_strength(assigns.vehicle))

    ~H"""
    <section id="vehicle-record" class="vs-paper" aria-labelledby="record-heading">
      <div class="mx-auto max-w-3xl px-5 py-16 sm:px-8">
        <h2 id="record-heading" class="vs-eyebrow" style="color: var(--vs-ink-dim)">
          History & provenance
        </h2>

        <p class="mt-3 max-w-xl text-sm leading-relaxed" style="color: var(--vs-ink-dim)">
          Factory details and records from the car’s past. Open any row to see the source.
        </p>

        <p
          :if={@rows == []}
          id="record-empty"
          class="mt-8 text-sm"
          style="color: var(--vs-ink-dim)"
        >
          Nothing here yet. A build sheet, window sticker, or factory record would give us a
          place to start.
        </p>

        <div :if={@rows != []} class="mt-8 divide-y" style="border-color: var(--vs-rule)">
          <details
            :for={row <- @rows}
            id={row.dom_id}
            class="group py-1"
            data-status={row.status}
          >
            <summary
              id={"#{row.dom_id}-disclosure"}
              class="grid cursor-pointer list-none gap-2 py-3.5 transition-opacity hover:opacity-70 sm:grid-cols-[11rem_1fr_auto] sm:gap-6"
            >
              <span class="vs-eyebrow pt-1" style="color: var(--vs-ink-dim)">{row.label}</span>
              <span class="flex flex-wrap items-baseline gap-x-3">
                <span>{row.value}</span>
                <span class={["vs-eyebrow", status_class(row.status)]}>
                  {status_word(row.status)}
                </span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="mt-1 size-4 transition-transform duration-200 group-open:rotate-180"
              />
            </summary>

            <div
              id={"#{row.dom_id}-claims"}
              class="mb-5 ml-0 border-l pl-4 sm:ml-[11rem] sm:pl-6"
              style="border-color: var(--vs-rule)"
            >
              <article
                :for={claim <- row.claims}
                id={claim.dom_id}
                class="py-4 first:pt-2"
                data-claim-state={claim.state}
              >
                <div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
                  <p id={"#{claim.dom_id}-value"} class="text-sm font-medium">{claim.value}</p>
                  <span class="vs-code text-[0.7rem] uppercase" style="color: var(--vs-ink-dim)">
                    {claim_state_word(claim.state)}
                  </span>
                </div>

                <dl class="mt-3 grid gap-x-6 gap-y-2 text-xs sm:grid-cols-3">
                  <div>
                    <dt class="vs-eyebrow" style="color: var(--vs-ink-dim)">Source</dt>
                    <dd id={"#{claim.dom_id}-party"} class="mt-1">{claim.party}</dd>
                  </div>
                  <div>
                    <dt class="vs-eyebrow" style="color: var(--vs-ink-dim)">Date</dt>
                    <dd id={"#{claim.dom_id}-applicable"} class="mt-1">
                      {applicable_label(claim.scope_date)}
                    </dd>
                  </div>
                  <div>
                    <dt class="vs-eyebrow" style="color: var(--vs-ink-dim)">Backed by</dt>
                    <dd id={"#{claim.dom_id}-artifact"} class="mt-1">
                      <%= if claim.artifact do %>
                        {Presenter.artifact_kind(claim.artifact.kind)}
                        <span :if={claim.artifact.acquired_at}>
                          · acquired {artifact_date(claim.artifact.acquired_at)}
                        </span>
                      <% else %>
                        No source file attached
                      <% end %>
                    </dd>
                  </div>
                </dl>
              </article>

              <div :if={row.sources != []} class="border-t pt-4" style="border-color: var(--vs-rule)">
                <p class="vs-eyebrow" style="color: var(--vs-ink-dim)">Public sources</p>
                <p class="mt-2 flex flex-wrap gap-x-4 gap-y-2 text-xs">
                  <a
                    :for={source <- row.sources}
                    id={source.dom_id}
                    href={source.url}
                    target="_blank"
                    rel="noreferrer noopener"
                    class="underline underline-offset-4 transition-opacity hover:opacity-65"
                    aria-label={"Public source for #{row.label} from #{source.label}"}
                  >
                    {source.label} source
                  </a>
                </p>
              </div>
            </div>
          </details>
        </div>

        <p
          :if={@strength}
          id="record-strength"
          class="mt-10 text-sm"
          style="color: var(--vs-ink-dim)"
        >
          <span class="vs-figure font-semibold" style="color: var(--vs-ink)">
            {@strength.verified} of {@strength.total}
          </span>
          {if @strength.total == 1, do: "detail", else: "details"} verified.
        </p>
      </div>
    </section>
    """
  end

  # "Unverified" is not a failing grade — it means nobody has produced the paper
  # yet. The words are chosen so absence reads as absence, not as doubt.
  defp status_word("verified"), do: "verified"
  defp status_word("conflicted"), do: "sources disagree"
  defp status_word("unverified"), do: "unconfirmed"

  defp status_class("verified"), do: "vs-verified"
  defp status_class("conflicted"), do: "vs-conflicted"
  defp status_class(_status), do: ""

  defp claim_state_word(:admitted), do: "included"
  defp claim_state_word(:proposed), do: "under review"

  defp applicable_label(nil), do: "As built"
  defp applicable_label(date), do: Presenter.on_date(date)

  defp artifact_date(%DateTime{} = acquired_at) do
    acquired_at |> DateTime.to_date() |> Presenter.on_date()
  end

  # --- colophon -------------------------------------------------------------

  attr :vehicle, :map, required: true

  defp colophon(assigns) do
    ~H"""
    <footer class="vs-paper" style="border-top: 1px solid var(--vs-rule)">
      <div
        class="mx-auto flex max-w-3xl flex-wrap items-baseline justify-between gap-3 px-5 py-8 sm:px-8"
        style="color: var(--vs-ink-dim)"
      >
        <p class="vs-code text-xs">
          {Presenter.identity_label(@vehicle)} {Presenter.chassis(@vehicle)}
        </p>
        <p class="text-xs">
          Every detail includes its source and date. When something changes, the earlier
          version stays in the history.
        </p>
      </div>
    </footer>
    """
  end
end
