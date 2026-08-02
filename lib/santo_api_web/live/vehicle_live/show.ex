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
         |> assign(:timeline, Registry.timeline(vehicle.id))}

      {:error, :not_found} ->
        raise SantoApiWeb.VehicleNotFound
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <article>
      <.hero vehicle={@vehicle} />
      <.logbook entries={@timeline} />
      <.current_spec vehicle={@vehicle} />
      <.record vehicle={@vehicle} />
      <.colophon vehicle={@vehicle} />
    </article>
    """
  end

  # --- the living car -------------------------------------------------------

  attr :vehicle, :map, required: true

  defp hero(assigns) do
    assigns =
      assigns
      |> assign(:spec, Presenter.spec_line(assigns.vehicle))
      |> assign(:odometer, Presenter.odometer(assigns.vehicle))
      |> assign(:paint_code, Presenter.paint_code(assigns.vehicle))

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

        <div :if={@paint_code}>
          <dt class="vs-eyebrow" style="color: var(--vs-dim)">Paint</dt>
          <dd class="vs-code vs-figure mt-1 text-3xl font-semibold">{@paint_code}</dd>
        </div>
      </dl>
    </header>
    """
  end

  # --- the logbook ----------------------------------------------------------

  attr :entries, :list, required: true

  defp logbook(assigns) do
    ~H"""
    <section class="mx-auto max-w-3xl px-5 pb-16 sm:px-8" aria-labelledby="logbook-heading">
      <h2 id="logbook-heading" class="vs-eyebrow pb-6" style="color: var(--vs-dim)">
        Logbook
      </h2>

      <p :if={@entries == []} class="text-base" style="color: var(--vs-dim)">
        No entries yet. Everything that happens to this car from here — a service, a
        fill-up, a set of wheels — goes in the log and stays there.
      </p>

      <ol :if={@entries != []} class="vs-spine space-y-9 pl-6">
        <li :for={entry <- @entries} class="vs-tick relative" data-owner={owner_entry?(entry)}>
          <p class="vs-code text-xs" style="color: var(--vs-dim)">
            {Presenter.on_date(entry.date) || "Undated"}
          </p>

          <h3 class="mt-1.5 text-lg leading-snug">{Presenter.entry_headline(entry)}</h3>

          <ul class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm">
            <li :for={claim <- entry.claims} style="color: var(--vs-dim)">
              <span class="vs-eyebrow">{Presenter.entry_label(claim.predicate)}</span>
              <span :if={detail(claim)} class="ml-1.5">{detail(claim)}</span>
            </li>
          </ul>

          <p class="mt-2 text-xs" style="color: var(--vs-dim)">
            Recorded by {entry.party}
          </p>
        </li>
      </ol>
    </section>
    """
  end

  # Owner-logged entries get the lit tick; registry-sourced ones stay grey.
  # Attribution is the honesty, so the page shows it before it shows anything else.
  defp owner_entry?(%{method: :human}), do: "true"
  defp owner_entry?(_entry), do: "false"

  defp detail(%{predicate: "observation.mileage", value: miles}) when is_integer(miles),
    do: "#{Presenter.delimit(miles)} mi"

  defp detail(%{predicate: "event.service", value: %{"performer" => performer}})
       when is_binary(performer),
       do: performer

  defp detail(%{predicate: "event.sale", value: %{"price" => price, "currency" => currency}}),
    do: Presenter.money(price, currency)

  defp detail(_claim), do: nil

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
