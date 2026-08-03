defmodule SantoApiWeb.BenchLive.Claims do
  @moduledoc """
  The claiming queue (owner_surface §4 step 4, §9.2).

  A person decides every claim. There is no vision pre-check and nothing
  auto-approves: at a few claims a week the operator is looking at the photograph
  regardless, and the period where we are still learning what a fraudulent claim
  looks like is exactly the wrong one to automate. When volume argues otherwise,
  a model's read becomes a proposal on this screen — never the decision.

  What the operator is checking, in order: the VIN in the photograph matches the
  car, the challenge code is in frame and matches this row, and the plate looks
  photographed in place rather than off another photograph.
  """

  use SantoApiWeb, :live_view

  alias SantoApi.Owners
  alias SantoApi.Owners.Challenge
  alias SantoApiWeb.VehicleLive.Presenter

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:error, nil) |> assign_queue()}
  end

  defp assign_queue(socket) do
    assign(socket, :claims, Enum.map(Owners.list_pending_challenges(), &decorate/1))
  end

  # The incumbent is the whole story of a contested claim, so it is read here
  # rather than left for the operator to go and look up.
  defp decorate(%Challenge{} = challenge) do
    %{
      challenge: challenge,
      vehicle: challenge.vehicle,
      title: Presenter.title(challenge.vehicle),
      chassis: Presenter.chassis(challenge.vehicle),
      incumbent: Owners.steward(challenge.vehicle)
    }
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    with {:ok, challenge} <- fetch(socket, id),
         {:ok, _stewardship} <- Owners.approve_challenge(challenge, operator(socket)) do
      {:noreply, socket |> assign(:error, nil) |> assign_queue()}
    else
      {:error, reason} -> {:noreply, socket |> assign(:error, refusal(reason)) |> assign_queue()}
    end
  end

  def handle_event("deny", %{"claim_id" => id, "reason" => reason}, socket) do
    case String.trim(reason) do
      "" ->
        {:noreply, assign(socket, :error, "Say why. The claimant is owed a reason.")}

      reason ->
        with {:ok, challenge} <- fetch(socket, id),
             {:ok, _denied} <- Owners.deny_challenge(challenge, operator(socket), reason) do
          {:noreply, socket |> assign(:error, nil) |> assign_queue()}
        else
          {:error, error} -> {:noreply, assign(socket, :error, refusal(error))}
        end
    end
  end

  defp fetch(socket, id) do
    case Enum.find(socket.assigns.claims, &(&1.challenge.id == id)) do
      %{challenge: challenge} -> {:ok, challenge}
      nil -> {:error, :not_found}
    end
  end

  defp operator(socket), do: socket.assigns.current_scope.user

  # §4's escalation, in one sentence: the incumbent keeps the car until somebody
  # adjudicates the dispute, and approving over them is not the adjudication.
  defp refusal(:already_stewarded),
    do:
      "Somebody already maintains that car. Revoke the incumbent first if this claim wins — " <>
        "approving here would not decide the dispute, it would hide it."

  defp refusal(:not_pending), do: "That claim has already been decided."
  defp refusal(:no_proof), do: "That claim has no photo yet."
  defp refusal(:not_found), do: "That claim is no longer in the queue."
  defp refusal(reason), do: "Refused: #{inspect(reason)}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Claims waiting
        <:subtitle>
          A photograph of the VIN plate with the code in frame. Check the VIN against the
          car, the code against this row, and whether the plate was photographed in place.
        </:subtitle>
      </.header>

      <div :if={@error} id="claims-error" class="alert alert-error my-4">{@error}</div>

      <p :if={@claims == []} class="text-base-content/70 mt-6">Nothing waiting.</p>

      <div
        :for={row <- @claims}
        id={"claim-#{row.challenge.id}"}
        class="card bg-base-200 mt-6 p-5"
      >
        <div class="flex flex-wrap items-baseline justify-between gap-3">
          <div>
            <.link navigate={~p"/bench/vehicles/#{row.vehicle.id}"} class="link text-lg font-semibold">
              {row.title}
            </.link>
            <p class="font-mono text-sm text-base-content/70">{row.chassis}</p>
          </div>

          <div class="text-right">
            <p class="text-sm">
              claimed by <span class="font-mono">{row.challenge.handle}</span>
            </p>
            <p class="text-xs text-base-content/70">{row.challenge.user.email}</p>
            <p class="text-xs text-base-content/70">
              sent {Calendar.strftime(row.challenge.inserted_at, "%-d %B %Y, %H:%M UTC")}
            </p>
          </div>
        </div>

        <div :if={row.incumbent} class="alert alert-warning mt-4">
          <span>
            <strong>Contested.</strong>
            This car is maintained by <span class="font-mono">{row.incumbent.name}</span>. Decide the
            dispute on evidence before anything here changes hands — both parties are owed
            the outcome.
          </span>
        </div>

        <div class="mt-4 flex flex-wrap items-start gap-6">
          <div>
            <p class="text-xs uppercase tracking-wide text-base-content/70">Code to find</p>
            <p class="font-mono text-2xl tracking-[0.25em]">
              {Challenge.spaced(row.challenge.code)}
            </p>
          </div>

          <!-- Proof photos render here and nowhere else: serving artifact images
               publicly is an open rights question, and this one is a picture of
               somebody's car and their handwriting. -->
          <a href={~p"/bench/artifacts/#{row.challenge.proof_artifact_id}"} target="_blank">
            <img
              src={~p"/bench/artifacts/#{row.challenge.proof_artifact_id}"}
              alt="Possession proof"
              class="max-h-64 rounded border border-base-300"
            />
          </a>
        </div>

        <div class="mt-5 flex flex-wrap items-end gap-3">
          <.button variant="primary" phx-click="approve" phx-value-id={row.challenge.id}>
            Approve
          </.button>

          <form id={"deny-#{row.challenge.id}"} phx-submit="deny" class="flex items-end gap-2">
            <input type="hidden" name="claim_id" value={row.challenge.id} />
            <.input type="text" name="reason" value="" label="Reason, if you deny it" />
            <.button>Deny</.button>
          </form>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
