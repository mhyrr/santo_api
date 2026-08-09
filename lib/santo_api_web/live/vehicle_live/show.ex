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

  alias SantoApi.Owners
  alias SantoApi.Owners.Links
  alias SantoApi.Owners.VehicleLink
  alias SantoApi.Registry
  alias SantoApiWeb.OwnerLive.Composer
  alias SantoApiWeb.VehicleLive.Presenter

  @impl true
  def mount(%{"public_id" => public_id}, _session, socket) do
    case Registry.fetch_by_public_id(public_id) do
      {:ok, vehicle} ->
        scope = socket.assigns.current_scope
        stewarding? = Owners.stewarding?(scope, vehicle)
        published? = Owners.published?(vehicle)

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
         |> assign(:timeline, Owners.timeline(scope, vehicle))
         |> assign(:record_provenance, Registry.public_fact_provenance(vehicle.id))
         |> assign(:steward, Owners.steward(vehicle))
         |> assign(:stewarding?, stewarding?)
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

  @impl true
  def render(assigns) do
    ~H"""
    <article>
      <.unpublished_banner :if={not @published?} />
      <.hero vehicle={@vehicle} steward={@steward} />
      <.composer_bar :if={@stewarding?} vehicle={@vehicle} />
      <.claim_bar
        :if={not @stewarding? and @vehicle.identity_kind != :asserted}
        vehicle={@vehicle}
        signed_in?={@signed_in?}
      />
      <.logbook entries={@timeline} my_handle={@my_handle} public_id={@vehicle.public_id} />
      <.current_spec vehicle={@vehicle} />
      <.links_section links={@links} stewarding?={@stewarding?} />
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
        Everything on this page is your word. Add the VIN and the factory record
        fills in underneath it.
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

  # The steward's own two doors, and nobody else's.
  attr :vehicle, :map, required: true

  defp composer_bar(assigns) do
    ~H"""
    <div class="mx-auto -mt-6 mb-12 flex max-w-3xl flex-wrap gap-3 px-5 sm:px-8">
      <.link navigate={~p"/v/#{@vehicle.public_id}/log"} class="vs-commit">Log an update</.link>
      <.link navigate={~p"/v/#{@vehicle.public_id}/spec"} class="vs-quiet">As it sits</.link>
    </div>
    """
  end

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

  defp hero(assigns) do
    assigns =
      assigns
      |> assign(:spec, Presenter.spec_line(assigns.vehicle))
      |> assign(:odometer, Presenter.odometer(assigns.vehicle))

    ~H"""
    <header id="vehicle-hero" class="mx-auto max-w-3xl px-5 pt-16 pb-14 sm:px-8 sm:pt-24">
      <p id="vehicle-identity" class="vs-eyebrow vs-rise" style="color: var(--vs-dim)">
        {Presenter.identity_label(@vehicle)}
        <span class="vs-code ml-2" style="color: var(--vs-dial)">{Presenter.chassis(@vehicle)}</span>
      </p>

      <h1 id="vehicle-title" class="vs-spec vs-rise mt-5 text-[2.75rem] sm:text-6xl">
        {Presenter.title(@vehicle)}
      </h1>

      <p
        :if={@spec != []}
        id="vehicle-spec"
        class="vs-rise mt-4 text-lg sm:text-xl"
        style="color: var(--vs-dim)"
      >
        <span :for={{part, index} <- Enum.with_index(@spec)}>
          <span :if={index > 0} aria-hidden="true" class="mx-2">·</span><span style="color: var(--vs-dial)">{part}</span>
        </span>
      </p>

      <p
        :if={@spec == []}
        id="vehicle-description-gap"
        class="vs-rise mt-4 text-lg"
        style="color: var(--vs-dim)"
      >
        Nobody has described this car yet.
      </p>

      <!-- Maintained by, never owned by: possession proof gates the log, and
           title is layer 5's evidence to hold (owner_surface §4). -->
      <p :if={@steward} class="vs-rise mt-5 text-sm" style="color: var(--vs-dim)">
        Maintained by <span class="vs-code ml-1" style="color: var(--vs-dial)">{@steward.name}</span>
      </p>

      <dl class="vs-rise mt-10 flex flex-wrap items-baseline gap-x-10 gap-y-6">
        <div :if={@odometer}>
          <dt class="vs-eyebrow" style="color: var(--vs-dim)">Odometer</dt>
          <dd class="vs-figure mt-1 text-3xl font-semibold">
            {Presenter.delimit(@odometer.miles)}
            <span class="text-base font-normal" style="color: var(--vs-dim)">mi</span>
          </dd>
          <dd :if={@odometer.as_of} class="vs-code mt-1 text-xs" style="color: var(--vs-dim)">
            read {Presenter.on_date(@odometer.as_of)}
          </dd>
        </div>
      </dl>
    </header>
    """
  end

  # --- the logbook ----------------------------------------------------------

  attr :entries, :list, required: true
  attr :public_id, :string, required: true

  attr :my_handle, :string, default: nil

  defp logbook(assigns) do
    assigns = assign(assigns, :entries, Enum.map(assigns.entries, &own(&1, assigns.my_handle)))

    ~H"""
    <section
      id="vehicle-logbook"
      class="mx-auto max-w-3xl px-5 pb-16 sm:px-8"
      aria-labelledby="logbook-heading"
    >
      <h2 id="logbook-heading" class="vs-eyebrow pb-6" style="color: var(--vs-dim)">
        Updates
      </h2>

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
        >
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

  def handle_event("delete_entry", %{"entry_ref" => entry_ref}, socket) do
    %{current_scope: scope, vehicle: vehicle} = socket.assigns

    case Owners.retract_entry(scope, vehicle, entry_ref) do
      {:ok, _count} ->
        {:ok, vehicle} = Registry.fetch_vehicle(vehicle.id)

        {:noreply,
         socket
         |> assign(:vehicle, vehicle)
         |> assign(:timeline, Owners.timeline(scope, vehicle))
         |> put_flash(:info, "Entry removed.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "That entry is not yours to remove.")}
    end
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
      :if={@rows != []}
      class="mx-auto max-w-3xl px-5 pb-20 sm:px-8"
      aria-labelledby="spec-heading"
    >
      <h2 id="spec-heading" class="vs-eyebrow pb-6" style="color: var(--vs-dim)">
        As it sits
      </h2>

      <dl class="divide-y" style="border-color: var(--vs-hairline)">
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
          What this car left the factory as, and what backs each line. Verified lines have
          been admitted to the record. Unconfirmed evidence stays proposed; disagreement
          keeps every side visible.
        </p>

        <p
          :if={@rows == []}
          id="record-empty"
          class="mt-8 text-sm"
          style="color: var(--vs-ink-dim)"
        >
          Nothing on file yet. A build sheet, a window sticker, or a Kardex would start it.
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
                    <dt class="vs-eyebrow" style="color: var(--vs-ink-dim)">Asserted by</dt>
                    <dd id={"#{claim.dom_id}-party"} class="mt-1">{claim.party}</dd>
                  </div>
                  <div>
                    <dt class="vs-eyebrow" style="color: var(--vs-ink-dim)">Applicable</dt>
                    <dd id={"#{claim.dom_id}-applicable"} class="mt-1">
                      {applicable_label(claim.scope_date)}
                    </dd>
                  </div>
                  <div>
                    <dt class="vs-eyebrow" style="color: var(--vs-ink-dim)">Evidence</dt>
                    <dd id={"#{claim.dom_id}-artifact"} class="mt-1">
                      <%= if claim.artifact do %>
                        {Presenter.artifact_kind(claim.artifact.kind)}
                        <span :if={claim.artifact.acquired_at}>
                          · acquired {artifact_date(claim.artifact.acquired_at)}
                        </span>
                      <% else %>
                        No public artifact
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
          facts on this car are admitted without a live disagreement.
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

  defp claim_state_word(:admitted), do: "admitted"
  defp claim_state_word(:proposed), do: "proposed"

  defp applicable_label(nil), do: "Timeless factory claim"
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
          Every line on this page traces to a dated, attributed claim. Nothing here is
          edited — corrections are added, and the original stays visible.
        </p>
      </div>
    </footer>
    """
  end
end
