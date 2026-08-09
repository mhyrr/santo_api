defmodule SantoApiWeb.VehicleLive.Update do
  @moduledoc """
  A stable, shareable page for one public logbook update and the conversation
  around it. Social state is read and written through `SantoApi.Social`; the
  claim ledger remains untouched.
  """

  use SantoApiWeb, :live_view

  alias SantoApi.Owners
  alias SantoApi.Registry
  alias SantoApi.Social
  alias SantoApi.Social.CommentReport
  alias SantoApiWeb.VehicleLive.Presenter

  @impl true
  def mount(%{"public_id" => public_id, "entry_ref" => entry_ref}, _session, socket) do
    with {:ok, vehicle} <- Registry.fetch_by_public_id(public_id),
         true <- visible_car?(socket.assigns.current_scope, vehicle),
         {:ok, entry} <- Registry.fetch_timeline_entry(vehicle.id, entry_ref) do
      scope = socket.assigns.current_scope

      {:ok,
       socket
       |> assign(:page_title, "#{Presenter.entry_headline(entry)} — #{Presenter.title(vehicle)}")
       |> assign(:vehicle, vehicle)
       |> assign(:entry, entry)
       |> assign(:parts, Presenter.entry_parts(entry))
       |> assign(:signed_in?, signed_in?(scope))
       |> assign(:viewer_id, viewer_id(scope))
       |> assign(:comment_form, comment_form(scope, vehicle, entry.entry_ref))
       |> assign(:reporting_id, nil)
       |> assign(:report_form, nil)
       |> assign(:error, nil)
       |> stream_configure(:comments, dom_id: &"comment-#{&1.id}")
       |> load_conversation()}
    else
      _absent -> raise SantoApiWeb.VehicleNotFound
    end
  end

  defp visible_car?(scope, vehicle) do
    Owners.published?(vehicle) or Owners.stewarding?(scope, vehicle)
  end

  defp signed_in?(%SantoApi.Accounts.Scope{user: %SantoApi.Accounts.User{}}), do: true
  defp signed_in?(_scope), do: false

  defp viewer_id(%SantoApi.Accounts.Scope{user: %SantoApi.Accounts.User{id: id}}), do: id
  defp viewer_id(_scope), do: nil

  defp comment_form(
         %SantoApi.Accounts.Scope{user: %SantoApi.Accounts.User{handle: handle}} = scope,
         vehicle,
         entry_ref
       )
       when is_binary(handle) do
    scope
    |> Social.change_comment(vehicle, entry_ref)
    |> to_form(as: :comment)
  end

  defp comment_form(_scope, _vehicle, _entry_ref), do: nil

  defp load_conversation(socket) do
    conversation =
      Social.conversation(
        socket.assigns.current_scope,
        socket.assigns.vehicle,
        socket.assigns.entry.entry_ref
      )

    socket
    |> assign(:like_count, conversation.like_count)
    |> assign(:liked?, conversation.liked?)
    |> assign(:comment_count, conversation.comment_count)
    |> assign(:comments_empty?, conversation.comments == [])
    |> stream(:comments, conversation.comments, reset: true)
  end

  @impl true
  def handle_event("toggle_like", _params, socket) do
    case Social.toggle_like(
           socket.assigns.current_scope,
           socket.assigns.vehicle,
           socket.assigns.entry.entry_ref
         ) do
      {:ok, _state} -> {:noreply, load_conversation(socket)}
      {:error, reason} -> {:noreply, assign(socket, :error, social_error(reason))}
    end
  end

  def handle_event("create_comment", %{"comment" => params}, socket) do
    scope = socket.assigns.current_scope
    vehicle = socket.assigns.vehicle
    entry_ref = socket.assigns.entry.entry_ref

    case Social.create_comment(scope, vehicle, entry_ref, params) do
      {:ok, _comment} ->
        {:noreply,
         socket
         |> assign(:comment_form, comment_form(scope, vehicle, entry_ref))
         |> assign(:error, nil)
         |> load_conversation()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :comment_form, to_form(changeset, as: :comment))}

      {:error, reason} ->
        {:noreply, assign(socket, :error, social_error(reason))}
    end
  end

  def handle_event("withdraw_comment", %{"id" => id}, socket) do
    case Social.withdraw_comment(socket.assigns.current_scope, id) do
      {:ok, _comment} -> {:noreply, socket |> assign(:error, nil) |> load_conversation()}
      {:error, reason} -> {:noreply, assign(socket, :error, social_error(reason))}
    end
  end

  def handle_event("open_report", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    case Social.fetch_comment(scope, socket.assigns.vehicle, socket.assigns.entry.entry_ref, id) do
      {:ok, comment} ->
        {:noreply,
         socket
         |> assign(:reporting_id, comment.id)
         |> assign(:report_form, scope |> Social.change_report(comment) |> to_form(as: :report))
         |> assign(:error, nil)
         |> load_conversation()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, social_error(reason))}
    end
  end

  def handle_event("cancel_report", _params, socket) do
    {:noreply,
     socket
     |> assign(:reporting_id, nil)
     |> assign(:report_form, nil)
     |> load_conversation()}
  end

  def handle_event("submit_report", %{"report" => params}, socket) do
    case Social.report_comment(socket.assigns.current_scope, socket.assigns.reporting_id, params) do
      {:ok, _report} ->
        {:noreply,
         socket
         |> put_flash(:info, "Report sent to the Vin Santo operators.")
         |> assign(:reporting_id, nil)
         |> assign(:report_form, nil)
         |> load_conversation()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :report_form, to_form(changeset, as: :report))}

      {:error, reason} ->
        {:noreply, assign(socket, :error, social_error(reason))}
    end
  end

  defp social_error(:authentication_required), do: "Sign in to join the conversation."
  defp social_error(:not_authorized), do: "That reply is not yours to withdraw."
  defp social_error(:own_comment), do: "You can withdraw your own reply instead."
  defp social_error(:not_found), do: "That update or reply is no longer available."
  defp social_error(_reason), do: "That could not be done."

  @impl true
  def render(assigns) do
    ~H"""
    <article id="update-page" class="club-update-page">
      <div class="club-wrap club-update-wrap">
        <.link navigate={~p"/v/#{@vehicle.public_id}"} class="club-back-link">
          <span aria-hidden="true">←</span> {Presenter.title(@vehicle)}
        </.link>

        <header id="update-card" class="club-update-card">
          <div class="club-update-card-rail" aria-hidden="true"></div>
          <div>
            <p class="club-kicker">{Presenter.on_date(@entry.date) || "Undated"}</p>
            <h1>{@parts.headline}</h1>
            <dl :if={@parts.details != []} class="club-update-details">
              <div :for={detail <- @parts.details}>
                <dt>{detail.label}</dt>
                <dd>{detail.value}</dd>
              </div>
            </dl>
            <p class="club-update-byline">
              Recorded by <span>@{@entry.party}</span>
            </p>
          </div>
        </header>

        <section
          id="update-conversation"
          class="club-conversation"
          aria-labelledby="conversation-heading"
        >
          <div class="club-conversation-head">
            <div>
              <p class="club-kicker club-kicker-paper">Around this update</p>
              <h2 id="conversation-heading">Appreciation and replies</h2>
            </div>

            <button
              :if={@signed_in?}
              type="button"
              id="update-like-button"
              phx-click="toggle_like"
              aria-pressed={to_string(@liked?)}
              class={["club-like-button", @liked? && "club-like-button-active"]}
            >
              <.icon name="hero-heart" class="size-5" />
              <span>{if @liked?, do: "Loved", else: "Love this"}</span>
              <strong>{@like_count}</strong>
            </button>

            <.link :if={not @signed_in?} navigate={~p"/users/log-in"} class="club-like-button">
              <.icon name="hero-heart" class="size-5" />
              <span>Love this</span>
              <strong>{@like_count}</strong>
            </.link>
          </div>

          <p :if={@error} id="update-social-error" class="club-form-error">{@error}</p>

          <div id="update-comments" phx-update="stream" class="club-comment-list">
            <div :if={@comments_empty?} id="update-comments-empty" class="club-comment-empty">
              No replies yet. A nod across the garage is allowed to be first.
            </div>

            <article :for={{id, comment} <- @streams.comments} id={id} class="club-comment">
              <div class="club-comment-avatar" aria-hidden="true">
                {comment.author_handle |> String.first() |> String.upcase()}
              </div>
              <div>
                <div class="club-comment-meta">
                  <strong>@{comment.author_handle}</strong>
                  <time datetime={DateTime.to_iso8601(comment.inserted_at)}>
                    {Calendar.strftime(comment.inserted_at, "%b %-d, %Y")}
                  </time>
                </div>
                <p>{comment.body}</p>
                <div class="club-comment-actions">
                  <button
                    :if={comment.author_user_id == @viewer_id}
                    type="button"
                    phx-click="withdraw_comment"
                    phx-value-id={comment.id}
                    data-confirm="Withdraw your reply?"
                  >
                    Withdraw
                  </button>
                  <button
                    :if={@signed_in? and comment.author_user_id != @viewer_id}
                    type="button"
                    phx-click="open_report"
                    phx-value-id={comment.id}
                  >
                    Report
                  </button>
                </div>

                <.form
                  :if={@reporting_id == comment.id}
                  for={@report_form}
                  id={"comment-report-#{comment.id}"}
                  phx-submit="submit_report"
                  class="club-report-form"
                >
                  <.input
                    field={@report_form[:reason]}
                    type="select"
                    label="Why should an operator look?"
                    options={Enum.map(CommentReport.reasons(), &{String.capitalize(&1), &1})}
                  />
                  <.input
                    field={@report_form[:detail]}
                    type="textarea"
                    label="Anything the operator should know"
                    rows="3"
                  />
                  <div class="club-inline-actions">
                    <button type="submit" class="club-button club-button-primary">Send report</button>
                    <button type="button" phx-click="cancel_report" class="club-text-button">Cancel</button>
                  </div>
                </.form>
              </div>
            </article>
          </div>

          <.form
            :if={@comment_form}
            for={@comment_form}
            id="update-comment-form"
            phx-submit="create_comment"
            class="club-comment-form"
          >
            <.input
              field={@comment_form[:body]}
              type="textarea"
              label="Leave a reply"
              placeholder="Ask a question, notice a detail, or just say you get it."
              rows="4"
            />
            <button type="submit" class="club-button club-button-primary">Post reply</button>
          </.form>

          <p :if={not @signed_in?} class="club-conversation-signin">
            <.link navigate={~p"/users/log-in"}>Sign in</.link> to reply.
          </p>
        </section>
      </div>
    </article>
    """
  end
end
