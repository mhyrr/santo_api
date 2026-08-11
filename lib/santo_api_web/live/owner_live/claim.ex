defmodule SantoApiWeb.OwnerLive.Claim do
  @moduledoc """
  Claiming a car, from the claimant's side (owner_surface §4).

  Three screens in one: choose a handle and get a code, photograph the VIN plate
  with that code in frame, then wait for a person to look at it. The page never
  promises more than the state of the claim supports — nothing here is approved
  until an operator says so, and the copy says that rather than implying it.

  What claiming unlocks is bounded, and the page says that too: the log, under
  the claimant's own attributed handle. Not the factory record, not identity,
  not ownership. Possession proves access to a car, and this flow proves
  possession — the ownership chain is layer 5's problem, with layer 5's
  evidence.
  """

  use SantoApiWeb, :live_view

  alias SantoApi.Owners
  alias SantoApi.Owners.Challenge
  alias SantoApiWeb.VehicleLive.Presenter

  @impl true
  def mount(%{"public_id" => public_id}, _session, socket) do
    case SantoApi.Registry.fetch_by_public_id(public_id) do
      {:ok, vehicle} ->
        if Owners.stewarding?(socket.assigns.current_scope, vehicle),
          do: {:ok, land_the_steward(socket, vehicle)},
          else: {:ok, mount_claim(socket, vehicle)}

      {:error, :not_found} ->
        raise SantoApiWeb.VehicleNotFound
    end
  end

  # Session zero (§1's caveat): an approved claimant arrives at the spec panel,
  # not at a page with nothing on it. Ten minutes of describing the car is the
  # difference between a page worth returning to and an empty one.
  defp land_the_steward(socket, vehicle) do
    user = socket.assigns.current_scope.user

    case Owners.challenge(user, vehicle) do
      %Challenge{status: :approved} ->
        socket
        |> put_flash(:info, "This car is yours to maintain. Start with what it is now.")
        |> redirect(to: ~p"/v/#{vehicle.public_id}/spec")

      _no_claim ->
        socket
        |> put_flash(:info, "You already maintain this car's log.")
        |> redirect(to: ~p"/v/#{vehicle.public_id}")
    end
  end

  defp mount_claim(socket, vehicle) do
    user = socket.assigns.current_scope.user

    socket
    |> assign(:page_title, "Claim — #{Presenter.title(vehicle)}")
    |> assign(:vehicle, vehicle)
    # The minted party name where one exists, else the handle reserved at
    # registration (§9.1) — either way the flow's handle step disappears.
    # Nil only for accounts predating the reservation, which still get the
    # legacy input.
    |> assign(:handle, (Owners.party(user) && Owners.party(user).name) || user.handle)
    |> assign(:incumbent, Owners.steward(vehicle))
    |> assign(:error, nil)
    |> assign_challenge(Owners.challenge(user, vehicle))
    |> assign_form(%{})
    |> allow_upload(:proof,
      accept: ~w(.jpg .jpeg .png .heic .webp),
      max_entries: 1,
      max_file_size: 20_000_000
    )
  end

  # A decided or lapsed claim is not a state to sit in: the claimant starts
  # over, with the reason they were given still on the screen.
  defp assign_challenge(socket, challenge) do
    socket
    |> assign(:challenge, challenge)
    |> assign(:step, step(challenge))
  end

  defp step(%Challenge{status: :issued}), do: :photograph
  defp step(%Challenge{status: :submitted}), do: :waiting
  defp step(_none), do: :start

  @impl true
  def handle_event("validate", %{"claim" => params}, socket) do
    {:noreply, socket |> assign(:error, nil) |> assign_form(params)}
  end

  # A claimant who already has a handle submits a form with nothing in it —
  # there is one button and no field, which is the point.
  def handle_event("issue", unsigned_params, socket) do
    params = Map.get(unsigned_params, "claim", %{})
    user = socket.assigns.current_scope.user
    opts = if handle = params["handle"], do: [handle: handle], else: []

    case Owners.issue_challenge(user, socket.assigns.vehicle, opts) do
      {:ok, challenge} ->
        {:noreply, socket |> assign(:error, nil) |> assign_challenge(challenge)}

      {:error, reason} ->
        {:noreply, socket |> assign(:error, refusal(reason)) |> assign_form(params)}
    end
  end

  def handle_event("validate_proof", _params, socket), do: {:noreply, socket}

  def handle_event("submit_proof", _params, socket) do
    case consume_proof(socket) do
      [photo] -> submit(socket, photo)
      [] -> {:noreply, assign(socket, :error, "Add the photo first.")}
    end
  end

  defp submit(socket, photo) do
    case Owners.submit_proof(socket.assigns.challenge, photo) do
      {:ok, challenge} ->
        {:noreply, socket |> assign(:error, nil) |> assign_challenge(challenge)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, refusal(reason))}
    end
  end

  # Copied out of the upload's temp path, which is gone the moment this callback
  # returns — the registry hashes and stores the bytes itself.
  defp consume_proof(socket) do
    consume_uploaded_entries(socket, :proof, fn %{path: path}, entry ->
      destination = Path.join(System.tmp_dir!(), "#{Ecto.UUID.generate()}-#{entry.client_name}")
      File.cp!(path, destination)
      {:ok, %{path: destination, filename: entry.client_name, mime: entry.client_type}}
    end)
  end

  defp refusal(:handle_taken), do: "That handle is already taken. Pick another."
  defp refusal(:handle_required), do: "Choose a handle first."
  defp refusal(:handle_immutable), do: "Your handle is already set and cannot change."
  defp refusal(:already_stewarded), do: "You already maintain this car's log."
  defp refusal(:expired), do: "That code ran out. Ask for a fresh one and photograph it again."
  defp refusal(:not_pending), do: "That claim has already been decided."

  defp refusal(%Ecto.Changeset{}),
    do: "A handle is 3 to 32 characters: lowercase letters, numbers, hyphens or underscores."

  defp refusal(_reason), do: "That could not be done."

  defp assign_form(socket, params), do: assign(socket, :form, to_form(params, as: :claim))

  ## Render

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-lg px-5 pt-10 pb-24 sm:px-8">
      <.link navigate={~p"/v/#{@vehicle.public_id}"} class="vs-eyebrow" style="color: var(--vs-dim)">
        <span aria-hidden="true">&larr;</span> {Presenter.title(@vehicle)}
      </.link>

      <h1 class="vs-spec mt-4 text-3xl sm:text-4xl">Is this your car?</h1>

      <p :if={@error} id="claim-error" class="vs-refusal mt-6 text-sm">{@error}</p>

      <.contested :if={@incumbent} incumbent={@incumbent} />

      <.start :if={@step == :start} form={@form} handle={@handle} challenge={@challenge} />
      <.photograph :if={@step == :photograph} challenge={@challenge} uploads={@uploads} />
      <.waiting :if={@step == :waiting} vehicle={@vehicle} />
    </div>
    """
  end

  attr :incumbent, :map, required: true

  defp contested(assigns) do
    ~H"""
    <div class="vs-inset mt-6 text-sm" style="color: var(--vs-dim)">
      <p>
        This car's log is maintained by <span class="vs-code" style="color: var(--vs-dial)">{@incumbent.name}</span>.
      </p>
      <p class="mt-2">
        A second claim does not replace them. It goes to an operator, who decides between
        you on evidence — registration, service records in your name — and tells you both
        what was decided.
      </p>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :handle, :string, default: nil
  attr :challenge, :map, default: nil

  defp start(assigns) do
    ~H"""
    <div>
      <p :if={denied?(@challenge)} class="vs-refusal mt-6 text-sm" id="claim-denial">
        Your last claim was turned down: {@challenge.reason}
      </p>

      <p class="mt-6 text-base leading-relaxed" style="color: var(--vs-dim)">
        We will give you a code. Write it down, photograph the VIN plate with the code in
        frame, and a person here looks at the picture. The code is what makes the photo
        proof — it did not exist yesterday, so a picture taken at a show last summer
        cannot satisfy it.
      </p>

      <p class="mt-4 text-sm leading-relaxed" style="color: var(--vs-dim)">
        What this gets you is the log: entries under your own name, the spec, photos.
        It does not touch the factory record, and it says nothing about who owns the car
        — the page will read <em>maintained by</em>, never <em>owned by</em>.
      </p>

      <.form for={@form} id="claim-form" phx-change="validate" phx-submit="issue" class="mt-8">
        <div :if={is_nil(@handle)}>
          <label for="claim_handle" class="vs-eyebrow" style="color: var(--vs-dim)">
            Your handle
          </label>
          <input
            type="text"
            id="claim_handle"
            name="claim[handle]"
            value={@form[:handle].value}
            autocomplete="off"
            class="vs-field vs-code mt-2"
            placeholder="mhyrr"
          />
          <p class="mt-2 text-xs leading-relaxed" style="color: var(--vs-dim)">
            This is permanent. Every entry you log is signed with it, and the signature is
            part of what makes the entry checkable later — so it cannot be changed
            afterwards, by you or by us. Lowercase letters, numbers, hyphens.
          </p>
        </div>

        <p :if={@handle} class="text-sm" style="color: var(--vs-dim)">
          You log as <span class="vs-code" style="color: var(--vs-dial)">{@handle}</span>.
        </p>

        <button type="submit" id="claim-start" class="vs-commit mt-6 w-full">
          Get my code
        </button>
      </.form>
    </div>
    """
  end

  defp denied?(%Challenge{status: :denied, reason: reason}) when is_binary(reason), do: true
  defp denied?(_challenge), do: false

  attr :challenge, :map, required: true
  attr :uploads, :map, required: true

  defp photograph(assigns) do
    ~H"""
    <div>
      <p class="mt-6 text-base leading-relaxed" style="color: var(--vs-dim)">
        Write this down and photograph it beside the VIN plate — the windshield corner or
        the door jamb sticker. Both have to be readable in one frame.
      </p>

      <p
        id="challenge-code"
        class="vs-figure mt-6 text-center text-4xl tracking-[0.3em] sm:text-5xl"
      >
        {Challenge.spaced(@challenge.code)}
      </p>

      <p class="vs-code mt-3 text-center text-xs" style="color: var(--vs-dim)">
        good for 72 hours — until {Calendar.strftime(@challenge.expires_at, "%-d %B, %H:%M UTC")}
      </p>

      <form id="proof-form" phx-submit="submit_proof" phx-change="validate_proof" class="mt-8">
        <span class="vs-eyebrow" style="color: var(--vs-dim)">The photo</span>
        <div class="mt-2">
          <.live_file_input upload={@uploads.proof} class="vs-file" />
        </div>

        <p
          :for={entry <- @uploads.proof.entries}
          class="vs-code mt-2 text-xs"
          style="color: var(--vs-dim)"
        >
          {entry.client_name}
        </p>

        <p :for={error <- upload_errors(@uploads.proof)} class="vs-refusal mt-2 text-xs">
          {upload_error(error)}
        </p>

        <button type="submit" id="proof-send" class="vs-commit mt-6 w-full">Send it in</button>
      </form>

      <p class="mt-6 text-xs leading-relaxed" style="color: var(--vs-dim)">
        The photo is not published. It is read here, by a person, and kept with the record
        of the decision.
      </p>
    </div>
    """
  end

  attr :vehicle, :map, required: true

  defp waiting(assigns) do
    ~H"""
    <div>
      <p class="mt-6 text-base leading-relaxed">
        Your photo is with an operator.
      </p>

      <p class="mt-4 text-sm leading-relaxed" style="color: var(--vs-dim)">
        Somebody looks at every claim — no model decides this, and we would rather be slow
        than hand a stranger somebody's car. You will hear either way by email.
      </p>

      <.link navigate={~p"/v/#{@vehicle.public_id}"} class="vs-quiet mt-8 inline-block">
        Back to the car
      </.link>
    </div>
    """
  end

  defp upload_error(:too_large), do: "That photo is too large."
  defp upload_error(:too_many_files), do: "One photo."
  defp upload_error(:not_accepted), do: "Photos only."
  defp upload_error(_error), do: "That photo could not be read."
end
