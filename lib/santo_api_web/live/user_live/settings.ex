defmodule SantoApiWeb.UserLive.Settings do
  @moduledoc """
  Account settings. Email only — v1 ships no passwords (owner_surface.md §5,
  see `SantoApiWeb.UserLive.Login`).
  """
  use SantoApiWeb, :live_view

  on_mount {SantoApiWeb.UserAuth, :require_sudo_mode}

  alias SantoApi.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="settings-page" class="mx-auto max-w-3xl">
        <.header>
          Account settings
          <:subtitle>Manage your account email address and assistant access.</:subtitle>
        </.header>

        <.form
          for={@email_form}
          id="email_form"
          phx-submit="update_email"
          phx-change="validate_email"
          class="mt-8 max-w-lg"
        >
          <.input
            field={@email_form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
          />
          <.button variant="primary" phx-disable-with="Changing...">Change Email</.button>
        </.form>

        <div class="mt-16 border-t pt-10 club-rule">
          <h2 class="club-control-title">Assistant access</h2>
          <p class="club-muted mt-3 max-w-2xl text-sm leading-relaxed">
            A token lets an assistant you already use — Claude, ChatGPT — read and write
            the logbooks of cars you maintain, on your behalf. Entries it writes are
            attributed to you. Changing your email or password revokes every token.
          </p>
        </div>

        <div :if={@minted} class="club-notice club-notice-success mt-6">
          <p class="text-sm font-medium">
            Copy this now — it is not shown again.
          </p>
          <input
            id="minted-token"
            type="text"
            readonly
            value={@minted}
            class="club-input mt-2 font-mono text-xs"
          />
        </div>

        <.form
          for={@token_form}
          id="mcp_token_form"
          phx-submit="mint_token"
          class="mt-6 flex flex-col gap-2 sm:flex-row sm:items-end"
        >
          <div class="grow">
            <.input field={@token_form[:name]} type="text" label="Name this token" />
          </div>
          <.button variant="secondary" phx-disable-with="Minting...">Mint token</.button>
        </.form>

        <div :if={@tokens != []} class="club-table-wrap mt-6">
          <table class="club-table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Created</th>
                <th>Last used</th>
                <th><span class="sr-only">Actions</span></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={token <- @tokens}>
                <td>{token.name}</td>
                <td class="club-code">{Calendar.strftime(token.inserted_at, "%Y-%m-%d")}</td>
                <td class="club-code">
                  {if token.last_used_at,
                    do: Calendar.strftime(token.last_used_at, "%Y-%m-%d %H:%M UTC"),
                    else: "Never used"}
                </td>
                <td class="text-right">
                  <button
                    type="button"
                    class="club-link club-code text-xs uppercase"
                    phx-click="revoke_token"
                    phx-value-id={token.id}
                    data-confirm="Revoke this token? Any assistant using it stops working."
                  >
                    Revoke
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:minted, nil)
      |> load_tokens()

    {:ok, socket}
  end

  # `minted` is assigned only by the event that mints, so it survives exactly
  # one render and no remount can bring it back — the shown-once rule is the
  # assign's lifetime rather than a flag we have to remember to clear.
  defp load_tokens(socket) do
    socket
    |> assign(:tokens, Accounts.list_mcp_tokens(socket.assigns.current_scope.user))
    |> assign(:token_form, to_form(%{"name" => ""}, as: :token))
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("mint_token", %{"token" => %{"name" => name}}, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.mint_mcp_token(user, name) do
      {:ok, plaintext, _record} ->
        {:noreply, socket |> assign(:minted, plaintext) |> load_tokens()}

      {:error, :name_required} ->
        form = to_form(%{"name" => name}, as: :token, errors: [name: {"Name this token", []}])
        {:noreply, assign(socket, :token_form, form)}
    end
  end

  def handle_event("revoke_token", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    {:ok, :revoked} = Accounts.revoke_mcp_token(user, id)

    {:noreply,
     socket
     |> assign(:minted, nil)
     |> load_tokens()
     |> put_flash(:info, "Token revoked.")}
  end
end
