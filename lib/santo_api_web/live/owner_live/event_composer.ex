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
  def mount(%{"public_id" => public_id}, _session, socket) do
    case Registry.fetch_by_public_id(public_id) do
      {:ok, vehicle} ->
        if Owners.stewarding?(socket.assigns.current_scope, vehicle) do
          params = default_params()

          {:ok,
           socket
           |> assign(:page_title, "Add an event — #{Presenter.title(vehicle)}")
           |> assign(:vehicle, vehicle)
           |> assign(:selected_event, nil)
           |> assign(:event_results, Events.search_events())
           |> assign(:search_form, to_form(%{"query" => ""}, as: :search))
           |> assign(:details, [blank_item()])
           |> assign(:links, [blank_link()])
           |> assign(:params, params)
           |> assign(:review, nil)
           |> assign(:error, nil)
           |> assign_form(params)
           |> allow_upload(:attachments,
             accept: ~w(.jpg .jpeg .png .heic .webp .pdf .txt .mp4 .mov),
             max_entries: 6,
             max_file_size: 50_000_000
           )}
        else
          {:ok, turn_away(socket, vehicle)}
        end

      {:error, :not_found} ->
        raise SantoApiWeb.VehicleNotFound
    end
  end

  defp turn_away(socket, vehicle) do
    socket
    |> put_flash(:error, "You do not maintain this car's log.")
    |> redirect(to: ~p"/v/#{vehicle.public_id}")
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     socket
     |> assign(:event_results, Events.search_events(query))
     |> assign(:search_form, to_form(%{"query" => query}, as: :search))}
  end

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

  def handle_event("submit", %{"intent" => "review", "event" => params}, socket) do
    socket = sync_form(socket, params)
    attrs = draft_attrs(socket, params, [])

    case Events.validate_draft(attrs) do
      {:ok, review} ->
        {:noreply, socket |> assign(:review, review) |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply, socket |> assign(:review, nil) |> assign(:error, error(reason))}
    end
  end

  def handle_event("submit", %{"intent" => "save", "event" => params}, socket) do
    uploads = consume_attachments(socket, params)
    attrs = draft_attrs(socket, params, uploads)

    case Events.create_participation(socket.assigns.current_scope, socket.assigns.vehicle, attrs) do
      {:ok, result} ->
        {:noreply,
         socket
         |> put_flash(:info, "Your day is on the car and the shared event.")
         |> redirect(
           to:
             ~p"/v/#{socket.assigns.vehicle.public_id}/updates/#{result.participation.entry_ref}"
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

  @impl true
  def render(assigns) do
    ~H"""
    <article id="event-composer-page" class="event-composer-page">
      <div class="club-wrap event-composer-wrap">
        <.link navigate={~p"/v/#{@vehicle.public_id}"} class="club-back-link">
          <span aria-hidden="true">←</span> {Presenter.title(@vehicle)}
        </.link>

        <header class="event-composer-heading">
          <p class="club-kicker club-kicker-paper">Adding to {Presenter.title(@vehicle)}</p>
          <h1>Add our day</h1>
          <p>
            Find or name the shared event, then tell the car's version of it. Details are your
            labels and words; they stay with this day.
          </p>
        </header>

        <div class="event-composer-shell">
          <.form
            :if={is_nil(@review)}
            for={@form}
            id="event-composer-form"
            phx-change="validate"
            phx-submit="submit"
            class="event-composer-form"
          >
            <input type="hidden" name="event[event_id]" value={@params["event_id"]} />

            <section id="event-find" class="event-composer-step">
              <span class="event-step-number">01</span>
              <div>
                <p class="club-kicker club-kicker-paper">Find or name it</p>
                <h2>The shared coordinate</h2>

                <div :if={@selected_event} class="event-selected">
                  <div>
                    <strong>{@selected_event.title}</strong>
                    <span>{EventComponents.event_time(@selected_event)} · {@selected_event.place_text}</span>
                  </div>
                  <button type="button" phx-click="new_event">Name a different event</button>
                </div>

                <div :if={is_nil(@selected_event)} class="event-new-fields">
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
                        phx-click="move_detail"
                        phx-value-id={detail.id}
                        phx-value-direction="up"
                        aria-label="Move detail up"
                      >↑</button>
                      <button
                        type="button"
                        phx-click="move_detail"
                        phx-value-id={detail.id}
                        phx-value-direction="down"
                        aria-label="Move detail down"
                      >↓</button>
                      <button
                        type="button"
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
                    <button type="button" phx-click="remove_link" phx-value-id={link.id}>Remove</button>
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

            <section class="event-composer-step">
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

            <p :if={@error} id="event-composer-error" class="club-form-error">{@error}</p>
            <button type="submit" name="intent" value="review" class="club-button club-button-primary">
              Review our day
            </button>
          </.form>

          <aside :if={is_nil(@review)} id="event-find-existing" class="event-find-panel">
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
              :if={@uploads.attachments.entries != [] or reviewed_links(@links) != []}
              id="event-review-attachments"
              class="event-review-attachments"
            >
              <li :for={entry <- @uploads.attachments.entries}>
                {get_in(@params, ["upload_labels", entry.ref]) || entry.client_name}
              </li>
              <li :for={link <- reviewed_links(@links)}>{link.label || link.url}</li>
            </ul>
            <p class="event-review-visibility">
              Visibility: <strong>{visibility_label(@review.participation.visibility)}</strong>
            </p>
            <p class="event-review-note">
              Saving creates one car update and links it to this shared event. Event-local details
              do not change “As it sits.”
            </p>
            <p :if={@error} id="event-review-error" class="club-form-error">{@error}</p>
            <.form for={@form} id="event-review-form" phx-submit="submit">
              <input
                :for={{key, value} <- review_hidden_fields(@params)}
                type="hidden"
                name={key}
                value={value}
              />
              <button type="submit" name="intent" value="save" class="club-button club-button-primary">
                Save our day
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

    socket
    |> assign(:params, params)
    |> assign(:details, details)
    |> assign(:links, links)
    |> assign(:review, nil)
    |> assign(:error, nil)
    |> assign_form(params)
  end

  defp sync_items(existing, values, blank_fun) do
    known_ids = MapSet.new(existing, & &1.id)

    existing_items =
      Enum.map(existing, fn item ->
        attrs = Map.get(values, item.id, %{})

        Map.merge(
          item,
          Map.new(attrs, fn {key, value} -> {String.to_existing_atom(key), value} end)
        )
      end)

    added_items =
      values
      |> Enum.reject(fn {id, _attrs} -> MapSet.member?(known_ids, id) end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {id, attrs} ->
        blank_fun.()
        |> Map.put(:id, id)
        |> Map.merge(Map.new(attrs, fn {key, value} -> {String.to_existing_atom(key), value} end))
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
      "links" => %{}
    }
  end

  defp blank_item, do: %{id: item_id(), label: "", value: ""}
  defp blank_link, do: %{id: item_id(), url: "", label: "", kind: "link"}
  defp item_id, do: System.unique_integer([:positive]) |> Integer.to_string()

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp reviewed_links(links), do: Enum.filter(links, &present?(&1.url))

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
  defp error(_reason), do: "That could not be saved. Review the fields and try again."
end
