defmodule SantoApiWeb.OwnerLive.Composer do
  @moduledoc """
  The entry composer (owner_surface §1) — the make-or-break surface.

  Phone-first, because the entry moment is standing at the pump or in the garage
  with greasy hands. Four modes: **Fill-up | Service | Mod | Note**. Fill-up opens
  selected with the odometer already carried forward from the last reading, so a
  fill-up is three numbers and a save — the Fuelly bar, which v1 has to clear.

  Nothing here decides truth. This module translates a form into vocabulary
  claims and hands them to `SantoApi.Owners.compose_entry/3`, which owns the
  transaction, the `entry_ref`, and the scope split. What a "Fill-up" *means* —
  which predicates it produces — is the composer's business and lives here; the
  agent surface (§8) takes typed claims directly and never sees this mapping.

  No LLM in the loop, deliberately. Fuel and mileage are arithmetic and a
  structured form beats a sentence; mods and notes are narrative and the text is
  the value. Voice and free-text structuring arrive through the owner's own
  assistant over MCP (§8), not through a parser of ours.
  """

  use SantoApiWeb, :live_view

  alias SantoApi.Owners
  alias SantoApi.Registry
  alias SantoApiWeb.VehicleLive.Presenter

  @modes [
    {:fuel, "Fill-up"},
    {:service, "Service"},
    {:modification, "Mod"},
    {:note, "Note"}
  ]

  @impl true
  def mount(%{"public_id" => public_id}, _session, socket) do
    # Signing in is the router's job; stewarding *this* car is ours. A signed-in
    # stranger is sent back to the public record rather than shown an error page —
    # they are allowed to read this car, just not to write to it.
    case Registry.fetch_by_public_id(public_id) do
      {:ok, vehicle} ->
        if Owners.stewarding?(socket.assigns.current_scope, vehicle),
          do: {:ok, mount_composer(socket, vehicle)},
          else: {:ok, turn_away(socket, vehicle)}

      {:error, :not_found} ->
        raise SantoApiWeb.VehicleNotFound
    end
  end

  defp mount_composer(socket, vehicle) do
    socket
    |> assign(:page_title, "Log — #{Presenter.title(vehicle)}")
    |> assign(:vehicle, vehicle)
    |> assign(:modes, @modes)
    |> assign(:mode, :fuel)
    |> assign(:error, nil)
    |> assign(:defaults, Owners.last_entry_defaults(socket.assigns.current_scope, vehicle))
    |> assign_form(%{})
    |> allow_upload(:photos,
      accept: ~w(.jpg .jpeg .png .heic .webp),
      max_entries: 4,
      max_file_size: 20_000_000
    )
  end

  # A full redirect, not a live one: the public record lives in another
  # live_session and cannot be reached by live navigation.
  defp turn_away(socket, vehicle) do
    socket
    |> put_flash(:error, "You do not maintain this car's log.")
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
    case claims(socket.assigns.mode, params) do
      {:ok, claims} -> save_entry(socket, params, claims)
      {:error, message} -> {:noreply, socket |> assign(:error, message) |> assign_form(params)}
    end
  end

  defp save_entry(socket, params, claims) do
    vehicle = socket.assigns.vehicle

    attrs = %{
      date: params["date"] || Date.to_iso8601(Date.utc_today()),
      claims: claims,
      photos: consume_photos(socket),
      visibility: visibility(params["visibility"])
    }

    case Owners.compose_entry(socket.assigns.current_scope, vehicle, attrs) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> put_flash(:info, "Logged. It is on the car's page.")
         |> push_navigate(to: ~p"/v/#{vehicle.public_id}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, refusal(reason))
         |> assign_form(params)}
    end
  end

  # Copied out of the upload's temp path, which is removed the moment this
  # callback returns — the registry hashes and stores the bytes itself.
  defp consume_photos(socket) do
    consume_uploaded_entries(socket, :photos, fn %{path: path}, entry ->
      destination = Path.join(System.tmp_dir!(), "#{Ecto.UUID.generate()}-#{entry.client_name}")
      File.cp!(path, destination)
      {:ok, %{path: destination, filename: entry.client_name, mime: entry.client_type}}
    end)
  end

  ## Form to claims — what each mode means in the vocabulary (§1, §2)

  defp claims(:fuel, params) do
    with {:ok, volume} <-
           required_decimal(params["volume"], "A fill-up needs to know how much fuel went in."),
         {:ok, cents} <- optional_cents(params["price"]),
         {:ok, odometer} <-
           optional_integer(params["odometer"], "That odometer reading is not a number.") do
      fuel =
        %{"volume" => volume, "unit" => "gal"}
        |> put_unless_nil("total_cents", cents)
        |> put_unless_nil("currency", cents && "USD")

      {:ok, [%{predicate: "event.fuel", value: fuel}] ++ mileage(odometer)}
    end
  end

  defp claims(:service, params) do
    with {:ok, summary} <- required_text(params["summary"], "Say what was done."),
         {:ok, odometer} <-
           optional_integer(params["odometer"], "That odometer reading is not a number.") do
      service = %{"summary" => summary, "performer" => trimmed(params["performer"])}

      {:ok, [%{predicate: "event.service", value: service}] ++ mileage(odometer)}
    end
  end

  defp claims(:modification, params) do
    with {:ok, summary} <- required_text(params["summary"], "Say what changed."),
         {:ok, sets} <- trait_delta(params) do
      modification =
        %{"summary" => summary}
        |> put_unless_nil("area", trimmed(params["area"]))
        |> put_unless_nil("sets", sets)

      {:ok, [%{predicate: "event.modification", value: modification}]}
    end
  end

  defp claims(:note, params) do
    with {:ok, text} <- required_text(params["text"], "Nothing to log yet — say something first.") do
      {:ok, [%{predicate: "event.note", value: %{"text" => text}}]}
    end
  end

  # A mod may state what the car is *now* as well as what was done to it — the
  # §2b delta. Without one the entry is timeline-only, which is a fine thing for
  # a mod to be.
  defp trait_delta(params) do
    case {trimmed(params["trait"]), trimmed(params["trait_summary"])} do
      {nil, _summary} ->
        {:ok, nil}

      {trait, nil} when is_binary(trait) ->
        {:error, "Say what the #{Presenter.trait_label(trait) |> String.downcase()} is now."}

      {trait, summary} ->
        {:ok, [%{"predicate" => trait, "value" => %{"summary" => summary}}]}
    end
  end

  defp mileage(nil), do: []
  defp mileage(odometer), do: [%{predicate: "observation.mileage", value: odometer}]

  defp required_text(value, message) do
    case trimmed(value) do
      nil -> {:error, message}
      text -> {:ok, text}
    end
  end

  # Volume stays a decimal *string* all the way into the claim: the vocabulary
  # takes it that way so no float ever touches a measurement.
  defp required_decimal(value, message) do
    case trimmed(value) do
      nil ->
        {:error, message}

      text ->
        case Decimal.parse(text) do
          {decimal, ""} ->
            if Decimal.negative?(decimal),
              do: {:error, "A volume cannot be negative."},
              else: {:ok, Decimal.to_string(decimal, :normal)}

          _unparseable ->
            {:error, "That volume is not a number."}
        end
    end
  end

  # Dollars in, integer cents stored. The arithmetic stays exact — a float here
  # would make cost-per-mile wrong in the third decimal place forever.
  defp optional_cents(value) do
    case trimmed(value) do
      nil ->
        {:ok, nil}

      text ->
        case Decimal.parse(String.trim_leading(text, "$")) do
          {decimal, ""} ->
            if Decimal.negative?(decimal),
              do: {:error, "A price cannot be negative."},
              else:
                {:ok, decimal |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer()}

          _unparseable ->
            {:error, "That price is not a number."}
        end
    end
  end

  defp optional_integer(value, message) do
    case trimmed(value) do
      nil ->
        {:ok, nil}

      text ->
        case Integer.parse(String.replace(text, ",", "")) do
          {integer, ""} when integer >= 0 -> {:ok, integer}
          _unparseable -> {:error, message}
        end
    end
  end

  defp trimmed(nil), do: nil

  defp trimmed(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp put_unless_nil(map, _key, nil), do: map
  defp put_unless_nil(map, key, value), do: Map.put(map, key, value)

  defp visibility("private"), do: :private
  defp visibility(_public), do: :public

  defp mode(mode) when mode in ~w(fuel service modification note),
    do: String.to_existing_atom(mode)

  defp mode(_unknown), do: :fuel

  # The context's refusals, in the second person. `:not_stewarded` can only mean
  # the stewardship was revoked while this page was open.
  defp refusal(:not_stewarded), do: "You no longer maintain this car's log."
  defp refusal(:empty_entry), do: "Nothing to log yet."
  defp refusal(:missing_date), do: "That date could not be read."
  defp refusal({:claim_not_live, :rejected}), do: "This was proposed before and turned down."
  defp refusal({:claim_not_live, _state}), do: "A later claim has already replaced this one."
  defp refusal(%Ecto.Changeset{}), do: "That entry does not fit the record. Check the numbers."
  defp refusal(_reason), do: "That could not be saved."

  defp assign_form(socket, params) do
    defaults = socket.assigns.defaults

    params =
      params
      |> Map.put_new("date", Date.to_iso8601(Date.utc_today()))
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

      <h1 class="vs-spec mt-4 text-3xl sm:text-4xl">Log an entry</h1>

      <nav class="mt-7 grid grid-cols-4 gap-1.5" aria-label="Entry type">
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

          <div>
            <span class="vs-eyebrow" style="color: var(--vs-dim)">Photos</span>
            <div class="mt-2">
              <.live_file_input upload={@uploads.photos} class="vs-file" />
            </div>
            <p
              :for={entry <- @uploads.photos.entries}
              class="vs-code mt-1 text-xs"
              style="color: var(--vs-dim)"
            >
              {entry.client_name}
            </p>
            <p
              :for={error <- upload_errors(@uploads.photos)}
              class="vs-refusal mt-1 text-xs"
            >
              {upload_error(error)}
            </p>
          </div>
        </div>

        <label class="flex items-start gap-3 text-sm" style="color: var(--vs-dim)">
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
            Keep this entry off the public page.
            <span class="block text-xs">
              It stays in the record and in your own view, and in any dossier you share.
            </span>
          </span>
        </label>

        <button type="submit" id="composer-save" class="vs-commit w-full">Log it</button>
      </.form>

      <p class="mt-8 text-xs leading-relaxed" style="color: var(--vs-dim)">
        Entries are added, never edited. A correction is a new entry, and both stay
        on the record under your handle.
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
end
