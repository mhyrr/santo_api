defmodule SantoApiWeb.OriginationLive do
  @moduledoc """
  The front door (owner_surface §7b.3): one box, VIN or sentence, and the
  identity kind is an outcome rather than a question.

  A VIN — pasted bare or embedded in a sentence — persists immediately and
  lands on the car's page, exactly as §7 always said. A sentence runs
  through extraction into the read-back, then registration, and one submit
  creates everything (`SantoApi.Origination.originate/2`). Nothing persists
  on the sentence path until there is an account behind it.

  The flow's later screens render here rather than on `/v/:public_id`
  because the owner has no session yet — the magic-link click is their
  first login, and it publishes the page (§7b.1 decision 6). The minute-one
  panel is the same data the page will show, read from the rows the submit
  just created.

  Extraction failure is not an error state: the read-back renders with
  empty lines the owner fills by hand, and their lines carry `method:
  :human` where the extractor's carry `:llm_extract`.
  """
  use SantoApiWeb, :live_view

  alias SantoApi.Accounts
  alias SantoApi.Accounts.Scope
  alias SantoApi.AcquisitionRuns
  alias SantoApi.Extraction
  alias SantoApi.Origination
  alias SantoApi.Owners.Links
  alias SantoApi.RateLimit
  alias SantoApiWeb.VehicleLive.Presenter

  @impl true
  def mount(_params, _session, socket) do
    if match?(%Scope{user: %Accounts.User{}}, socket.assigns.current_scope) do
      # Origination registers an account, so a signed-in owner has no
      # business here — their add-a-car door is a later ticket.
      {:ok, socket |> put_flash(:error, "You already have an account.") |> redirect(to: ~p"/")}
    else
      {:ok,
       socket
       |> assign(:page_title, "Add your car")
       |> assign(:throttle_key, throttle_key(socket))
       |> assign(:step, :box)
       |> assign(:sentence, nil)
       |> assign(:reading, empty_reading())
       |> assign(:extracted?, false)
       |> assign(:error, nil)
       |> assign(:form, registration_form(%{}))
       |> assign(:created, nil)
       |> assign(:links, [])}
    end
  end

  ## The box (screen 1)

  @impl true
  def handle_event("lookup", %{"origination" => %{"q" => q}}, socket) do
    input = String.trim(q)

    cond do
      input == "" ->
        {:noreply, assign(socket, :error, "Say something about the car — or paste its VIN.")}

      throttled?(socket) ->
        {:noreply, assign(socket, :error, "Too many tries — give it a few minutes.")}

      vin?(input) ->
        vin_path(socket, input)

      true ->
        sentence_path(socket, input)
    end
  end

  ## The read-back (screen 2)

  def handle_event("confirm_reading", %{"reading" => fields}, socket) do
    {:noreply,
     socket
     |> assign(:reading, Map.take(fields, ~w(year marque model color mileage)))
     |> assign(:step, :register)
     |> assign(:error, nil)}
  end

  ## Registration (screen 3)

  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      Accounts.change_user_registration(%Accounts.User{}, params, validate_unique: false)

    {:noreply, assign(socket, :form, to_form(Map.put(changeset, :action, :validate), as: "user"))}
  end

  def handle_event("originate", %{"user" => params}, socket) do
    reading = typed_reading(socket.assigns.reading)

    attrs = %{
      email: params["email"],
      handle: params["handle"],
      sentence: socket.assigns.sentence,
      claims: Extraction.claims(reading),
      method: if(socket.assigns.extracted?, do: :llm_extract, else: :human)
    }

    case Origination.originate(attrs, &url(~p"/users/log-in/#{&1}")) do
      {:ok, created} ->
        {:noreply,
         socket
         |> assign(:created, created)
         |> assign(:step, :minute_one)
         |> assign(:error, nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "user"))}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "That could not be done. Try again.")}
    end
  end

  ## Links (screen 5) — written with the account the flow just created; the
  ## owner has no session until the magic-link click.

  def handle_event("add_link", %{"link" => params}, socket) do
    %{user: user, vehicle: vehicle} = socket.assigns.created

    case Links.add_link(Scope.for_user(user), vehicle, params) do
      {:ok, _link} ->
        {:noreply, assign(socket, :links, Links.list_links(vehicle))}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "A link needs a full http(s) address.")}
    end
  end

  defp vin?(input), do: match?({:ok, {:vin, _vin}}, Santo.Identity.key(input))

  # The §7 path: a VIN persists immediately — its decoded facts are real and
  # exist independent of who typed them (§7b.1 decision 5).
  defp vin_path(socket, vin) do
    case AcquisitionRuns.start(socket.assigns.current_scope, vin) do
      {:ok, _disposition, vehicle, _run} ->
        {:noreply, push_navigate(socket, to: ~p"/v/#{vehicle.public_id}")}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "That VIN could not be looked up.")}
    end
  end

  defp sentence_path(socket, sentence) do
    case Extraction.extract(sentence) do
      # An embedded VIN is still the VIN path — nobody has to know which
      # door they walked through (§7b.1 decision 3).
      {:ok, %{vin: vin}} when is_binary(vin) ->
        if vin?(vin), do: vin_path(socket, vin), else: read_back(socket, sentence, nil)

      {:ok, reading} ->
        read_back(socket, sentence, reading)

      # Parse failure renders the same screen with empty lines — no separate
      # error state, no dead end (§7b.1 decision 4).
      {:error, _reason} ->
        read_back(socket, sentence, nil)
    end
  end

  defp read_back(socket, sentence, reading) do
    fields =
      case reading do
        nil ->
          empty_reading()

        reading ->
          %{
            "year" => reading.year && Integer.to_string(reading.year),
            "marque" => reading.marque,
            "model" => reading.model,
            "color" => reading.color,
            "mileage" => reading.mileage && Integer.to_string(reading.mileage)
          }
      end

    {:noreply,
     socket
     |> assign(:sentence, sentence)
     |> assign(:reading, fields)
     |> assign(:extracted?, reading != nil)
     |> assign(:step, :read_back)
     |> assign(:error, nil)}
  end

  defp empty_reading do
    %{"year" => nil, "marque" => nil, "model" => nil, "color" => nil, "mileage" => nil}
  end

  defp typed_reading(fields) do
    %{
      vin: nil,
      year: parse_int(fields["year"]),
      marque: presence(fields["marque"]),
      model: presence(fields["model"]),
      color: presence(fields["color"]),
      mileage: parse_int(fields["mileage"])
    }
  end

  defp parse_int(nil), do: nil

  defp parse_int(value) when is_binary(value) do
    case value |> String.replace(~r/[,\s]/, "") |> Integer.parse() do
      {int, ""} -> int
      _other -> nil
    end
  end

  defp presence(nil), do: nil

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  # Origination is a second door that mints vehicle rows and spends an LLM
  # call per try (§7b.5) — bounded per address, same shape as §7's lookup
  # limit. Checked in the submit handler because the expensive act never
  # crosses the router; the key is read at mount, the only place connect
  # info exists.
  defp throttled?(socket) do
    {limit, window} = RateLimit.limits(:origination)
    match?({:deny, _retry}, RateLimit.check(socket.assigns.throttle_key, limit, window))
  end

  defp throttle_key(socket) do
    case connected?(socket) && get_connect_info(socket, :peer_data) do
      %{address: address} -> "origination:ip:#{:inet.ntoa(address)}"
      _unknown -> "origination:ip:unknown"
    end
  end

  defp registration_form(params) do
    to_form(
      Accounts.change_user_registration(%Accounts.User{}, params, validate_unique: false),
      as: "user"
    )
  end

  ## Rendering — the vs-* register: an originated car has earned no amber and
  ## no oxblood, so the flow is almost entirely unlit (§7b.3).

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl px-5 py-16 sm:px-8 sm:py-24">
      <.box :if={@step == :box} error={@error} />
      <.read_back_screen
        :if={@step == :read_back}
        sentence={@sentence}
        reading={@reading}
        error={@error}
      />
      <.register_screen :if={@step == :register} sentence={@sentence} form={@form} error={@error} />
      <.minute_one :if={@step == :minute_one} created={@created} links={@links} error={@error} />
    </div>
    """
  end

  attr :error, :string, default: nil

  defp box(assigns) do
    ~H"""
    <header>
      <p class="vs-eyebrow" style="color: var(--vs-dim)">Vin Santo</p>
      <h1 class="vs-spec mt-4 text-4xl sm:text-5xl">Add your car</h1>
      <p class="mt-4 max-w-xl text-base leading-relaxed" style="color: var(--vs-dim)">
        Paste the VIN if you have it. If you don't, just say what it is — the
        record starts from your words and the VIN can come later.
      </p>
    </header>

    <form id="origination-form" phx-submit="lookup" class="mt-10">
      <input
        type="text"
        id="origination_q"
        name="origination[q]"
        placeholder="2024 Lexus GX 550, green, 35,000 miles — or a 17-character VIN"
        autocomplete="off"
        spellcheck="false"
        class="w-full rounded border bg-transparent px-4 py-3 text-base"
        style="border-color: var(--vs-hairline)"
        phx-mounted={JS.focus()}
      />
      <p :if={@error} id="origination-error" class="mt-2 text-sm" style="color: var(--vs-needle)">
        {@error}
      </p>
      <button type="submit" class="vs-commit mt-4">Start the record</button>
    </form>
    """
  end

  attr :sentence, :string, required: true
  attr :reading, :map, required: true
  attr :error, :string, default: nil

  # The sentence stays on screen because it is about to become the artifact
  # (§7b.3 screen 2). Every line is editable in place.
  defp read_back_screen(assigns) do
    ~H"""
    <header>
      <p class="vs-eyebrow" style="color: var(--vs-dim)">We read</p>
      <p class="vs-code mt-4 text-base" style="color: var(--vs-dial)">{@sentence}</p>
      <p class="mt-4 max-w-xl text-sm leading-relaxed" style="color: var(--vs-dim)">
        Here's what we took from that. Fix anything we misread — an empty line
        just stays off the record until you fill it in.
      </p>
    </header>

    <form id="read-back-form" phx-submit="confirm_reading" class="mt-8 space-y-4">
      <.line name="year" label="Year" value={@reading["year"]} />
      <.line name="marque" label="Marque" value={@reading["marque"]} />
      <.line name="model" label="Model" value={@reading["model"]} />
      <.line name="color" label="Colour" value={@reading["color"]} />
      <.line name="mileage" label="Odometer (miles)" value={@reading["mileage"]} />

      <p :if={@error} class="text-sm" style="color: var(--vs-needle)">{@error}</p>
      <button type="submit" class="vs-commit mt-2">That's the car</button>
    </form>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, default: nil

  defp line(assigns) do
    ~H"""
    <div class="grid gap-1 sm:grid-cols-[11rem_1fr] sm:gap-6">
      <label for={"reading_#{@name}"} class="vs-eyebrow pt-2" style="color: var(--vs-dim)">
        {@label}
      </label>
      <input
        type="text"
        id={"reading_#{@name}"}
        name={"reading[#{@name}]"}
        value={@value}
        autocomplete="off"
        class="rounded border bg-transparent px-3 py-2 text-base"
        style="border-color: var(--vs-hairline)"
      />
    </div>
    """
  end

  attr :sentence, :string, required: true
  attr :form, :map, required: true
  attr :error, :string, default: nil

  defp register_screen(assigns) do
    ~H"""
    <header>
      <p class="vs-eyebrow" style="color: var(--vs-dim)">Nearly there</p>
      <h1 class="vs-spec mt-4 text-3xl sm:text-4xl">Who keeps this record?</h1>
      <p class="mt-4 max-w-xl text-sm leading-relaxed" style="color: var(--vs-dim)">
        An email for the magic link, and the handle your entries are signed with.
      </p>
    </header>

    <.form for={@form} id="origination-registration" phx-submit="originate" phx-change="validate">
      <div class="mt-8 max-w-sm space-y-4">
        <.input
          field={@form[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          spellcheck="false"
          required
        />
        <.input
          field={@form[:handle]}
          type="text"
          label="Handle"
          autocomplete="off"
          spellcheck="false"
          required
        />
        <!-- Permanence stated where the question is asked (§7b.1 decision 7). -->
        <p class="text-sm" style="color: var(--vs-dim)">
          Public and permanent — entries you record are signed with it, and it
          cannot be changed later.
        </p>

        <p :if={@error} class="text-sm" style="color: var(--vs-needle)">{@error}</p>
        <button type="submit" class="vs-commit" phx-disable-with="Starting the record…">
          Start the record
        </button>
      </div>
    </.form>
    """
  end

  attr :created, :map, required: true
  attr :links, :list, required: true
  attr :error, :string, default: nil

  # The page, minute one (§7b.3 screen 4), then links as the last onboarding
  # step (screen 5). Amber appears exactly once in this flow: on the owner's
  # own opening tick.
  defp minute_one(assigns) do
    assigns =
      assigns
      |> assign(:vehicle, assigns.created.vehicle)
      |> assign(:party, assigns.created.party)
      |> assign(:odometer, Presenter.odometer(assigns.created.vehicle))

    ~H"""
    <header id="minute-one">
      <p class="vs-eyebrow" style="color: var(--vs-dim)">Your record</p>
      <h1 class="vs-spec mt-4 text-4xl sm:text-5xl">{Presenter.title(@vehicle)}</h1>

      <p
        :if={Presenter.spec_line(@vehicle) != []}
        class="mt-4 text-lg"
        style="color: var(--vs-dial)"
      >
        {Enum.join(Presenter.spec_line(@vehicle), " · ")}
      </p>

      <dl :if={@odometer} class="mt-8">
        <dt class="vs-eyebrow" style="color: var(--vs-dim)">Odometer</dt>
        <dd class="vs-figure mt-1 text-3xl font-semibold">
          {Presenter.delimit(@odometer.miles)}
          <span class="text-base font-normal" style="color: var(--vs-dim)">mi</span>
        </dd>
      </dl>

      <ol class="vs-spine mt-10 pl-6">
        <li class="vs-tick relative" data-owner="true">
          <p class="vs-code text-xs" style="color: var(--vs-dim)">
            {Presenter.on_date(Date.utc_today())}
          </p>
          <h3 class="mt-1.5 text-lg leading-snug">Started this record</h3>
          <p class="mt-2 text-xs" style="color: var(--vs-dim)">Recorded by {@party.name}</p>
        </li>
      </ol>

      <p id="publish-banner" class="mt-10 max-w-xl text-base leading-relaxed">
        Your page is live — confirm your email to make it public. The link is in
        your inbox.
      </p>
      <p class="vs-code mt-2 text-sm" style="color: var(--vs-dim)">
        {url(~p"/v/#{@vehicle.public_id}")}
      </p>
    </header>

    <section id="onboarding-links" class="mt-14">
      <h2 class="vs-eyebrow pb-4" style="color: var(--vs-dim)">
        Where does this car already live?
      </h2>
      <p class="max-w-xl text-sm leading-relaxed" style="color: var(--vs-dim)">
        A build thread, a YouTube channel, an Instagram — link them and the page
        points back. Skippable; the record works without an audience.
      </p>

      <ul :if={@links != []} class="mt-4 space-y-1">
        <li :for={link <- @links} class="text-sm">{link.label || link.url}</li>
      </ul>

      <form id="onboarding-link-form" phx-submit="add_link" class="mt-4">
        <div class="flex flex-wrap items-center gap-3">
          <input
            type="url"
            name="link[url]"
            placeholder="https://…"
            class="w-72 rounded border bg-transparent px-3 py-2 text-sm"
            style="border-color: var(--vs-hairline)"
          />
          <input
            type="text"
            name="link[label]"
            placeholder="Label (optional)"
            class="w-48 rounded border bg-transparent px-3 py-2 text-sm"
            style="border-color: var(--vs-hairline)"
          />
          <button type="submit" class="vs-quiet">Add</button>
        </div>
        <p :if={@error} class="mt-2 text-sm" style="color: var(--vs-needle)">{@error}</p>
      </form>
    </section>
    """
  end
end
