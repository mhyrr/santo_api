defmodule SantoApiWeb.OwnerLive.EventComposer do
  @moduledoc """
  One generic event composer for every kind of car day.

  The form finds or names an occurrence, then captures the owner's journal,
  tags, ordered text details, and labeled files or links. It never asks for an
  event type and never turns those details into durable car state.
  """

  use SantoApiWeb, :live_view

  alias SantoApi.Events
  alias SantoApi.Owners
  alias SantoApi.Registry
  alias SantoApiWeb.EventComponents
  alias SantoApiWeb.VehicleLive.Presenter

  @impl true
  def mount(%{"public_id" => public_id} = params, _session, socket) do
    case Registry.fetch_by_public_id(public_id) do
      {:ok, vehicle} ->
        if Owners.stewarding?(socket.assigns.current_scope, vehicle) do
          {:ok, open(socket, vehicle, params["entry_ref"])}
        else
          {:ok, turn_away(socket, vehicle)}
        end

      {:error, :not_found} ->
        raise SantoApiWeb.VehicleNotFound
    end
  end

  defp open(socket, vehicle, nil), do: mount_create(socket, vehicle)

  defp open(socket, vehicle, entry_ref) do
    case Events.participation_for_edit(socket.assigns.current_scope, vehicle, entry_ref) do
      {:ok, participation} ->
        mount_edit(socket, vehicle, participation)

      {:error, _reason} ->
        socket
        |> put_flash(:error, "That event account is not yours to edit.")
        |> redirect(to: ~p"/v/#{vehicle.public_id}")
    end
  end

  defp mount_create(socket, vehicle) do
    params = default_params()

    socket
    |> mount_shared(vehicle)
    |> assign(:page_title, "Add an event — #{Presenter.title(vehicle)}")
    |> assign(:editing?, false)
    |> assign(:participation, nil)
    |> assign(:selected_event, nil)
    |> assign(:event_results, Events.search_events())
    |> assign(:details, [blank_item()])
    |> assign(:links, [blank_link()])
    |> assign(:existing_attachments, [])
    |> assign(:params, params)
    |> assign_form(params)
  end

  defp mount_edit(socket, vehicle, participation) do
    details = Enum.map(participation.details, &detail_item/1)
    details = if details == [], do: [blank_item()], else: details
    existing_attachments = Enum.map(participation.attachments, &attachment_item/1)
    params = edit_params(participation, details, existing_attachments)

    socket
    |> mount_shared(vehicle)
    |> assign(:page_title, "Edit our day — #{Presenter.title(vehicle)}")
    |> assign(:editing?, true)
    |> assign(:participation, participation)
    |> assign(:selected_event, participation.event)
    |> assign(:event_results, [])
    |> assign(:details, details)
    |> assign(:links, [blank_link()])
    |> assign(:existing_attachments, existing_attachments)
    |> assign(:params, params)
    |> assign_form(params)
  end

  defp mount_shared(socket, vehicle) do
    socket
    |> assign(:vehicle, vehicle)
    |> assign(:search_form, to_form(%{"query" => ""}, as: :search))
    |> assign(:review, nil)
    |> assign(:error, nil)
    |> allow_upload(:attachments,
      accept: ~w(.jpg .jpeg .png .heic .webp .pdf .txt .mp4 .mov),
      max_entries: 6,
      max_file_size: 50_000_000
    )
  end

  defp turn_away(socket, vehicle) do
    socket
    |> put_flash(:error, "You do not maintain this car's log.")
    |> redirect(to: ~p"/v/#{vehicle.public_id}")
  end

  @impl true
  def handle_event("search", _params, %{assigns: %{editing?: true}} = socket),
    do: {:noreply, shared_event_locked(socket)}

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     socket
     |> assign(:event_results, Events.search_events(query))
     |> assign(:search_form, to_form(%{"query" => query}, as: :search))}
  end

  def handle_event("choose_event", _params, %{assigns: %{editing?: true}} = socket),
    do: {:noreply, shared_event_locked(socket)}

  def handle_event("choose_event", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.event_results, &(&1.id == id)) do
      nil ->
        {:noreply, assign(socket, :error, "That event is no longer available.")}

      event ->
        params = Map.put(socket.assigns.params, "event_id", event.id)

        {:noreply,
         socket
         |> assign(:selected_event, event)
         |> assign(:params, params)
         |> assign(:review, nil)
         |> assign(:error, nil)
         |> assign_form(params)}
    end
  end

  def handle_event("new_event", _params, %{assigns: %{editing?: true}} = socket),
    do: {:noreply, shared_event_locked(socket)}

  def handle_event("new_event", _params, socket) do
    params = Map.put(socket.assigns.params, "event_id", "")

    {:noreply,
     socket
     |> assign(:selected_event, nil)
     |> assign(:params, params)
     |> assign(:review, nil)
     |> assign(:error, nil)
     |> assign_form(params)}
  end

  def handle_event("validate", %{"event" => params}, socket) do
    {:noreply, sync_form(socket, params)}
  end

  def handle_event("add_detail", _params, socket) do
    details = socket.assigns.details ++ [blank_item()]
    {:noreply, socket |> assign(:details, details) |> put_detail_params(details)}
  end

  def handle_event("remove_detail", %{"id" => id}, socket) do
    details = Enum.reject(socket.assigns.details, &(&1.id == id))
    details = if details == [], do: [blank_item()], else: details
    {:noreply, socket |> assign(:details, details) |> put_detail_params(details)}
  end

  def handle_event("move_detail", %{"id" => id, "direction" => direction}, socket) do
    details = move(socket.assigns.details, id, direction)
    {:noreply, socket |> assign(:details, details) |> put_detail_params(details)}
  end

  def handle_event("add_link", _params, socket) do
    links = socket.assigns.links ++ [blank_link()]
    {:noreply, socket |> assign(:links, links) |> put_link_params(links)}
  end

  def handle_event("remove_link", %{"id" => id}, socket) do
    links = Enum.reject(socket.assigns.links, &(&1.id == id))
    links = if links == [], do: [blank_link()], else: links
    {:noreply, socket |> assign(:links, links) |> put_link_params(links)}
  end

  def handle_event("toggle_attachment_removal", %{"id" => id}, socket) do
    attachments =
      Enum.map(socket.assigns.existing_attachments, fn attachment ->
        if attachment.id == id,
          do: %{attachment | remove: not attachment.remove},
          else: attachment
      end)

    {:noreply,
     socket
     |> assign(:existing_attachments, attachments)
     |> put_existing_attachment_params(attachments)}
  end

  def handle_event("submit", %{"intent" => "review", "event" => params}, socket) do
    socket = sync_form(socket, params)
    attrs = draft_attrs(socket, params, [])

    case validate_draft(socket, attrs) do
      {:ok, review} ->
        {:noreply, socket |> assign(:review, review) |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply, socket |> assign(:review, nil) |> assign(:error, error(reason))}
    end
  end

  def handle_event("submit", %{"intent" => "save", "event" => params}, socket) do
    uploads = consume_attachments(socket, params)
    attrs = draft_attrs(socket, params, uploads)

    case commit(socket, attrs) do
      {:ok, participation} ->
        {:noreply,
         socket
         |> put_flash(:info, saved_message(socket.assigns.editing?))
         |> redirect(
           to: ~p"/v/#{socket.assigns.vehicle.public_id}/updates/#{participation.entry_ref}"
         )}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:review, nil)
         |> assign(:error, error(reason))
         |> sync_form(params)}
    end
  end

  def handle_event("edit", _params, socket), do: {:noreply, assign(socket, :review, nil)}

  defp validate_draft(%{assigns: %{editing?: true}} = socket, attrs) do
    Events.validate_participation_edit(
      socket.assigns.current_scope,
      socket.assigns.vehicle,
      socket.assigns.participation.entry_ref,
      attrs
    )
  end

  defp validate_draft(_socket, attrs), do: Events.validate_draft(attrs)

  defp commit(%{assigns: %{editing?: true}} = socket, attrs) do
    case Events.update_participation(
           socket.assigns.current_scope,
           socket.assigns.vehicle,
           socket.assigns.participation.entry_ref,
           attrs
         ) do
      {:ok, participation} -> {:ok, participation}
      {:error, reason} -> {:error, reason}
    end
  end

  defp commit(socket, attrs) do
    case Events.create_participation(socket.assigns.current_scope, socket.assigns.vehicle, attrs) do
      {:ok, result} -> {:ok, result.participation}
      {:error, reason} -> {:error, reason}
    end
  end

  defp shared_event_locked(socket) do
    assign(socket, :error, "Event details are shared across everyone who attended.")
  end

  defp saved_message(true), do: "Our day has been updated. The event itself is unchanged."
  defp saved_message(false), do: "Your day is on the car and the shared event."

  @impl true
  def render(assigns) do
    ~H"""
    <article
      id={if(@editing?, do: "event-participation-edit-page", else: "event-composer-page")}
      class="event-composer-page"
    >
      <div class="club-wrap event-composer-wrap">
        <.link navigate={~p"/v/#{@vehicle.public_id}"} class="club-back-link">
          <span aria-hidden="true">←</span> {Presenter.title(@vehicle)}
        </.link>

        <header class="event-composer-heading">
          <p class="club-kicker club-kicker-paper">
            {if @editing?,
              do: "Updating #{Presenter.title(@vehicle)}",
              else: "Adding to #{Presenter.title(@vehicle)}"}
          </p>
          <h1>{if @editing?, do: "Edit our day", else: "Add our day"}</h1>
          <p :if={@editing?}>You’re editing this car’s account of the event.</p>
          <p :if={not @editing?}>
            Find or name the shared event, then tell the car's version of it. Details are your
            labels and words; they stay with this day.
          </p>
        </header>

        <div class="event-composer-shell">
          <.form
            :if={is_nil(@review)}
            for={@form}
            id={if(@editing?, do: "event-participation-edit-form", else: "event-composer-form")}
            phx-change="validate"
            phx-submit="submit"
            class="event-composer-form"
          >
            <input type="hidden" name="event[event_id]" value={@params["event_id"]} />

            <section id="event-find" class="event-composer-step">
              <span class="event-step-number">01</span>
              <div>
                <p class="club-kicker club-kicker-paper">Find or name it</p>
                <h2>{if @editing?, do: "The shared event", else: "The shared coordinate"}</h2>

                <div :if={@editing?} id="event-shared-readonly" class="event-shared-readonly">
                  <strong>{@selected_event.title}</strong>
                  <span>{EventComponents.event_time(@selected_event)}</span>
                  <span>{@selected_event.place_text}</span>
                  <p>Event details are shared across everyone who attended.</p>
                </div>

                <div :if={not @editing? and @selected_event} class="event-selected">
                  <div>
                    <strong>{@selected_event.title}</strong>
                    <span>{EventComponents.event_time(@selected_event)} · {@selected_event.place_text}</span>
                  </div>
                  <button type="button" phx-click="new_event">Name a different event</button>
                </div>

                <div :if={not @editing? and is_nil(@selected_event)} class="event-new-fields">
                  <.input field={@form[:title]} type="text" label="Event title" required />
                  <div class="event-field-grid">
                    <.input field={@form[:starts_on]} type="date" label="Starts" required />
                    <.input field={@form[:ends_on]} type="date" label="Ends (optional)" />
                    <.input field={@form[:starts_at]} type="time" label="Start time" />
                    <.input field={@form[:ends_at]} type="time" label="End time" />
                  </div>
                  <.input
                    field={@form[:timezone]}
                    type="text"
                    label="Time zone (optional)"
                    placeholder="America/New_York"
                  />
                  <.input field={@form[:place_text]} type="text" label="Place" required />
                  <.input
                    field={@form[:description]}
                    type="textarea"
                    label="Shared description"
                    rows="3"
                  />
                  <.input
                    field={@form[:event_tags]}
                    type="text"
                    label="Event tags"
                    placeholder="WDCR, Summit Point, 2026"
                  />
                </div>
              </div>
            </section>

            <section class="event-composer-step">
              <span class="event-step-number">02</span>
              <div>
                <p class="club-kicker club-kicker-paper">Your account</p>
                <h2>What happened with this car?</h2>
                <.input
                  field={@form[:journal]}
                  type="textarea"
                  label="Journal"
                  placeholder="The part you will want to remember next season…"
                  rows="7"
                  required
                />
                <.input
                  field={@form[:participation_tags]}
                  type="text"
                  label="Your tags"
                  placeholder="rain, first event, setup test"
                />
              </div>
            </section>

            <section id="event-details-editor" class="event-composer-step">
              <span class="event-step-number">03</span>
              <div>
                <p class="club-kicker club-kicker-paper">Owner-defined details</p>
                <h2>Add what mattered</h2>
                <p class="event-step-note">
                  These are searchable words, not comparable metrics. “Best run” and “Instructor”
                  are examples, not fields Vin Santo owns.
                </p>

                <div class="event-detail-editor">
                  <div
                    :for={detail <- @details}
                    id={"event-detail-#{detail.id}"}
                    class="event-detail-row"
                  >
                    <.input
                      type="text"
                      id={"event_detail_#{detail.id}_label"}
                      name={"event[details][#{detail.id}][label]"}
                      value={detail.label}
                      label="Label"
                      placeholder="Best run"
                    />
                    <.input
                      type="text"
                      id={"event_detail_#{detail.id}_value"}
                      name={"event[details][#{detail.id}][value]"}
                      value={detail.value}
                      label="Value"
                      placeholder="44.182"
                    />
                    <div class="event-row-actions">
                      <button
                        type="button"
                        id={"event-detail-#{detail.id}-up"}
                        phx-click="move_detail"
                        phx-value-id={detail.id}
                        phx-value-direction="up"
                        aria-label="Move detail up"
                      >↑</button>
                      <button
                        type="button"
                        id={"event-detail-#{detail.id}-down"}
                        phx-click="move_detail"
                        phx-value-id={detail.id}
                        phx-value-direction="down"
                        aria-label="Move detail down"
                      >↓</button>
                      <button
                        type="button"
                        id={"event-detail-#{detail.id}-remove"}
                        phx-click="remove_detail"
                        phx-value-id={detail.id}
                        aria-label="Remove detail"
                      >Remove</button>
                    </div>
                  </div>
                </div>
                <button
                  type="button"
                  id="event-add-detail"
                  phx-click="add_detail"
                  class="event-text-action"
                >
                  + Add another detail
                </button>
              </div>
            </section>

            <section id="event-attachments-editor" class="event-composer-step">
              <span class="event-step-number">04</span>
              <div>
                <p class="club-kicker club-kicker-paper">Labeled media &amp; files</p>
                <h2>Keep the useful things attached</h2>

                <div
                  :if={@existing_attachments != []}
                  id="event-existing-attachments"
                  class="event-existing-attachments"
                >
                  <div
                    :for={attachment <- @existing_attachments}
                    id={"event-existing-attachment-#{attachment.id}"}
                    class={[
                      "event-existing-attachment",
                      attachment.remove && "event-existing-attachment-remove"
                    ]}
                    data-remove={to_string(attachment.remove)}
                  >
                    <div class="event-existing-attachment-heading">
                      <div>
                        <strong>{attachment_type_label(attachment)}</strong>
                        <span>{attachment.label}</span>
                      </div>
                      <button
                        type="button"
                        id={"event-existing-attachment-#{attachment.id}-remove"}
                        phx-click="toggle_attachment_removal"
                        phx-value-id={attachment.id}
                        class={[
                          "event-attachment-remove",
                          attachment.remove && "event-attachment-undo"
                        ]}
                        data-confirm={
                          if attachment.remove,
                            do: nil,
                            else:
                              "Remove this attachment when you save our day? The retained upload itself is not erased."
                        }
                      >
                        {if attachment.remove, do: "Keep attachment", else: "Remove"}
                      </button>
                    </div>

                    <div
                      :if={not attachment.remove}
                      class={[
                        "event-existing-attachment-fields",
                        attachment.artifact? && "event-existing-attachment-fields-file"
                      ]}
                    >
                      <.input
                        :if={not attachment.artifact?}
                        type="url"
                        id={"event_existing_attachment_#{attachment.id}_url"}
                        name={"event[existing_attachments][#{attachment.id}][url]"}
                        value={attachment.url}
                        label="Link"
                      />
                      <.input
                        type="text"
                        id={"event_existing_attachment_#{attachment.id}_label"}
                        name={"event[existing_attachments][#{attachment.id}][label]"}
                        value={attachment.label}
                        label="Label"
                      />
                      <.input
                        :if={not attachment.artifact?}
                        type="select"
                        id={"event_existing_attachment_#{attachment.id}_kind"}
                        name={"event[existing_attachments][#{attachment.id}][kind]"}
                        value={attachment.kind}
                        label="Kind"
                        options={attachment_kind_options()}
                      />
                    </div>

                    <input
                      type="hidden"
                      name={"event[existing_attachments][#{attachment.id}][id]"}
                      value={attachment.id}
                    />
                    <input
                      type="hidden"
                      name={"event[existing_attachments][#{attachment.id}][remove]"}
                      value={to_string(attachment.remove)}
                    />
                  </div>
                </div>

                <div class="event-upload-well">
                  <.live_file_input upload={@uploads.attachments} />
                  <p>Photos, video, PDF, or text · up to 50 MB each</p>
                </div>

                <div :if={@uploads.attachments.entries != []} class="event-upload-list">
                  <div :for={entry <- @uploads.attachments.entries} id={"event-upload-#{entry.ref}"}>
                    <span>{entry.client_name}</span>
                    <.input
                      type="text"
                      id={"event_upload_#{entry.ref}_label"}
                      name={"event[upload_labels][#{entry.ref}]"}
                      value={get_in(@params, ["upload_labels", entry.ref]) || entry.client_name}
                      label="Label"
                    />
                  </div>
                </div>

                <div class="event-link-editor">
                  <div :for={link <- @links} id={"event-link-#{link.id}"} class="event-link-row">
                    <.input
                      type="url"
                      id={"event_link_#{link.id}_url"}
                      name={"event[links][#{link.id}][url]"}
                      value={link.url}
                      label="Link"
                      placeholder="https://…"
                    />
                    <.input
                      type="text"
                      id={"event_link_#{link.id}_label"}
                      name={"event[links][#{link.id}][label]"}
                      value={link.label}
                      label="Label"
                      placeholder="Run 6 · onboard"
                    />
                    <.input
                      type="select"
                      id={"event_link_#{link.id}_kind"}
                      name={"event[links][#{link.id}][kind]"}
                      value={link.kind}
                      label="Kind"
                      options={[
                        {"Link", "link"},
                        {"Video", "video"},
                        {"Photo", "photo"},
                        {"File", "file"}
                      ]}
                    />
                    <button
                      type="button"
                      id={"event-link-#{link.id}-remove"}
                      phx-click="remove_link"
                      phx-value-id={link.id}
                    >Remove</button>
                  </div>
                </div>
                <button
                  type="button"
                  id="event-add-link"
                  phx-click="add_link"
                  class="event-text-action"
                >
                  + Add another link
                </button>
              </div>
            </section>

            <section :if={not @editing?} class="event-composer-step">
              <span class="event-step-number">05</span>
              <div>
                <p class="club-kicker club-kicker-paper">Visibility</p>
                <h2>Who can see this account?</h2>
                <.input
                  field={@form[:visibility]}
                  type="select"
                  label="Visibility"
                  options={[
                    {"Public — on the car and event", "public"},
                    {"Private account — only you; the event remains shared", "private"}
                  ]}
                />
                <p class="event-step-note">
                  One choice covers the journal, details, and uploaded files.
                </p>
              </div>
            </section>

            <p
              :if={@error}
              id={if(@editing?, do: "event-participation-edit-error", else: "event-composer-error")}
              class="club-form-error"
            >
              {@error}
            </p>
            <button
              type="submit"
              id={if(@editing?, do: "event-participation-edit-review", else: "event-composer-review")}
              name="intent"
              value="review"
              class="club-button club-button-primary"
            >
              Review our day
            </button>
          </.form>

          <aside
            :if={is_nil(@review) and not @editing?}
            id="event-find-existing"
            class="event-find-panel"
          >
            <p class="club-kicker">Already on Vin Santo?</p>
            <h2>Find the event</h2>
            <.form for={@search_form} id="event-search-form" phx-submit="search">
              <.input field={@search_form[:query]} type="search" label="Title, place, or tag" />
              <button type="submit" class="club-button club-button-secondary">Search</button>
            </.form>
            <div id="event-search-results" class="event-search-results">
              <button
                :for={event <- @event_results}
                id={"event-choice-#{event.id}"}
                type="button"
                phx-click="choose_event"
                phx-value-id={event.id}
              >
                <strong>{event.title}</strong>
                <span>{EventComponents.event_date(event)} · {event.place_text}</span>
              </button>
              <p :if={@event_results == []}>No match. Name it in the form.</p>
            </div>
          </aside>

          <section :if={@review} id="event-review" class="event-composer-review">
            <p class="club-kicker">Review before save</p>
            <h2>{@review.event.title}</h2>
            <p class="event-review-meta">
              {EventComponents.event_time(@review.event)} · {@review.event.place_text}
            </p>
            <p :if={@review.event.description}>{@review.event.description}</p>
            <div :if={@review.event.tags != []} class="theme-tags" aria-label="Event tags">
              <span :for={tag <- @review.event.tags}>{tag}</span>
            </div>
            <p>{@review.participation.journal}</p>
            <div
              :if={@review.participation.tags != []}
              class="theme-tags"
              aria-label="Participation tags"
            >
              <span :for={tag <- @review.participation.tags}>{tag}</span>
            </div>
            <dl :if={@review.participation.details != []}>
              <div :for={detail <- @review.participation.details}>
                <dt>{detail.label}</dt><dd>{detail.value}</dd>
              </div>
            </dl>
            <ul
              :if={
                kept_attachments(@existing_attachments) != [] or
                  @uploads.attachments.entries != [] or reviewed_links(@links) != []
              }
              id="event-review-attachments"
              class="event-review-attachments"
            >
              <li :for={attachment <- kept_attachments(@existing_attachments)}>
                {attachment.label}
              </li>
              <li :for={entry <- @uploads.attachments.entries}>
                {get_in(@params, ["upload_labels", entry.ref]) || entry.client_name}
              </li>
              <li :for={link <- reviewed_links(@links)}>{link.label || link.url}</li>
            </ul>
            <p class="event-review-visibility">
              Visibility: <strong>{visibility_label(@review.participation.visibility)}</strong>
            </p>
            <p class="event-review-note">
              <%= if @editing? do %>
                Saving updates this car’s account under the same permalink. Event details are
                shared across everyone who attended.
              <% else %>
                Saving creates one car update and links it to this shared event.
              <% end %>
              Event-local details do not change “As it sits.”
            </p>
            <p :if={@error} id="event-review-error" class="club-form-error">{@error}</p>
            <.form
              for={@form}
              id={
                if(@editing?,
                  do: "event-participation-edit-review-form",
                  else: "event-review-form"
                )
              }
              phx-submit="submit"
            >
              <input
                :for={{key, value} <- review_hidden_fields(@params)}
                type="hidden"
                name={key}
                value={value}
              />
              <button
                type="submit"
                id={if(@editing?, do: "event-participation-edit-save", else: "event-save")}
                name="intent"
                value="save"
                class="club-button club-button-primary"
              >
                {if @editing?, do: "Save our day", else: "Save our day"}
              </button>
              <button type="button" phx-click="edit" class="club-button club-button-secondary">
                Keep editing
              </button>
            </.form>
          </section>
        </div>
      </div>
    </article>
    """
  end

  defp sync_form(socket, params) do
    details = sync_items(socket.assigns.details, params["details"] || %{}, &blank_item/0)
    links = sync_items(socket.assigns.links, params["links"] || %{}, &blank_link/0)

    existing_attachments =
      sync_items(
        socket.assigns.existing_attachments,
        params["existing_attachments"] || %{},
        &blank_attachment/0
      )

    socket
    |> assign(:params, params)
    |> assign(:details, details)
    |> assign(:links, links)
    |> assign(:existing_attachments, existing_attachments)
    |> assign(:review, nil)
    |> assign(:error, nil)
    |> assign_form(params)
  end

  defp sync_items(existing, values, blank_fun) do
    known_ids = MapSet.new(existing, & &1.id)

    existing_items =
      Enum.map(existing, fn item ->
        attrs = Map.get(values, item.id, %{})

        Map.merge(item, safe_item_attrs(attrs))
      end)

    added_items =
      values
      |> Enum.reject(fn {id, _attrs} -> MapSet.member?(known_ids, id) end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {id, attrs} ->
        blank_fun.()
        |> Map.put(:id, id)
        |> Map.merge(safe_item_attrs(attrs))
      end)

    items = existing_items ++ added_items
    if items == [], do: [blank_fun.()], else: items
  end

  defp put_detail_params(socket, details) do
    params = Map.put(socket.assigns.params, "details", item_params(details, [:label, :value]))
    socket |> assign(:params, params) |> assign(:review, nil) |> assign_form(params)
  end

  defp put_link_params(socket, links) do
    params = Map.put(socket.assigns.params, "links", item_params(links, [:url, :label, :kind]))
    socket |> assign(:params, params) |> assign(:review, nil) |> assign_form(params)
  end

  defp put_existing_attachment_params(socket, attachments) do
    params =
      Map.put(
        socket.assigns.params,
        "existing_attachments",
        item_params(attachments, [:id, :label, :url, :kind, :remove])
      )

    socket |> assign(:params, params) |> assign(:review, nil) |> assign_form(params)
  end

  @item_fields %{
    "id" => :id,
    "label" => :label,
    "value" => :value,
    "url" => :url,
    "kind" => :kind,
    "remove" => :remove
  }

  defp safe_item_attrs(attrs) do
    attrs
    |> Enum.flat_map(fn {key, value} ->
      case Map.fetch(@item_fields, key) do
        {:ok, field} -> [{field, normalize_item_value(field, value)}]
        :error -> []
      end
    end)
    |> Map.new()
  end

  defp normalize_item_value(:remove, value), do: value in [true, "true", "1", "on"]
  defp normalize_item_value(_field, value), do: value

  defp item_params(items, fields) do
    Map.new(items, fn item ->
      {item.id, Map.new(fields, fn field -> {to_string(field), Map.get(item, field)} end)}
    end)
  end

  defp move(items, id, direction) do
    case Enum.find_index(items, &(&1.id == id)) do
      nil ->
        items

      index ->
        target = if direction == "up", do: index - 1, else: index + 1

        if target >= 0 and target < length(items) do
          item = Enum.at(items, index)
          other = Enum.at(items, target)
          items |> List.replace_at(index, other) |> List.replace_at(target, item)
        else
          items
        end
    end
  end

  defp draft_attrs(socket, params, uploads) do
    %{
      event_id: blank_to_nil(params["event_id"]),
      event: %{
        title: params["title"],
        starts_on: params["starts_on"],
        ends_on: blank_to_nil(params["ends_on"]),
        starts_at: blank_to_nil(params["starts_at"]),
        ends_at: blank_to_nil(params["ends_at"]),
        timezone: blank_to_nil(params["timezone"]),
        place_text: params["place_text"],
        description: params["description"],
        tags: tags(params["event_tags"])
      },
      participation: %{
        journal: params["journal"],
        tags: tags(params["participation_tags"]),
        details: detail_attrs(socket.assigns.details),
        visibility: params["visibility"] || "public"
      },
      existing_attachments: attachment_attrs(socket.assigns.existing_attachments),
      uploads: uploads,
      links: link_attrs(socket.assigns.links)
    }
  end

  defp detail_attrs(details) do
    details
    |> Enum.filter(&(present?(&1.label) or present?(&1.value)))
    |> Enum.map(&%{label: &1.label, value: &1.value})
  end

  defp link_attrs(links) do
    links
    |> Enum.filter(&present?(&1.url))
    |> Enum.map(&%{url: &1.url, label: &1.label, kind: &1.kind})
  end

  defp attachment_attrs(attachments) do
    Enum.map(attachments, fn attachment ->
      %{
        id: attachment.id,
        label: attachment.label,
        url: attachment.url,
        kind: attachment.kind,
        remove: attachment.remove
      }
    end)
  end

  defp consume_attachments(socket, params) do
    labels = params["upload_labels"] || %{}

    consume_uploaded_entries(socket, :attachments, fn %{path: path}, entry ->
      destination = Path.join(System.tmp_dir!(), "#{Ecto.UUID.generate()}-#{entry.client_name}")
      File.cp!(path, destination)

      {:ok,
       %{
         path: destination,
         filename: entry.client_name,
         mime: entry.client_type,
         label: Map.get(labels, entry.ref, entry.client_name),
         kind: upload_kind(entry.client_type)
       }}
    end)
  end

  defp upload_kind("image/" <> _rest), do: :photo
  defp upload_kind("video/" <> _rest), do: :video
  defp upload_kind(_mime), do: :file

  defp tags(nil), do: []

  defp tags(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp review_hidden_fields(params) do
    flatten_params(params, "event")
  end

  defp flatten_params(map, prefix) when is_map(map) do
    Enum.flat_map(map, fn {key, value} -> flatten_params(value, "#{prefix}[#{key}]") end)
  end

  defp flatten_params(value, prefix), do: [{prefix, value}]

  defp assign_form(socket, params), do: assign(socket, :form, to_form(params, as: :event))

  defp default_params do
    %{
      "event_id" => "",
      "starts_on" => Date.to_iso8601(Date.utc_today()),
      "visibility" => "public",
      "details" => %{},
      "links" => %{},
      "existing_attachments" => %{}
    }
  end

  defp edit_params(participation, details, existing_attachments) do
    %{
      "event_id" => participation.event_id,
      "journal" => participation.journal,
      "participation_tags" => Enum.join(participation.tags, ", "),
      "details" => item_params(details, [:label, :value]),
      "links" => %{},
      "existing_attachments" =>
        item_params(existing_attachments, [:id, :label, :url, :kind, :remove])
    }
  end

  defp blank_item, do: %{id: item_id(), label: "", value: ""}
  defp blank_link, do: %{id: item_id(), url: "", label: "", kind: "link"}

  defp blank_attachment do
    %{id: item_id(), url: nil, label: "", kind: "link", remove: false, artifact?: false}
  end

  defp detail_item(detail), do: %{id: item_id(), label: detail.label, value: detail.value}

  defp attachment_item(attachment) do
    %{
      id: attachment.id,
      url: attachment.url,
      label: attachment.label,
      kind: to_string(attachment.kind),
      remove: false,
      artifact?: not is_nil(attachment.artifact_id)
    }
  end

  defp item_id, do: System.unique_integer([:positive]) |> Integer.to_string()

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp reviewed_links(links), do: Enum.filter(links, &present?(&1.url))

  defp kept_attachments(attachments), do: Enum.reject(attachments, & &1.remove)

  defp attachment_type_label(%{artifact?: true, kind: "photo"}), do: "Uploaded photo"
  defp attachment_type_label(%{artifact?: true, kind: "video"}), do: "Uploaded video"
  defp attachment_type_label(%{artifact?: true}), do: "Uploaded file"
  defp attachment_type_label(%{kind: "photo"}), do: "Photo link"
  defp attachment_type_label(%{kind: "video"}), do: "Video link"
  defp attachment_type_label(%{kind: "file"}), do: "File link"
  defp attachment_type_label(_attachment), do: "Link"

  defp attachment_kind_options do
    [
      {"Link", "link"},
      {"Video", "video"},
      {"Photo", "photo"},
      {"File", "file"}
    ]
  end

  defp visibility_label(:private), do: "Private account"
  defp visibility_label(_public), do: "Public"

  defp error(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> List.first()
    |> case do
      {field, {message, _opts}} ->
        "#{field |> to_string() |> String.replace("_", " ")}: #{message}"

      nil ->
        "Review the event and your account before saving."
    end
  end

  defp error(:event_not_found), do: "That event is no longer available."
  defp error(:not_stewarded), do: "You no longer maintain this car."
  defp error(:not_authorized), do: "That event account is not yours to edit."
  defp error(:attachment_not_found), do: "One of those attachments is no longer available."
  defp error(_reason), do: "That could not be saved. Review the fields and try again."
end
