defmodule SantoApiWeb.GarageLive do
  @moduledoc """
  The signed-in member's daily surface: intake first, their cars immediately
  below it. Natural language and browser dictation both become an editable
  structured draft before `Owners.compose_entry/3` writes anything.
  """

  use SantoApiWeb, :live_view

  import Ecto.Changeset

  alias SantoApi.EntryExtraction
  alias SantoApi.Logbook.EntryDraft
  alias SantoApi.Owners
  alias SantoApiWeb.VehicleLive.Presenter

  @review_fields ~w(
    mode date odometer volume unit price currency summary performer area outing_kind
    venue result text private
  )a

  @impl true
  def mount(_params, _session, socket) do
    vehicles = Owners.list_stewarded_vehicles(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, "Your garage")
     |> assign(:vehicles, vehicles)
     |> assign(:garage_empty?, vehicles == [])
     |> assign(:intake_form, intake_form(vehicles))
     |> assign(:review_form, nil)
     |> assign(:review_mode, nil)
     |> assign(:review_vehicle, nil)
     |> assign(:source_text, nil)
     |> assign(:input_method, "text")
     |> assign(:parse_notice, nil)
     |> assign(:error, nil)
     |> put_car_stream(vehicles)}
  end

  defp put_car_stream(socket, vehicles) do
    counts = Owners.public_entry_counts(Enum.map(vehicles, & &1.id))
    stewards = Owners.stewards_for(Enum.map(vehicles, & &1.id))
    scope = socket.assigns.current_scope

    rows =
      Enum.map(vehicles, fn vehicle ->
        Presenter.car_card(vehicle,
          entries: Map.get(counts, vehicle.id, 0),
          latest: scope |> Owners.timeline(vehicle) |> List.first(),
          steward: stewards[vehicle.id]
        )
      end)

    stream(socket, :cars, rows)
  end

  @impl true
  def handle_event("parse_update", %{"intake" => params}, socket) do
    changeset = intake_changeset(params, socket.assigns.vehicles)

    with true <- changeset.valid?,
         %{} = vehicle <- garage_vehicle(socket, get_field(changeset, :vehicle)) do
      text = get_field(changeset, :text)
      input_method = get_field(changeset, :input_method) || "text"

      {mode, draft_params, notice, parsed?} = parse(text)

      {:noreply,
       socket
       |> assign(:review_vehicle, vehicle)
       |> assign(:review_mode, mode)
       |> assign(:review_form, review_form(mode, draft_params))
       |> assign(:source_text, text)
       |> assign(:input_method, input_method)
       |> assign(:parse_notice, notice)
       |> assign(:parsed?, parsed?)
       |> assign(:error, nil)}
    else
      false ->
        {:noreply,
         socket
         |> assign(:intake_form, to_form(%{changeset | action: :validate}, as: :intake))
         |> assign(:error, "Choose one of your cars and tell us what happened.")}

      nil ->
        {:noreply, assign(socket, :error, "That car is no longer in your garage.")}
    end
  end

  def handle_event("review_changed", %{"review" => params}, socket) do
    mode = mode(params["mode"])

    {:noreply,
     socket
     |> assign(:review_mode, mode)
     |> assign(:review_form, review_form(mode, params))
     |> assign(:error, nil)}
  end

  def handle_event("save_update", %{"review" => params}, socket) do
    mode = mode(params["mode"])
    vehicle = socket.assigns.review_vehicle

    with true <- is_map(vehicle) and Owners.stewarding?(socket.assigns.current_scope, vehicle),
         {:ok, claims} <- EntryDraft.claims(mode, params),
         {:ok, entry} <-
           Owners.compose_entry(socket.assigns.current_scope, vehicle, %{
             date: params["date"],
             claims: claims,
             visibility: visibility(params["private"]),
             method: mediation(socket),
             method_meta: %{
               "surface" => "garage",
               "input" => socket.assigns.input_method,
               "parser" => if(socket.assigns.parsed?, do: "entry_extraction", else: "fallback")
             }
           }) do
      {:noreply,
       socket
       |> put_flash(:info, "Logged. The update is now part of the car's story.")
       |> push_navigate(to: ~p"/v/#{vehicle.public_id}/updates/#{entry.entry_ref}")}
    else
      false ->
        {:noreply, assign(socket, :error, "You no longer maintain that car's log.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:review_mode, mode)
         |> assign(:review_form, review_form(mode, params))
         |> assign(:error, refusal(reason))}
    end
  end

  def handle_event("cancel_review", _params, socket) do
    vehicles = socket.assigns.vehicles

    {:noreply,
     socket
     |> assign(:review_form, nil)
     |> assign(:review_mode, nil)
     |> assign(:review_vehicle, nil)
     |> assign(:parse_notice, nil)
     |> assign(:error, nil)
     |> assign(
       :intake_form,
       intake_form(vehicles, %{
         "vehicle" => socket.assigns.review_vehicle.public_id,
         "text" => socket.assigns.source_text,
         "input_method" => socket.assigns.input_method
       })
     )}
  end

  defp parse(text) do
    case EntryExtraction.extract(text) do
      {:ok, reading} ->
        {mode, params} = EntryDraft.from_reading(reading, text)

        {mode, params,
         "We read this as #{mode_label(mode)}. Check the fields before it goes on the car.", true}

      {:error, _reason} ->
        {mode, params} = EntryDraft.note_fallback(text)

        {mode, params, "We could not structure that safely, so every word is here as a note.",
         false}
    end
  end

  defp garage_vehicle(socket, public_id) do
    Enum.find(socket.assigns.vehicles, &(&1.public_id == public_id))
  end

  defp intake_form(vehicles, attrs \\ %{}) do
    defaults = %{
      "vehicle" => vehicles |> List.first() |> then(&(&1 && &1.public_id)),
      "text" => "",
      "input_method" => "text"
    }

    attrs = Map.merge(defaults, attrs)
    to_form(intake_changeset(attrs, vehicles), as: :intake)
  end

  defp intake_changeset(attrs, vehicles) do
    vehicle_ids = MapSet.new(vehicles, & &1.public_id)

    {%{}, %{vehicle: :string, text: :string, input_method: :string}}
    |> cast(attrs, [:vehicle, :text, :input_method])
    |> update_change(:text, &String.trim/1)
    |> validate_required([:vehicle, :text])
    |> validate_length(:text, max: 4_000)
    |> validate_inclusion(:vehicle, vehicle_ids)
    |> validate_inclusion(:input_method, ~w(text voice))
  end

  defp review_form(mode, attrs) do
    attrs = Map.put(attrs, "mode", Atom.to_string(mode))

    types = Map.new(@review_fields, &{&1, if(&1 == :private, do: :boolean, else: :string)})

    {%{}, types}
    |> cast(attrs, @review_fields)
    |> to_form(as: :review)
  end

  defp mediation(socket) do
    if socket.assigns.parsed? or socket.assigns.input_method == "voice",
      do: :llm_extract,
      else: :human
  end

  defp visibility(value) when value in [true, "true", "on", "1"], do: :private
  defp visibility(_value), do: :public

  defp mode(value) when value in ~w(fuel service modification outing note),
    do: String.to_existing_atom(value)

  defp mode(_value), do: :note

  defp mode_label(:fuel), do: "a fill-up"
  defp mode_label(:service), do: "service"
  defp mode_label(:modification), do: "a modification"
  defp mode_label(:outing), do: "a drive"
  defp mode_label(:note), do: "a note"

  defp refusal(:not_stewarded), do: "You no longer maintain that car's log."
  defp refusal(:missing_date), do: "Check the date."
  defp refusal(%Ecto.Changeset{}), do: "One of those values does not fit the record."
  defp refusal(message) when is_binary(message), do: message
  defp refusal(_reason), do: "That update could not be saved."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="garage-page" class="club-garage-page">
        <section class="club-garage-intake" aria-labelledby="garage-heading">
          <div class="club-garage-intake-copy">
            <p class="club-kicker">Your garage</p>
            <h1 id="garage-heading" class="club-display">What happened with the car?</h1>
            <p>
              Say it the way you would to a friend. We will turn it into an update and show it
              back before anything is saved.
            </p>
          </div>

          <div :if={@garage_empty?} id="garage-empty-intake" class="club-garage-empty">
            <p>You need a car in the garage before there is anything to log.</p>
            <.button navigate={~p"/start"} variant="primary">Add your first car</.button>
          </div>

          <.form
            :if={not @garage_empty? and is_nil(@review_form)}
            for={@intake_form}
            id="garage-intake-form"
            phx-submit="parse_update"
            class="club-intake-form"
          >
            <%= if length(@vehicles) == 1 do %>
              <input
                type="hidden"
                name={@intake_form[:vehicle].name}
                value={@intake_form[:vehicle].value}
              />
              <div class="club-intake-car-context">
                <span>Adding to</span>
                <strong>{Presenter.title(List.first(@vehicles))}</strong>
              </div>
            <% else %>
              <.input
                field={@intake_form[:vehicle]}
                type="select"
                label="Which car?"
                options={Enum.map(@vehicles, &{Presenter.title(&1), &1.public_id})}
              />
            <% end %>

            <div id="garage-dictation" phx-hook=".GarageDictation" phx-update="ignore">
              <.input
                field={@intake_form[:text]}
                type="textarea"
                label="What happened?"
                placeholder="Filled it yesterday — 13.1 gallons at $5.15, 41,660 miles."
                rows="4"
              />
              <input
                type="hidden"
                id="garage-input-method"
                name="intake[input_method]"
                value={@intake_form[:input_method].value || "text"}
              />
              <div class="club-dictation-actions">
                <button
                  type="button"
                  id="garage-voice-button"
                  class="club-voice-button"
                  aria-pressed="false"
                  aria-label="Dictate update"
                  title="Dictate update"
                >
                  <.icon name="hero-microphone" class="size-5" />
                  <span class="sr-only">Dictate update</span>
                </button>
                <span id="garage-voice-status" class="sr-only" aria-live="polite">
                  Dictation is available.
                </span>
              </div>
            </div>

            <p :if={@error} id="garage-intake-error" class="club-form-error">{@error}</p>

            <button type="submit" id="garage-review-button" class="club-button club-button-primary">
              Review the update
            </button>
          </.form>

          <.form
            :if={@review_form}
            for={@review_form}
            id="garage-review-form"
            phx-change="review_changed"
            phx-submit="save_update"
            class="club-review-form"
          >
            <div class="club-review-heading">
              <div>
                <p class="club-kicker">Read-back · {Presenter.title(@review_vehicle)}</p>
                <h2>Does this look right?</h2>
              </div>
              <button type="button" phx-click="cancel_review" class="club-text-button">Start over</button>
            </div>

            <p id="garage-parse-notice" class="club-review-notice">{@parse_notice}</p>

            <div class="club-review-grid">
              <.input
                field={@review_form[:mode]}
                type="select"
                label="Kind of update"
                options={[
                  {"Fill-up", "fuel"},
                  {"Service", "service"},
                  {"Modification", "modification"},
                  {"Drive / event", "outing"},
                  {"Note", "note"}
                ]}
              />
              <.input field={@review_form[:date]} type="date" label="Date" />
            </div>

            <.review_fields mode={@review_mode} form={@review_form} />

            <.input
              field={@review_form[:private]}
              type="checkbox"
              label="Keep this update off the public page"
            />

            <p :if={@error} id="garage-review-error" class="club-form-error">{@error}</p>

            <button type="submit" id="garage-save-update" class="club-button club-button-primary">
              Put it on the car
            </button>
          </.form>
        </section>

        <section id="your-cars" class="club-garage-cars" aria-labelledby="your-cars-heading">
          <div class="club-garage-section-head">
            <div>
              <p class="club-kicker club-kicker-paper">The cars you maintain</p>
              <h2 id="your-cars-heading" class="club-display club-display-dark">In your garage</h2>
            </div>
            <.button navigate={~p"/start"} variant="secondary">Add a car</.button>
          </div>

          <div id="garage-cars" phx-update="stream" class="club-car-grid">
            <div :if={@garage_empty?} id="garage-cars-empty" class="club-empty-state">
              <p>Your garage is empty. The floor is suspiciously clean.</p>
              <.link navigate={~p"/start"}>Add a car</.link>
            </div>
            <.car_card :for={{id, row} <- @streams.cars} id={id} row={row} actions={true} />
          </div>
        </section>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".GarageDictation">
        export default {
          mounted() {
            this.button = this.el.querySelector("#garage-voice-button")
            this.status = this.el.querySelector("#garage-voice-status")
            this.textarea = this.el.querySelector("textarea")
            this.methodField = this.el.querySelector("#garage-input-method")
            const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition

            if (!Recognition) {
              this.button.hidden = true
              this.status.textContent = "This browser does not offer dictation."
              return
            }

            this.recognition = new Recognition()
            this.recognition.continuous = true
            this.recognition.interimResults = true
            this.recognition.lang = document.documentElement.lang || "en-US"
            this.listening = false
            this.baseText = ""

            this.onClick = () => this.toggle()
            this.button.addEventListener("click", this.onClick)

            this.recognition.onstart = () => {
              this.listening = true
              this.baseText = this.textarea.value.trim()
              this.button.setAttribute("aria-pressed", "true")
              this.setButtonLabel("Stop dictation")
              this.status.textContent = "Listening…"
            }

            this.recognition.onresult = event => {
              let transcript = ""
              for (let i = 0; i < event.results.length; i++) {
                transcript += event.results[i][0].transcript
              }
              const separator = this.baseText && transcript ? " " : ""
              this.textarea.value = `${this.baseText}${separator}${transcript}`.trim()
              this.methodField.value = "voice"
              this.textarea.dispatchEvent(new Event("input", {bubbles: true}))
            }

            this.recognition.onerror = event => {
              this.status.textContent = event.error === "not-allowed"
                ? "Microphone access was not allowed. You can still type the update."
                : "Dictation stopped. Keep the transcript or try again."
            }

            this.recognition.onend = () => {
              this.listening = false
              this.button.setAttribute("aria-pressed", "false")
              this.setButtonLabel("Dictate update")
              if (!this.status.textContent.includes("not allowed")) {
                this.status.textContent = "Transcript ready. Review it when you are done."
              }
            }
          },

          setButtonLabel(label) {
            this.button.querySelector("span").textContent = label
            this.button.setAttribute("aria-label", label)
            this.button.title = label
          },

          toggle() {
            if (this.listening) this.recognition.stop()
            else this.recognition.start()
          },

          destroyed() {
            if (this.button && this.onClick) this.button.removeEventListener("click", this.onClick)
            if (this.recognition && this.listening) this.recognition.stop()
          }
        }
      </script>
    </Layouts.app>
    """
  end

  attr :mode, :atom, required: true
  attr :form, :map, required: true

  defp review_fields(assigns) do
    ~H"""
    <div class="club-review-fields">
      <%= case @mode do %>
        <% :fuel -> %>
          <div class="club-review-grid club-review-grid-three">
            <.input field={@form[:odometer]} type="text" label="Odometer" inputmode="numeric" />
            <.input field={@form[:volume]} type="text" label="Fuel amount" inputmode="decimal" />
            <.input
              field={@form[:unit]}
              type="select"
              label="Unit"
              options={[{"Gallons", "gal"}, {"Liters", "l"}]}
            />
          </div>
          <div class="club-review-grid">
            <.input field={@form[:price]} type="text" label="Total paid" inputmode="decimal" />
            <.input
              field={@form[:currency]}
              type="text"
              label="Currency"
              maxlength="3"
              autocapitalize="characters"
            />
          </div>
        <% :service -> %>
          <.input field={@form[:summary]} type="textarea" label="What was done" rows="3" />
          <div class="club-review-grid">
            <.input field={@form[:performer]} type="text" label="Who did it" />
            <.input field={@form[:odometer]} type="text" label="Odometer" inputmode="numeric" />
          </div>
        <% :modification -> %>
          <.input field={@form[:summary]} type="textarea" label="What changed" rows="3" />
          <.input field={@form[:area]} type="text" label="Area" />
        <% :outing -> %>
          <.input field={@form[:summary]} type="textarea" label="What happened" rows="3" />
          <div class="club-review-grid">
            <.input
              field={@form[:outing_kind]}
              type="select"
              label="Kind of day"
              options={[
                {"Drive", "drive"},
                {"Track", "track"},
                {"Autocross", "autocross"},
                {"Show", "show"},
                {"Other", "other"}
              ]}
            />
            <.input field={@form[:venue]} type="text" label="Place" />
          </div>
          <div class="club-review-grid">
            <.input field={@form[:result]} type="text" label="Result" />
            <.input field={@form[:odometer]} type="text" label="Odometer" inputmode="numeric" />
          </div>
        <% :note -> %>
          <.input field={@form[:text]} type="textarea" label="Note" rows="5" />
      <% end %>
    </div>
    """
  end
end
