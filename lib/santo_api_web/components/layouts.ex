defmodule SantoApiWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use SantoApiWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :chrome, :boolean, default: true, doc: "whether to render the application chrome"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="club-shell">
      <.topbar :if={@chrome} id="app-topbar" current_scope={@current_scope} />

      <main :if={@chrome} id="app-main" class="club-app-main">
        {render_slot(@inner_block)}
      </main>

      <main :if={not @chrome} id="app-main-full">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  The public record and owner layout.

  It keeps the car-first instrument face while sharing the product's compact
  navigation and account controls.
  """
  def public(assigns) do
    ~H"""
    <div class="club-shell">
      <.topbar id="public-topbar" current_scope={@current_scope} />
      <div class="club-public-stage">
        <img src={~p"/images/tire-arcs.svg"} alt="" class="club-public-tracks" />
        <main id="public-main" class="vs-face min-h-screen">
          {@inner_content}
        </main>
      </div>
      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc "Renders the universal Vin Santo navigation bar."
  attr :id, :string, required: true
  attr :current_scope, :map, default: nil
  attr :handle, :string, default: nil
  attr :operator?, :boolean, default: false
  attr :embedded?, :boolean, default: false

  def topbar(assigns) do
    assigns =
      assigns
      |> assign(:resolved_handle, assigns.handle || handle(assigns.current_scope))
      |> assign(:resolved_operator?, assigns.operator? || operator?(assigns.current_scope))

    ~H"""
    <header id={@id} class={["club-topbar", @embedded? && "club-topbar-embedded"]}>
      <div class="club-topbar-inner">
        <.link href={~p"/"} class="club-brand" aria-label="Vin Santo home">
          <img src={~p"/images/vin-santo-mark.svg"} alt="" class="club-brand-mark" />
          <span class="club-wordmark">Vin Santo</span>
        </.link>

        <nav class="club-desktop-nav" aria-label="Primary navigation">
          <.link :if={@resolved_handle} href={~p"/garage"}>Garage</.link>
          <.link href={~p"/cars"}>Cars</.link>
        </nav>

        <form action={~p"/cars"} method="get" class="club-topbar-search" role="search">
          <label for={"#{@id}-car-search"} class="sr-only">Search for a car</label>
          <input
            type="search"
            id={"#{@id}-car-search"}
            name="q"
            placeholder="Search cars"
            autocomplete="off"
          />
          <button type="submit" aria-label="Search cars">
            <.icon name="hero-magnifying-glass" class="size-4" />
          </button>
        </form>

        <div class="club-account-nav">
          <.link href={~p"/start"} class="club-topbar-cta">Add a car</.link>
          <%= if @resolved_handle do %>
            <details class="club-avatar-menu">
              <summary aria-label="Open profile menu">
                <.avatar handle={@resolved_handle} />
              </summary>
              <div id={"#{@id}-profile-menu"} class="club-menu-panel">
                <p class="club-menu-handle">@{@resolved_handle}</p>
                <.link href={~p"/garage"}>Your garage</.link>
                <.link href={~p"/users/settings"}>Settings</.link>
                <.link :if={@resolved_operator?} href={~p"/bench"}>Operator bench</.link>
                <.link href={~p"/users/log-out"} method="delete">Log out</.link>
              </div>
            </details>
          <% else %>
            <.link href={~p"/users/log-in"} class="club-sign-in">Sign in</.link>
          <% end %>
        </div>
      </div>
    </header>
    """
  end

  @doc "Renders a handle-derived profile avatar."
  attr :handle, :string, required: true
  attr :size, :atom, values: [:regular, :large], default: :regular
  attr :tone, :atom, values: [:orange, :petrol], default: :orange

  def avatar(assigns) do
    ~H"""
    <span
      class={[
        "club-avatar",
        @size == :large && "club-avatar-large",
        @tone == :petrol && "club-avatar-petrol"
      ]}
      title={@handle}
    >
      {initials(@handle)}
    </span>
    """
  end

  @doc """
  The document shell for public and owner pages. Warm paper is the application
  default; dark asphalt is reserved for media and deliberate contrast.
  """
  def public_root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" style="background: #ddd3c1; color-scheme: light">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <.live_title default="Vin Santo">{assigns[:page_title]}</.live_title>
        <link phx-track-static rel="stylesheet" href={~p"/assets/css/app.css"} />
        <script defer phx-track-static type="text/javascript" src={~p"/assets/js/app.js"}>
        </script>
      </head>
      <body class="club-shell antialiased">
        {@inner_content}
      </body>
    </html>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  defp handle(nil), do: nil
  defp handle(scope), do: scope.user.handle || scope.user.email

  defp operator?(nil), do: false
  defp operator?(scope), do: scope.user.operator

  defp initials(handle) do
    handle
    |> String.split(~r/[\s._-]+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
    |> case do
      "" -> "VS"
      value -> value
    end
  end
end
