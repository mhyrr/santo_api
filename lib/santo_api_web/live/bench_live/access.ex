defmodule SantoApiWeb.BenchLive.Access do
  @moduledoc """
  Operator controls for account credentials and per-car Stewardships.

  The two controls share a lookup screen, not a transition: suspension blocks
  the user's credential everywhere and leaves car authority intact; revocation
  removes authority over one car and leaves the account plus every other car
  intact. Privileged reads and mutations stay behind `SantoApi.Bench`.
  """

  use SantoApiWeb, :live_view

  alias SantoApi.Bench
  alias SantoApiWeb.UserAuth
  alias SantoApiWeb.VehicleLive.Presenter

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:search_form, to_form(%{"query" => ""}, as: :search))
     |> assign(:account, nil)
     |> assign(:account_action_form, nil)
     |> assign(:stewardship_count, 0)
     |> assign(:not_found?, false)
     |> assign(:error, nil)
     |> assign(:last_action, nil)
     |> stream_configure(:stewardships, dom_id: &"access-stewardship-#{&1.id}")
     |> stream_configure(:access_decisions, dom_id: &"access-decision-#{&1.id}")
     |> stream(:stewardships, [])
     |> stream(:access_decisions, [])}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    case Bench.find_access_account(socket.assigns.current_scope, query) do
      {:ok, nil} ->
        {:noreply,
         socket
         |> reset_account()
         |> assign(:search_form, to_form(%{"query" => query}, as: :search))
         |> assign(:not_found?, true)}

      {:ok, account} ->
        {:noreply,
         socket
         |> assign(:search_form, to_form(%{"query" => query}, as: :search))
         |> put_account(account)}

      {:error, :query_required} ->
        {:noreply,
         socket
         |> reset_account()
         |> assign(:error, "Enter an exact email address or handle.")}

      {:error, :not_authorized} ->
        {:noreply, operator_refused(socket)}
    end
  end

  def handle_event("search", _params, socket) do
    {:noreply,
     socket
     |> reset_account()
     |> assign(:error, "Enter an exact email address or handle.")}
  end

  def handle_event("suspend_account", %{"account_action" => params}, socket) do
    change_account_access(socket, params, :suspended)
  end

  def handle_event("restore_account", %{"account_action" => params}, socket) do
    change_account_access(socket, params, :restored)
  end

  def handle_event("revoke_stewardship", %{"stewardship_action" => params}, socket) do
    with %{"stewardship_id" => stewardship_id, "reason" => reason} <- params,
         :ok <- validate_reason(reason) do
      revoke_stewardship(socket, stewardship_id, String.trim(reason))
    else
      _invalid ->
        {:noreply,
         socket
         |> assign(:last_action, nil)
         |> assign(:error, "A concise stewardship-revocation reason is required.")}
    end
  end

  def handle_event("revoke_stewardship", _params, socket) do
    {:noreply,
     socket
     |> assign(:last_action, nil)
     |> assign(:error, "That stewardship action was incomplete. Nothing changed.")}
  end

  defp change_account_access(socket, params, action) do
    with %{
           "user_id" => user_id,
           "expected_version" => expected_version,
           "reason" => reason
         } <- params,
         :ok <- validate_reason(reason) do
      apply_account_access(socket, user_id, expected_version, String.trim(reason), action)
    else
      _invalid ->
        {:noreply,
         socket
         |> assign(:last_action, nil)
         |> assign(:error, "A concise account-access reason is required.")}
    end
  end

  defp apply_account_access(socket, user_id, expected_version, reason, action) do
    result =
      case action do
        :suspended ->
          Bench.suspend_account(
            socket.assigns.current_scope,
            user_id,
            expected_version,
            reason
          )

        :restored ->
          Bench.restore_account(
            socket.assigns.current_scope,
            user_id,
            expected_version,
            reason
          )
      end

    case result do
      {:ok, result} ->
        if action == :suspended, do: UserAuth.disconnect_sessions(result.session_tokens)

        {:noreply,
         socket
         |> refresh_selected()
         |> assign(:last_action, %{
           action: action,
           user_id: result.user.id,
           message: account_action_message(action)
         })}

      {:error, {:stale_access_state, _version}} ->
        {:noreply,
         stale_account(
           socket,
           "That account changed after this page loaded. The current state is shown; nothing else changed."
         )}

      {:error, :already_suspended} ->
        {:noreply, stale_account(socket, "That account is already suspended.")}

      {:error, :already_active} ->
        {:noreply, stale_account(socket, "That account is already active.")}

      {:error, :reason_required} ->
        {:noreply, assign(socket, :error, "A concise account-access reason is required.")}

      {:error, :reason_too_long} ->
        {:noreply, assign(socket, :error, "Keep the account-access reason under 500 characters.")}

      {:error, :not_authorized} ->
        {:noreply, operator_refused(socket)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:last_action, nil)
         |> assign(:error, "The account action was refused: #{inspect(reason)}")}
    end
  end

  defp revoke_stewardship(socket, stewardship_id, reason) do
    case Bench.revoke_stewardship(socket.assigns.current_scope, stewardship_id, reason) do
      {:ok, stewardship} ->
        {:noreply,
         socket
         |> refresh_selected()
         |> assign(:last_action, %{
           action: :stewardship_revoked,
           user_id: stewardship.user_id,
           stewardship_id: stewardship.id,
           message: "Stewardship revoked for this car. Other car authority is unchanged."
         })}

      {:error, :not_active} ->
        {:noreply,
         socket
         |> refresh_selected()
         |> assign(:last_action, nil)
         |> assign(:error, "That stewardship was already revoked. The stale row was removed.")}

      {:error, :reason_required} ->
        {:noreply, assign(socket, :error, "A concise stewardship-revocation reason is required.")}

      {:error, :reason_too_long} ->
        {:noreply,
         assign(socket, :error, "Keep the stewardship-revocation reason under 500 characters.")}

      {:error, :not_authorized} ->
        {:noreply, operator_refused(socket)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:last_action, nil)
         |> assign(:error, "The stewardship action was refused: #{inspect(reason)}")}
    end
  end

  defp put_account(socket, account) do
    stewardship_rows = Enum.map(account.active_stewardships, &decorate_stewardship/1)

    socket
    |> assign(:account, account)
    |> assign(:account_action_form, account_action_form(account.user))
    |> assign(:stewardship_count, length(stewardship_rows))
    |> assign(:not_found?, false)
    |> assign(:error, nil)
    |> assign(:last_action, nil)
    |> stream(:stewardships, stewardship_rows, reset: true)
    |> stream(:access_decisions, account.access_decisions, reset: true)
  end

  defp reset_account(socket) do
    socket
    |> assign(:account, nil)
    |> assign(:account_action_form, nil)
    |> assign(:stewardship_count, 0)
    |> assign(:not_found?, false)
    |> assign(:error, nil)
    |> assign(:last_action, nil)
    |> stream(:stewardships, [], reset: true)
    |> stream(:access_decisions, [], reset: true)
  end

  defp refresh_selected(%{assigns: %{account: %{user: user}}} = socket) do
    case Bench.find_access_account(socket.assigns.current_scope, user.email) do
      {:ok, account} when not is_nil(account) -> put_account(socket, account)
      _missing_or_refused -> reset_account(socket)
    end
  end

  defp refresh_selected(socket), do: socket

  defp stale_account(socket, message) do
    socket
    |> refresh_selected()
    |> assign(:last_action, nil)
    |> assign(:error, message)
  end

  defp account_action_form(user) do
    to_form(
      %{
        "user_id" => user.id,
        "expected_version" => Integer.to_string(user.access_version),
        "reason" => ""
      },
      as: :account_action
    )
  end

  defp decorate_stewardship(stewardship) do
    %{
      id: stewardship.id,
      stewardship: stewardship,
      title: Presenter.title(stewardship.vehicle),
      chassis: Presenter.chassis(stewardship.vehicle),
      revocation_form:
        to_form(
          %{"stewardship_id" => stewardship.id, "reason" => ""},
          as: :stewardship_action
        )
    }
  end

  defp validate_reason(reason) when is_binary(reason) do
    if String.trim(reason) == "", do: {:error, :reason_required}, else: :ok
  end

  defp validate_reason(_reason), do: {:error, :reason_required}

  defp operator_refused(socket) do
    socket
    |> put_flash(:error, "Operator access is required.")
    |> push_navigate(to: ~p"/")
  end

  defp account_action_message(:suspended),
    do: "Account access suspended. Car authority and history were not changed."

  defp account_action_message(:restored),
    do: "Account access restored. Existing stewardship state was not changed."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Account access
        <:subtitle>
          Suspend a credential everywhere, or revoke authority over one car. These are separate
          decisions with separate histories.
        </:subtitle>
        <:actions>
          <.button href={~p"/bench"} variant="secondary">Back to bench</.button>
        </:actions>
      </.header>

      <section id="access-search-panel" class="club-work-panel mt-6 p-5">
        <.form
          for={@search_form}
          id="access-search-form"
          phx-submit="search"
          class="grid min-w-0 gap-4 md:grid-cols-[minmax(0,1fr)_auto] md:items-end"
        >
          <.input
            field={@search_form[:query]}
            id="access-query"
            type="search"
            label="Account email or handle"
            placeholder="owner@example.com or owner-handle"
            autocomplete="off"
            required
          />
          <.button
            id="access-search-button"
            variant="primary"
            phx-disable-with="Finding…"
            class="mb-2 w-full md:w-auto"
          >
            Find account
          </.button>
        </.form>
      </section>

      <div :if={@not_found?} id="access-not-found" class="club-notice club-notice-info mt-4">
        No account matched that exact email or handle.
      </div>

      <div :if={@error} id="access-error" class="club-notice club-notice-warning mt-4">
        {@error}
      </div>

      <div
        :if={@last_action}
        id="access-success"
        data-action={@last_action.action}
        data-user-id={@last_action.user_id}
        data-stewardship-id={@last_action[:stewardship_id]}
        class="club-notice club-notice-success mt-4"
      >
        {@last_action.message}
      </div>

      <div :if={@account} class="mt-6 space-y-8">
        <section
          id="access-account"
          data-user-id={@account.user.id}
          data-state={account_state(@account.user)}
          class="club-work-panel min-w-0 overflow-hidden"
        >
          <div class="club-rule grid min-w-0 gap-5 border-b p-5 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-start">
            <div class="min-w-0">
              <p class="club-kicker">Credential</p>
              <p class="mt-2 break-all text-xl font-semibold">{@account.user.email}</p>
              <p class="club-code club-muted mt-1 break-all text-sm">@{@account.user.handle}</p>
            </div>
            <div class="lg:text-right">
              <span
                id="access-account-state"
                data-state={account_state(@account.user)}
                class={[
                  "club-status",
                  if(account_state(@account.user) == :active,
                    do: "club-status-verified",
                    else: "club-status-conflict"
                  )
                ]}
              >
                {account_state(@account.user)}
              </span>
              <p :if={@account.user.suspended_at} class="club-muted mt-2 text-xs tabular-nums">
                Since {format_timestamp(@account.user.suspended_at)}
              </p>
            </div>
          </div>

          <div class="grid min-w-0 gap-5 p-5 lg:grid-cols-2">
            <section
              id="access-party"
              data-party-id={@account.party && @account.party.id}
              class="club-rule min-w-0 border p-4"
            >
              <p class="club-kicker">Public Party identity</p>
              <%= if @account.party do %>
                <p class="mt-3 break-all font-mono text-base font-semibold">
                  @{@account.party.name}
                </p>
                <p class="club-muted mt-1 text-xs uppercase tracking-wider">
                  {@account.party.kind} party · permanent ledger attribution
                </p>
                <p class="club-code club-muted mt-3 break-all text-xs">{@account.party.id}</p>
              <% else %>
                <p class="club-muted mt-3 text-sm">
                  No Party exists yet. The account has not made an assertive ledger action.
                </p>
              <% end %>
            </section>

            <section id="access-account-controls" class="club-rule min-w-0 border p-4">
              <p class="club-kicker">Account credential</p>
              <p class="club-muted mt-2 text-sm leading-relaxed">
                This affects browser sessions, LiveView, authenticated controllers, magic links,
                and MCP tokens. It does not alter Party identity, entries, comments, media, or any
                Stewardship.
              </p>

              <.form
                :if={account_state(@account.user) == :active}
                for={@account_action_form}
                id={"suspend-account-form-#{@account.user.id}"}
                phx-submit="suspend_account"
                class="mt-4 grid min-w-0 gap-3"
              >
                <.input
                  field={@account_action_form[:user_id]}
                  id={"suspend-account-user-id-#{@account.user.id}"}
                  type="hidden"
                />
                <.input
                  field={@account_action_form[:expected_version]}
                  id={"suspend-account-version-#{@account.user.id}"}
                  type="hidden"
                />
                <.input
                  field={@account_action_form[:reason]}
                  id={"suspend-account-reason-#{@account.user.id}"}
                  type="text"
                  label="Suspension reason"
                  placeholder="Why this credential must stop authenticating"
                  maxlength="500"
                  required
                />
                <.button
                  id={"suspend-account-#{@account.user.id}"}
                  variant="danger"
                  phx-disable-with="Suspending…"
                  data-confirm="Suspend this account across browser and MCP access? Car authority and history will remain intact."
                  class="w-full sm:w-fit"
                >
                  Suspend account access
                </.button>
              </.form>

              <.form
                :if={account_state(@account.user) == :suspended}
                for={@account_action_form}
                id={"restore-account-form-#{@account.user.id}"}
                phx-submit="restore_account"
                class="mt-4 grid min-w-0 gap-3"
              >
                <.input
                  field={@account_action_form[:user_id]}
                  id={"restore-account-user-id-#{@account.user.id}"}
                  type="hidden"
                />
                <.input
                  field={@account_action_form[:expected_version]}
                  id={"restore-account-version-#{@account.user.id}"}
                  type="hidden"
                />
                <.input
                  field={@account_action_form[:reason]}
                  id={"restore-account-reason-#{@account.user.id}"}
                  type="text"
                  label="Restoration reason"
                  placeholder="What cleared the account for access"
                  maxlength="500"
                  required
                />
                <.button
                  id={"restore-account-#{@account.user.id}"}
                  variant="primary"
                  phx-disable-with="Restoring…"
                  class="w-full sm:w-fit"
                >
                  Restore account access
                </.button>
              </.form>
            </section>
          </div>

          <section class="club-rule border-t p-5">
            <div class="flex min-w-0 flex-wrap items-end justify-between gap-3">
              <div>
                <p class="club-kicker">Account access audit</p>
                <p class="club-muted mt-1 text-sm">Every suspension and restoration remains here.</p>
              </div>
              <span class="club-code club-muted text-xs">version {@account.user.access_version}</span>
            </div>
            <div id="access-decisions" phx-update="stream" class="club-list mt-4">
              <p id="access-decisions-empty" class="club-muted hidden py-4 text-sm only:block">
                No account-access decisions have been recorded.
              </p>
              <article
                :for={{dom_id, decision} <- @streams.access_decisions}
                id={dom_id}
                data-action={decision.action}
                class="club-list-row"
              >
                <div class="flex min-w-0 flex-wrap items-center justify-between gap-2">
                  <span class="club-status club-status-private">{decision.action}</span>
                  <span class="club-code club-muted text-xs">
                    {format_timestamp(decision.decided_at)}
                  </span>
                </div>
                <p class="mt-2 break-words text-sm">{decision.reason}</p>
                <p class="club-muted mt-1 break-all text-xs">
                  Decided by {operator_identity(decision.decided_by_user)}
                </p>
              </article>
            </div>
          </section>
        </section>

        <section id="access-stewardship-panel" class="min-w-0">
          <div class="flex min-w-0 flex-wrap items-end justify-between gap-4">
            <div>
              <p class="club-kicker">Per-car authority</p>
              <h2 class="mt-1 text-2xl font-semibold">Active Stewardships</h2>
              <p class="club-muted mt-2 max-w-2xl text-sm leading-relaxed">
                Revocation removes write and export authority over the named car only. The account,
                other cars, and every historical entry remain untouched.
              </p>
            </div>
            <div class="text-right">
              <p id="access-stewardship-count" class="club-code text-2xl font-semibold tabular-nums">
                {@stewardship_count}
              </p>
              <p class="club-muted text-xs uppercase tracking-wider">active cars</p>
            </div>
          </div>

          <div id="access-stewardships" phx-update="stream" class="mt-4 space-y-4">
            <div
              id="access-stewardships-empty"
              class="club-work-panel club-muted hidden p-6 text-center text-sm only:block"
            >
              This account has no active Stewardships.
            </div>
            <article
              :for={{dom_id, row} <- @streams.stewardships}
              id={dom_id}
              data-vehicle-id={row.stewardship.vehicle.id}
              class="club-work-panel grid min-w-0 gap-5 p-5 lg:grid-cols-[minmax(0,1fr)_minmax(18rem,0.8fr)] lg:items-end"
            >
              <div class="min-w-0">
                <span class="club-status club-status-verified">active</span>
                <h3 class="mt-3 break-words text-xl font-semibold">{row.title}</h3>
                <p :if={row.chassis} class="club-code club-muted mt-1 break-all text-xs">
                  {row.chassis}
                </p>
                <p class="club-muted mt-3 text-xs tabular-nums">
                  Steward since {format_timestamp(row.stewardship.decided_at)}
                </p>
                <div class="mt-3 flex min-w-0 flex-wrap gap-x-4 gap-y-2 text-sm">
                  <a href={~p"/v/#{row.stewardship.vehicle.public_id}"} class="club-link">Public car</a>
                  <.link
                    navigate={~p"/bench/vehicles/#{row.stewardship.vehicle.id}"}
                    class="club-link"
                  >
                    Vehicle workbench
                  </.link>
                </div>
              </div>

              <.form
                for={row.revocation_form}
                id={"revoke-stewardship-form-#{row.id}"}
                phx-submit="revoke_stewardship"
                class="grid min-w-0 gap-3"
              >
                <.input
                  field={row.revocation_form[:stewardship_id]}
                  id={"revoke-stewardship-id-#{row.id}"}
                  type="hidden"
                />
                <.input
                  field={row.revocation_form[:reason]}
                  id={"revoke-stewardship-reason-#{row.id}"}
                  type="text"
                  label="Revocation reason"
                  placeholder="Why authority over this car should end"
                  maxlength="500"
                  required
                />
                <.button
                  id={"revoke-stewardship-#{row.id}"}
                  variant="danger"
                  phx-disable-with="Revoking…"
                  data-confirm={"Revoke stewardship for #{row.title}? Prior entries remain attributed and every other car is unaffected."}
                  class="w-full sm:w-fit"
                >
                  Revoke this Stewardship
                </.button>
              </.form>
            </article>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp account_state(%{suspended_at: nil}), do: :active
  defp account_state(_user), do: :suspended

  defp format_timestamp(%DateTime{} = timestamp),
    do: Calendar.strftime(timestamp, "%Y-%m-%d %H:%M UTC")

  defp operator_identity(%{handle: handle, email: email}) when is_binary(handle),
    do: "@#{handle} (#{email})"

  defp operator_identity(%{email: email}), do: email
end
