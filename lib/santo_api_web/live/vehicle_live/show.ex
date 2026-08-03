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
  alias SantoApi.Registry
  alias SantoApiWeb.VehicleLive.Presenter

  @impl true
  def mount(%{"public_id" => public_id}, _session, socket) do
    case Registry.fetch_by_public_id(public_id) do
      {:ok, vehicle} ->
        {:ok,
         socket
         |> assign(:page_title, Presenter.title(vehicle))
         |> assign(:vehicle, vehicle)
         |> assign(:timeline, Owners.timeline(socket.assigns.current_scope, vehicle))
         |> assign(:steward, Owners.steward(vehicle))
         |> assign(:stewarding?, Owners.stewarding?(socket.assigns.current_scope, vehicle))
         |> assign(:signed_in?, signed_in?(socket.assigns.current_scope))}

      {:error, :not_found} ->
        raise SantoApiWeb.VehicleNotFound
    end
  end

  defp signed_in?(%SantoApi.Accounts.Scope{user: %SantoApi.Accounts.User{}}), do: true
  defp signed_in?(_anonymous), do: false

  @impl true
  def render(assigns) do
    ~H"""
    <article>
      <.hero vehicle={@vehicle} steward={@steward} />
      <.composer_bar :if={@stewarding?} vehicle={@vehicle} />
      <.claim_bar :if={not @stewarding?} vehicle={@vehicle} signed_in?={@signed_in?} />
      <.logbook entries={@timeline} />
      <.current_spec vehicle={@vehicle} />
      <.record vehicle={@vehicle} />
      <.colophon vehicle={@vehicle} />
    </article>
    """
  end

  # The steward's own two doors, and nobody else's.
  attr :vehicle, :map, required: true

  defp composer_bar(assigns) do
    ~H"""
    <div class="mx-auto -mt-6 mb-12 flex max-w-3xl flex-wrap gap-3 px-5 sm:px-8">
      <.link navigate={~p"/v/#{@vehicle.public_id}/log"} class="vs-commit">Log an entry</.link>
      <.link navigate={~p"/v/#{@vehicle.public_id}/spec"} class="vs-quiet">Edit the spec</.link>
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
    <header class="mx-auto max-w-3xl px-5 pt-16 pb-14 sm:px-8 sm:pt-24">
      <p class="vs-eyebrow vs-rise" style="color: var(--vs-dim)">
        {Presenter.identity_label(@vehicle)}
        <span class="vs-code ml-2" style="color: var(--vs-dial)">{Presenter.chassis(@vehicle)}</span>
      </p>

      <h1 class="vs-spec vs-rise mt-5 text-[2.75rem] sm:text-6xl">
        {Presenter.title(@vehicle)}
      </h1>

      <p :if={@spec != []} class="vs-rise mt-4 text-lg sm:text-xl" style="color: var(--vs-dim)">
        <span :for={{part, index} <- Enum.with_index(@spec)}>
          <span :if={index > 0} aria-hidden="true" class="mx-2">·</span><span style="color: var(--vs-dial)">{part}</span>
        </span>
      </p>

      <p :if={@spec == []} class="vs-rise mt-4 text-lg" style="color: var(--vs-dim)">
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

  defp logbook(assigns) do
    assigns =
      assign(
        assigns,
        :entries,
        Enum.map(assigns.entries, &Map.put(&1, :parts, Presenter.entry_parts(&1)))
      )

    ~H"""
    <section
      id="vehicle-logbook"
      class="mx-auto max-w-3xl px-5 pb-16 sm:px-8"
      aria-labelledby="logbook-heading"
    >
      <h2 id="logbook-heading" class="vs-eyebrow pb-6" style="color: var(--vs-dim)">
        Logbook
      </h2>

      <p :if={@entries == []} class="text-base" style="color: var(--vs-dim)">
        No entries yet. Everything that happens to this car from here — a service, a
        fill-up, a set of wheels — goes in the log and stays there.
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

          <h3 class="mt-1.5 text-lg leading-snug">{entry.parts.headline}</h3>

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

  defp record(assigns) do
    assigns =
      assigns
      |> assign(:rows, Presenter.record_rows(assigns.vehicle))
      |> assign(:strength, Presenter.record_strength(assigns.vehicle))

    ~H"""
    <section class="vs-paper" aria-labelledby="record-heading">
      <div class="mx-auto max-w-3xl px-5 py-16 sm:px-8">
        <h2 id="record-heading" class="vs-eyebrow" style="color: var(--vs-ink-dim)">
          The record
        </h2>

        <p class="mt-3 max-w-xl text-sm leading-relaxed" style="color: var(--vs-ink-dim)">
          What this car left the factory as, and what backs each line. Facts a document
          supports read verified. The rest are on the record as claims, and say so.
        </p>

        <p :if={@rows == []} class="mt-8 text-sm" style="color: var(--vs-ink-dim)">
          Nothing on file yet. A build sheet, a window sticker, or a Kardex would start it.
        </p>

        <dl :if={@rows != []} class="mt-8 divide-y" style="border-color: var(--vs-rule)">
          <div :for={row <- @rows} class="grid gap-1 py-3.5 sm:grid-cols-[11rem_1fr] sm:gap-6">
            <dt class="vs-eyebrow pt-1" style="color: var(--vs-ink-dim)">{row.label}</dt>
            <dd class="flex flex-wrap items-baseline gap-x-3">
              <span>{row.value}</span>
              <span class={["vs-eyebrow", status_class(row.status)]}>{status_word(row.status)}</span>
            </dd>
          </div>
        </dl>

        <p :if={@strength} class="mt-10 text-sm" style="color: var(--vs-ink-dim)">
          <span class="vs-figure font-semibold" style="color: var(--vs-ink)">
            {@strength.verified} of {@strength.total}
          </span>
          facts on this car are backed by a document or a second source.
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
