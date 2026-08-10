defmodule SantoApiWeb.OwnerLive.Composer do
  @moduledoc """
  The entry composer (owner_surface §1) — the make-or-break surface.

  Phone-first, because the entry moment is standing at the pump or in the garage
  with greasy hands. Six modes: **Fill-up | Service | Mod | Drive | Plan | Note**. Fill-up opens
  selected with the odometer already carried forward from the last reading, so a
  fill-up is three numbers and a save — the Fuelly bar, which v1 has to clear.

  Nothing here decides truth. This module translates a form into vocabulary
  claims and hands them to `SantoApi.Owners.compose_entry/3`, which owns the
  transaction, the `entry_ref`, and the scope split. What a "Fill-up" *means* —
  which predicates it produces — is the composer's business and lives here; the
  agent surface (§8) takes typed claims directly and never sees this mapping.

  Two entry points, one surface (§8, decided 2026-08-03). With an `entry_ref`
  this is the correction form: the same six modes, prefilled from an entry
  already in the ledger, saving through `Owners.amend_entry/4`. The mapping
  runs backwards to fill the form and forwards to save it, so the two can
  never drift — and an entry the backwards direction cannot restate exactly is
  refused rather than silently reshaped.

  The form itself remains deterministic. Natural-language and voice intake on
  `/garage` may prefill the same grammar, but the owner reviews ordinary fields
  and `EntryDraft` performs every parse and calculation before the ledger sees
  a claim. MCP remains the direct agent path.
  """

  use SantoApiWeb, :live_view

  alias SantoApi.Owners
  alias SantoApi.Logbook.EntryDraft
  alias SantoApi.Registry
  alias SantoApiWeb.VehicleLive.Presenter

  @modes [
    {:fuel, "Fill-up"},
    {:service, "Service"},
    {:modification, "Mod"},
    {:outing, "Drive"},
    {:plan, "Plan"},
    {:note, "Note"}
  ]

  @impl true
  def mount(%{"public_id" => public_id} = params, _session, socket) do
    # Signing in is the router's job; stewarding *this* car is ours. A signed-in
    # stranger is sent back to the public record rather than shown an error page —
    # they are allowed to read this car, just not to write to it.
    case Registry.fetch_by_public_id(public_id) do
      {:ok, vehicle} ->
        if Owners.stewarding?(socket.assigns.current_scope, vehicle),
          do: {:ok, open(socket, vehicle, params["entry_ref"], params["mode"])},
          else: {:ok, turn_away(socket, vehicle, "You do not maintain this car's log.")}

      {:error, :not_found} ->
        raise SantoApiWeb.VehicleNotFound
    end
  end

  defp open(socket, vehicle, nil, requested_mode),
    do: mount_composer(socket, vehicle, requested_mode)

  # Stewarding the car is not enough to correct a line of it: `Owners.entry/3`
  # hands back the caller's *own* claims, so a previous steward's entry and the
  # registry's own are absent rather than editable.
  defp open(socket, vehicle, entry_ref, _requested_mode) do
    case Owners.entry(socket.assigns.current_scope, vehicle, entry_ref) do
      {:ok, entry} -> mount_correction(socket, vehicle, entry)
      {:error, _reason} -> turn_away(socket, vehicle, "That entry is not yours to correct.")
    end
  end

  defp mount_composer(socket, vehicle, requested_mode) do
    socket
    |> mount_shared(vehicle)
    |> assign(:page_title, "Log — #{Presenter.title(vehicle)}")
    |> assign(:entry_ref, nil)
    |> assign(:mode, mode(requested_mode))
    |> assign(:date_default, Date.utc_today())
    |> assign(:defaults, Owners.last_entry_defaults(socket.assigns.current_scope, vehicle))
    |> assign_form(%{})
  end

  defp mount_correction(socket, vehicle, entry) do
    case prefill(entry.claims) do
      {:ok, mode, params} ->
        socket
        |> mount_shared(vehicle)
        |> assign(:page_title, "Correct — #{Presenter.title(vehicle)}")
        |> assign(:entry_ref, entry.entry_ref)
        |> assign(:mode, mode)
        |> assign(:date_default, entry.date)
        # No carrying the last fill-up's odometer into a correction: the fields
        # start as the entry states them and nowhere else.
        |> assign(:defaults, %{})
        |> assign_form(params)

      :error ->
        turn_away(
          socket,
          vehicle,
          "That entry was not written here, so it is not correctable here."
        )
    end
  end

  defp mount_shared(socket, vehicle) do
    socket
    |> assign(:vehicle, vehicle)
    |> assign(:modes, @modes)
    |> assign(:error, nil)
    |> allow_upload(:photos,
      accept: ~w(.jpg .jpeg .png .heic .webp),
      max_entries: 4,
      max_file_size: 20_000_000
    )
  end

  # A full redirect, not a live one: the public record lives in another
  # live_session and cannot be reached by live navigation.
  defp turn_away(socket, vehicle, message) do
    socket
    |> put_flash(:error, message)
    |> redirect(to: ~p"/v/#{vehicle.public_id}")
  end

  @impl true
  def handle_event("mode", %{"mode" => mode}, socket) do
    {:noreply,
     socket
     |> assign(:mode, mode(mode))
     |> assign(:error, nil)
     |> assign_form(%{})}
  end

  def handle_event("validate", %{"entry" => params}, socket) do
    {:noreply, socket |> assign(:error, nil) |> assign_form(params)}
  end

  def handle_event("save", %{"entry" => params}, socket) do
    case EntryDraft.claims(socket.assigns.mode, params) do
      {:ok, claims} ->
        save_entry(socket, params, claims)

      {:error, message} ->
        if photo_only_draft?(socket, params) do
          save_entry(socket, params, [])
        else
          {:noreply, socket |> assign(:error, message) |> assign_form(params)}
        end
    end
  end

  defp save_entry(socket, params, claims) do
    vehicle = socket.assigns.vehicle
    date = params["date"] || Date.to_iso8601(socket.assigns.date_default)

    case commit(socket, %{date: date, claims: claims}, params) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> put_flash(:info, saved(socket.assigns.entry_ref))
         |> push_navigate(to: ~p"/v/#{vehicle.public_id}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, refusal(reason))
         |> assign_form(params)}
    end
  end

  defp commit(%{assigns: %{entry_ref: nil}} = socket, attrs, params) do
    attrs =
      attrs
      |> Map.put(:photos, consume_photos(socket, params))
      |> Map.put(:visibility, visibility(params["visibility"]))

    Owners.compose_entry(socket.assigns.current_scope, socket.assigns.vehicle, attrs)
  end

  # A correction carries neither photos nor a visibility flip: `amend_entry/4`
  # writes claims and nothing else, and the entry's own visibility is preserved
  # underneath. Both are absent from the form rather than present and ignored.
  defp commit(%{assigns: %{entry_ref: entry_ref}} = socket, attrs, _params) do
    Owners.amend_entry(socket.assigns.current_scope, socket.assigns.vehicle, entry_ref, attrs)
  end

  defp saved(nil), do: "Logged. It is on the car's page."
  defp saved(_entry_ref), do: "Corrected. The value it replaced is withdrawn, not gone."

  # Copied out of the upload's temp path, which is removed the moment this
  # callback returns — the registry hashes and stores the bytes itself.
  defp consume_photos(socket, params) do
    alt_text = Map.get(params, "photo_alt", %{})

    consume_uploaded_entries(socket, :photos, fn %{path: path}, entry ->
      destination = Path.join(System.tmp_dir!(), "#{Ecto.UUID.generate()}-#{entry.client_name}")
      File.cp!(path, destination)

      {:ok,
       %{
         path: destination,
         filename: entry.client_name,
         mime: entry.client_type,
         alt_text: Map.get(alt_text, entry.ref)
       }}
    end)
  end

  defp photo_only_draft?(socket, params) do
    socket.assigns.entry_ref == nil and socket.assigns.uploads.photos.entries != [] and
      Enum.all?(photo_mode_fields(socket.assigns.mode), &blank?(params[&1]))
  end

  defp photo_mode_fields(:fuel), do: ~w(volume price)
  defp photo_mode_fields(:service), do: ~w(summary performer)
  defp photo_mode_fields(:modification), do: ~w(summary area trait trait_summary)
  defp photo_mode_fields(:outing), do: ~w(summary venue result)
  defp photo_mode_fields(:plan), do: ~w(text area)
  defp photo_mode_fields(:note), do: ~w(text)

  defp blank?(nil), do: true
  defp blank?(text) when is_binary(text), do: String.trim(text) == ""
  defp blank?(_value), do: false

  ## Claims to form — the same mapping, backwards (§8 correction)

  @doc """
  Whether this entry is one the composer can restate exactly.

  The gate on the Edit control, and it is a round trip rather than a list of
  allowed predicates: the entry is read into form fields, and those fields are
  run back through the same mapping that writes an entry. If what comes out is
  not what went in — an event with no composer mode, or a fill-up carrying a
  field this form has no box for — the entry is not correctable here, because
  saving it would quietly drop whatever did not survive the trip.

  Written this way so it maintains itself: add a field to a mode and the gate
  follows, because both directions are the same two functions.
  """
  def editable?(claims), do: match?({:ok, _mode, _params}, prefill(claims))

  defp prefill(claims) do
    stated = Map.new(claims, &{&1.predicate, &1.value})

    with {:ok, mode} <- entry_mode(stated),
         params = mode_params(mode, stated),
         {:ok, restated} <- EntryDraft.claims(mode, params),
         true <- assertions(restated) == assertions(claims) do
      {:ok, mode, params}
    else
      _mismatch -> :error
    end
  end

  defp assertions(claims), do: claims |> Enum.map(&{&1.predicate, &1.value}) |> Enum.sort()

  # What happened decides the mode; the odometer rides along with all of them.
  defp entry_mode(stated) do
    Enum.find_value(@modes, :error, fn {mode, _label} ->
      Map.has_key?(stated, event_predicate(mode)) && {:ok, mode}
    end)
  end

  defp event_predicate(:fuel), do: "event.fuel"
  defp event_predicate(:service), do: "event.service"
  defp event_predicate(:modification), do: "event.modification"
  defp event_predicate(:outing), do: "event.outing"
  defp event_predicate(:plan), do: "event.plan"
  defp event_predicate(:note), do: "event.note"

  defp mode_params(:fuel, stated) do
    fuel = stated["event.fuel"]

    %{
      "volume" => fuel["volume"],
      "price" => dollars(fuel["total_cents"]),
      "odometer" => odometer(stated)
    }
  end

  defp mode_params(:service, stated) do
    service = stated["event.service"]

    %{
      "summary" => service["summary"],
      "performer" => service["performer"],
      "odometer" => odometer(stated)
    }
  end

  defp mode_params(:modification, stated) do
    modification = stated["event.modification"]
    {trait, trait_summary} = trait_fields(modification["sets"])

    %{
      "summary" => modification["summary"],
      "area" => modification["area"],
      "trait" => trait,
      "trait_summary" => trait_summary
    }
  end

  defp mode_params(:outing, stated) do
    outing = stated["event.outing"]

    %{
      "summary" => outing["summary"],
      "outing_kind" => outing["kind"],
      "venue" => outing["venue"],
      "result" => outing["result"],
      "odometer" => odometer(stated)
    }
  end

  defp mode_params(:plan, stated) do
    plan = stated["event.plan"]
    %{"text" => plan["text"], "area" => plan["area"]}
  end

  defp mode_params(:note, stated), do: %{"text" => stated["event.note"]["text"]}

  # One delta is what the form can state. A mod that sets two traits at once
  # came from somewhere else and fails the round trip, which is the honest
  # outcome — this form would save it back with one.
  defp trait_fields([%{"predicate" => predicate, "value" => %{"summary" => summary}}]),
    do: {predicate, summary}

  defp trait_fields(_absent), do: {nil, nil}

  defp odometer(stated) do
    case stated["observation.mileage"] do
      miles when is_integer(miles) -> Integer.to_string(miles)
      _absent -> ""
    end
  end

  # Back to the dollars that were typed — `optional_cents/1` run in reverse,
  # in decimal the whole way so the number that comes back is the number that
  # went in.
  defp dollars(cents) when is_integer(cents),
    do: cents |> Decimal.new() |> Decimal.div(100) |> Decimal.to_string(:normal)

  defp dollars(_absent), do: ""

  defp visibility("private"), do: :private
  defp visibility(_public), do: :public

  defp mode(mode) when mode in ~w(fuel service modification outing plan note),
    do: String.to_existing_atom(mode)

  defp mode(_unknown), do: :fuel

  # The context's refusals, in the second person. `:not_stewarded` can only mean
  # the stewardship was revoked while this page was open.
  defp refusal(:not_stewarded), do: "You no longer maintain this car's log."
  defp refusal(:empty_entry), do: "Nothing to log yet."
  defp refusal(:missing_date), do: "That date could not be read."
  defp refusal({:claim_not_live, :rejected}), do: "This was proposed before and turned down."
  defp refusal({:claim_not_live, _state}), do: "A later claim has already replaced this one."
  defp refusal(%Ecto.Changeset{}), do: "That update does not fit the record. Check the numbers."
  defp refusal(_reason), do: "That could not be saved."

  defp assign_form(socket, params) do
    defaults = socket.assigns.defaults

    params =
      params
      |> Map.put_new("date", Date.to_iso8601(socket.assigns.date_default))
      |> Map.put_new("odometer", odometer_default(defaults))
      |> Map.put_new("volume", Map.get(defaults, :volume, ""))

    assign(socket, :form, to_form(params, as: :entry))
  end

  defp odometer_default(%{odometer: odometer}) when is_integer(odometer),
    do: Integer.to_string(odometer)

  defp odometer_default(_defaults), do: ""

  ## Render

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-lg px-5 pt-10 pb-24 sm:px-8">
      <.link
        navigate={~p"/v/#{@vehicle.public_id}"}
        class="vs-eyebrow"
        style="color: var(--vs-dim)"
      >
        <span aria-hidden="true">&larr;</span> {Presenter.title(@vehicle)}
      </.link>

      <h1 class="vs-spec mt-4 text-3xl sm:text-4xl">
        {if @entry_ref, do: "Correct this update", else: "Log an update"}
      </h1>

      <nav class="mt-7 grid grid-cols-3 gap-1.5 sm:grid-cols-6" aria-label="Entry type">
        <button
          :for={{mode, label} <- @modes}
          type="button"
          phx-click="mode"
          phx-value-mode={mode}
          data-mode={mode}
          aria-current={if @mode == mode, do: "true"}
          class="vs-segment"
        >
          {label}
        </button>
      </nav>

      <.form
        for={@form}
        id="composer-form"
        phx-change="validate"
        phx-submit="save"
        class="mt-8 space-y-6"
      >
        <p :if={@error} id="composer-error" class="vs-refusal text-sm">{@error}</p>

        <.fuel_fields :if={@mode == :fuel} form={@form} />
        <.service_fields :if={@mode == :service} form={@form} />
        <.mod_fields :if={@mode == :modification} form={@form} />
        <.outing_fields :if={@mode == :outing} form={@form} />
        <.plan_fields :if={@mode == :plan} form={@form} />
        <.note_fields :if={@mode == :note} form={@form} />

        <div class="grid gap-5 sm:grid-cols-2">
          <div>
            <label for="entry_date" class="vs-eyebrow" style="color: var(--vs-dim)">Date</label>
            <input
              type="date"
              id="entry_date"
              name="entry[date]"
              value={@form[:date].value}
              class="vs-field mt-2"
            />
          </div>

          <div :if={is_nil(@entry_ref)}>
            <span class="vs-eyebrow" style="color: var(--vs-dim)">Photos</span>
            <div class="mt-2">
              <.live_file_input upload={@uploads.photos} class="vs-file" />
            </div>
            <div
              :for={entry <- @uploads.photos.entries}
              id={"composer-photo-#{entry.ref}"}
              class="composer-photo-preview"
            >
              <.live_img_preview entry={entry} />
              <div>
                <p class="vs-code text-xs" style="color: var(--vs-dim)">
                  {entry.client_name}
                </p>
                <label for={"entry_photo_alt_#{entry.ref}"} class="vs-eyebrow">
                  Alt text <span class="normal-case tracking-normal">(recommended)</span>
                </label>
                <input
                  type="text"
                  id={"entry_photo_alt_#{entry.ref}"}
                  name={"entry[photo_alt][#{entry.ref}]"}
                  value={photo_alt_value(@form, entry.ref)}
                  maxlength="240"
                  class="vs-field"
                  placeholder="The car in the Summit Point paddock at dusk"
                />
                <p :for={error <- upload_errors(@uploads.photos, entry)} class="vs-refusal text-xs">
                  {upload_error(error)}
                </p>
              </div>
            </div>
            <p
              :for={error <- upload_errors(@uploads.photos)}
              class="vs-refusal mt-1 text-xs"
            >
              {upload_error(error)}
            </p>
          </div>
        </div>

        <label
          :if={is_nil(@entry_ref)}
          class="flex items-start gap-3 text-sm"
          style="color: var(--vs-dim)"
        >
          <input type="hidden" name="entry[visibility]" value="public" />
          <input
            type="checkbox"
            id="entry_visibility"
            name="entry[visibility]"
            value="private"
            checked={@form[:visibility].value == "private"}
            class="vs-check mt-0.5"
          />
          <span>
            Keep this update off the public page.
            <span class="block text-xs">
              It stays in your own history and in any export you share.
            </span>
          </span>
        </label>

        <button type="submit" id="composer-save" class="vs-commit w-full">
          {if @entry_ref, do: "Save the correction", else: "Log the update"}
        </button>
      </.form>

      <p class="mt-8 text-xs leading-relaxed" style="color: var(--vs-dim)">
        Nothing here is overwritten. Correcting an update writes a new claim and
        withdraws the one it replaces — the withdrawn value stays in the ledger under
        your handle, off the page.
      </p>
    </div>
    """
  end

  attr :form, :map, required: true

  defp fuel_fields(assigns) do
    ~H"""
    <div class="space-y-5">
      <div>
        <label for="entry_odometer" class="vs-eyebrow" style="color: var(--vs-dim)">Odometer</label>
        <input
          type="text"
          inputmode="numeric"
          id="entry_odometer"
          name="entry[odometer]"
          value={@form[:odometer].value}
          autocomplete="off"
          class="vs-field vs-figure mt-2 text-2xl"
        />
      </div>

      <div class="grid grid-cols-2 gap-4">
        <div>
          <label for="entry_volume" class="vs-eyebrow" style="color: var(--vs-dim)">Gallons</label>
          <input
            type="text"
            inputmode="decimal"
            id="entry_volume"
            name="entry[volume]"
            value={@form[:volume].value}
            autocomplete="off"
            class="vs-field vs-figure mt-2 text-2xl"
          />
        </div>

        <div>
          <label for="entry_price" class="vs-eyebrow" style="color: var(--vs-dim)">Total</label>
          <input
            type="text"
            inputmode="decimal"
            id="entry_price"
            name="entry[price]"
            value={@form[:price].value}
            autocomplete="off"
            class="vs-field vs-figure mt-2 text-2xl"
          />
        </div>
      </div>
    </div>
    """
  end

  attr :form, :map, required: true

  defp service_fields(assigns) do
    ~H"""
    <div class="space-y-5">
      <div>
        <label for="entry_summary" class="vs-eyebrow" style="color: var(--vs-dim)">
          What was done
        </label>
        <textarea
          id="entry_summary"
          name="entry[summary]"
          rows="3"
          class="vs-field mt-2"
          placeholder="Oil and filter, checked the plugs"
        >{@form[:summary].value}</textarea>
        <p class="mt-1.5 text-xs" style="color: var(--vs-dim)">
          Snap the invoice and write five words — nobody should retype what the receipt says.
        </p>
      </div>

      <div class="grid gap-4 sm:grid-cols-2">
        <div>
          <label for="entry_performer" class="vs-eyebrow" style="color: var(--vs-dim)">
            Who did it
          </label>
          <input
            type="text"
            id="entry_performer"
            name="entry[performer]"
            value={@form[:performer].value}
            class="vs-field mt-2"
          />
        </div>

        <div>
          <label for="entry_odometer" class="vs-eyebrow" style="color: var(--vs-dim)">Odometer</label>
          <input
            type="text"
            inputmode="numeric"
            id="entry_odometer"
            name="entry[odometer]"
            value={@form[:odometer].value}
            autocomplete="off"
            class="vs-field vs-figure mt-2"
          />
        </div>
      </div>
    </div>
    """
  end

  attr :form, :map, required: true

  defp mod_fields(assigns) do
    assigns = assign(assigns, :traits, SantoApi.Registry.Vocabulary.trait_predicates())

    ~H"""
    <div class="space-y-5">
      <div>
        <label for="entry_summary" class="vs-eyebrow" style="color: var(--vs-dim)">
          What changed
        </label>
        <textarea
          id="entry_summary"
          name="entry[summary]"
          rows="3"
          class="vs-field mt-2"
          placeholder="Changed the camber to 2.5 degrees"
        >{@form[:summary].value}</textarea>
      </div>

      <div>
        <label for="entry_area" class="vs-eyebrow" style="color: var(--vs-dim)">Area</label>
        <input
          type="text"
          id="entry_area"
          name="entry[area]"
          value={@form[:area].value}
          class="vs-field mt-2"
          placeholder="suspension"
        />
      </div>

      <fieldset class="vs-inset">
        <legend class="vs-eyebrow px-1" style="color: var(--vs-dim)">
          And the car is now
        </legend>

        <p class="mt-1 text-xs" style="color: var(--vs-dim)">
          Optional. Filling this in moves the spec on the car's page — the mod stays in
          the log either way.
        </p>

        <div class="mt-3 space-y-3">
          <select id="entry_trait" name="entry[trait]" class="vs-field">
            <option value="">Nothing else changed</option>
            <option
              :for={trait <- @traits}
              value={trait}
              selected={@form[:trait].value == trait}
            >
              {Presenter.trait_label(trait)}
            </option>
          </select>

          <input
            type="text"
            id="entry_trait_summary"
            name="entry[trait_summary]"
            value={@form[:trait_summary].value}
            class="vs-field"
            placeholder="3 degrees front camber, 32 psi"
          />
        </div>
      </fieldset>
    </div>
    """
  end

  attr :form, :map, required: true

  defp outing_fields(assigns) do
    ~H"""
    <div class="space-y-5">
      <div>
        <label for="entry_summary" class="vs-eyebrow" style="color: var(--vs-dim)">
          Where did you go?
        </label>
        <textarea
          id="entry_summary"
          name="entry[summary]"
          rows="3"
          class="vs-field mt-2"
          placeholder="Dawn run up Angeles Crest; empty roads and the car felt perfect"
        >{@form[:summary].value}</textarea>
      </div>

      <div class="grid gap-4 sm:grid-cols-2">
        <div>
          <label for="entry_outing_kind" class="vs-eyebrow" style="color: var(--vs-dim)">
            Kind of day
          </label>
          <select id="entry_outing_kind" name="entry[outing_kind]" class="vs-field mt-2">
            <option value="drive" selected={@form[:outing_kind].value in [nil, "", "drive"]}>
              Drive
            </option>
            <option value="track" selected={@form[:outing_kind].value == "track"}>Track</option>
            <option value="autocross" selected={@form[:outing_kind].value == "autocross"}>
              Autocross
            </option>
            <option value="show" selected={@form[:outing_kind].value == "show"}>Show</option>
            <option value="other" selected={@form[:outing_kind].value == "other"}>Other</option>
          </select>
        </div>

        <div>
          <label for="entry_venue" class="vs-eyebrow" style="color: var(--vs-dim)">Place</label>
          <input
            type="text"
            id="entry_venue"
            name="entry[venue]"
            value={@form[:venue].value}
            class="vs-field mt-2"
            placeholder="Lime Rock Park"
          />
        </div>
      </div>

      <div class="grid gap-4 sm:grid-cols-2">
        <div>
          <label for="entry_result" class="vs-eyebrow" style="color: var(--vs-dim)">Result</label>
          <input
            type="text"
            id="entry_result"
            name="entry[result]"
            value={@form[:result].value}
            class="vs-field mt-2"
            placeholder="Best lap 1:03.2"
          />
        </div>
        <div>
          <label for="entry_odometer" class="vs-eyebrow" style="color: var(--vs-dim)">Odometer</label>
          <input
            type="text"
            inputmode="numeric"
            id="entry_odometer"
            name="entry[odometer]"
            value={@form[:odometer].value}
            class="vs-field mt-2"
          />
        </div>
      </div>
    </div>
    """
  end

  attr :form, :map, required: true

  defp plan_fields(assigns) do
    ~H"""
    <div class="space-y-5">
      <div>
        <label for="entry_text" class="vs-eyebrow" style="color: var(--vs-dim)">
          What are you considering?
        </label>
        <textarea
          id="entry_text"
          name="entry[text]"
          rows="5"
          class="vs-field mt-2"
          placeholder="I’m looking at a lighter set of wheels for next season."
        >{@form[:text].value}</textarea>
      </div>

      <div>
        <label for="entry_area" class="vs-eyebrow" style="color: var(--vs-dim)">
          Part of the car <span class="normal-case tracking-normal">(optional)</span>
        </label>
        <input
          type="text"
          id="entry_area"
          name="entry[area]"
          value={@form[:area].value}
          class="vs-field mt-2"
          placeholder="Wheels & tires"
        />
      </div>

      <p class="text-xs leading-relaxed" style="color: var(--vs-dim)">
        A plan records what you were thinking on this date. It does not change the car’s
        current setup; log a modification if the work happens.
      </p>
    </div>
    """
  end

  attr :form, :map, required: true

  defp note_fields(assigns) do
    ~H"""
    <div>
      <label for="entry_text" class="vs-eyebrow" style="color: var(--vs-dim)">Note</label>
      <textarea
        id="entry_text"
        name="entry[text]"
        rows="5"
        class="vs-field mt-2"
        placeholder="Anything. Nothing here is rejected for not fitting a form."
      >{@form[:text].value}</textarea>
    </div>
    """
  end

  defp upload_error(:too_large), do: "That photo is too large."
  defp upload_error(:too_many_files), do: "Four photos to an entry."
  defp upload_error(:not_accepted), do: "Photos only."
  defp upload_error(_error), do: "That photo could not be read."

  defp photo_alt_value(form, ref) do
    case form[:photo_alt].value do
      value when is_map(value) -> Map.get(value, ref, "")
      _absent -> ""
    end
  end
end
