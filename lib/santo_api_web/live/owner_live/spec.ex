defmodule SantoApiWeb.OwnerLive.Spec do
  @moduledoc """
  The current-spec panel — §2b's cold start.

  A built car's first session must not be archaeology. The seed traits are six
  editable fields; each filled one becomes an observed claim through the normal
  propose-and-self-ratify path, and the fold has a full baseline in ten minutes.
  Events refine it from there.

  Separate from the composer on purpose. Filling in a spec is a considered
  ten-minute task and logging a fill-up is a ten-second one — putting them on one
  screen would cost the fast path its speed.
  """

  use SantoApiWeb, :live_view

  alias SantoApi.Owners
  alias SantoApi.Registry
  alias SantoApi.Registry.Vocabulary
  alias SantoApiWeb.VehicleLive.Presenter

  @impl true
  def mount(%{"public_id" => public_id}, _session, socket) do
    case Registry.fetch_by_public_id(public_id) do
      {:ok, vehicle} ->
        if Owners.stewarding?(socket.assigns.current_scope, vehicle),
          do: {:ok, mount_spec(socket, vehicle)},
          else: {:ok, turn_away(socket, vehicle)}

      {:error, :not_found} ->
        raise SantoApiWeb.VehicleNotFound
    end
  end

  defp mount_spec(socket, vehicle) do
    socket
    |> assign(:page_title, "Spec — #{Presenter.title(vehicle)}")
    |> assign(:vehicle, vehicle)
    |> assign(:traits, Vocabulary.trait_predicates())
    |> assign(:error, nil)
    |> assign_form(current_values(vehicle))
  end

  defp turn_away(socket, vehicle) do
    socket
    |> put_flash(:error, "You do not maintain this car's log.")
    |> redirect(to: ~p"/v/#{vehicle.public_id}")
  end

  # Pre-filled from the fold, so a second visit edits rather than starts over.
  defp current_values(vehicle) do
    Map.new(Vocabulary.trait_predicates(), fn trait ->
      {trait, get_in(vehicle.current_state, [trait, "value", "summary"]) || ""}
    end)
  end

  @impl true
  def handle_event("validate", %{"spec" => params}, socket) do
    {:noreply, socket |> assign(:error, nil) |> assign_form(params)}
  end

  def handle_event("save", %{"spec" => params}, socket) do
    vehicle = socket.assigns.vehicle

    case claims(socket.assigns.traits, params) do
      [] ->
        {:noreply,
         socket
         |> assign(:error, "Nothing to save yet — describe at least one part of the car.")
         |> assign_form(params)}

      claims ->
        write(socket, vehicle, claims, params)
    end
  end

  defp write(socket, vehicle, claims, params) do
    attrs = %{date: Date.utc_today(), claims: claims}

    case Owners.compose_entry(socket.assigns.current_scope, vehicle, attrs) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> put_flash(:info, "Spec recorded.")
         |> push_navigate(to: ~p"/v/#{vehicle.public_id}")}

      {:error, reason} ->
        {:noreply, socket |> assign(:error, refusal(reason)) |> assign_form(params)}
    end
  end

  # Only filled fields become claims. An empty field is a gap, and the record says
  # nothing rather than saying nothing-is-there.
  defp claims(traits, params) do
    for trait <- traits, summary = trimmed(params[trait]) do
      %{predicate: trait, value: %{"summary" => summary}}
    end
  end

  defp trimmed(nil), do: nil

  defp trimmed(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp refusal(:not_stewarded), do: "You no longer maintain this car's log."

  defp refusal({:claim_not_live, _state}),
    do: "One of these was already ruled on. Log the change as a mod instead."

  defp refusal(_reason), do: "That could not be saved."

  defp assign_form(socket, params), do: assign(socket, :form, to_form(params, as: :spec))

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-lg px-5 pt-10 pb-24 sm:px-8">
      <.link navigate={~p"/v/#{@vehicle.public_id}"} class="vs-eyebrow" style="color: var(--vs-dim)">
        <span aria-hidden="true">&larr;</span> {Presenter.title(@vehicle)}
      </.link>

      <h1 class="vs-spec mt-4 text-3xl sm:text-4xl">The spec, as it sits</h1>

      <p class="mt-4 text-sm leading-relaxed" style="color: var(--vs-dim)">
        What the car is now — not what it left the factory as. Leave anything you are
        unsure of blank; a blank field reads as a gap, which is the truth, and you can
        fill it in later. Every line here is dated and attributed to you.
      </p>

      <.form for={@form} id="spec-form" phx-change="validate" phx-submit="save" class="mt-8">
        <p :if={@error} id="spec-error" class="vs-refusal text-sm">{@error}</p>

        <div class="mt-2 space-y-5">
          <div :for={trait <- @traits}>
            <label for={field_id(trait)} class="vs-eyebrow" style="color: var(--vs-dim)">
              {Presenter.trait_label(trait)}
            </label>
            <input
              type="text"
              id={field_id(trait)}
              name={"spec[#{trait}]"}
              value={@form[trait].value}
              class="vs-field mt-2"
            />
          </div>
        </div>

        <button type="submit" id="spec-save" class="vs-commit mt-8 w-full">Record the spec</button>
      </.form>
    </div>
    """
  end

  defp field_id(trait), do: "spec_" <> String.replace(trait, ".", "_")
end
