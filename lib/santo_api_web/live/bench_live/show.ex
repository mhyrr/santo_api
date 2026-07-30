defmodule SantoApiWeb.BenchLive.Show do
  @moduledoc """
  The operator workbench for a single vehicle: facts, comparison,
  claims, evidence requests, and artifacts, each with the actions that
  move it forward. Every action reloads through `load_vehicle/2` so the
  page never drifts from the registry's state.
  """

  use SantoApiWeb, :live_view

  alias SantoApi.Registry

  @artifact_kinds ~w(document photo receipt listing)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Registry.fetch_vehicle(id) do
      {:ok, _vehicle} ->
        {:ok,
         socket
         |> allow_upload(:file,
           accept: ~w(.pdf .jpg .jpeg .png),
           max_entries: 1,
           max_file_size: 20_000_000
         )
         |> load_vehicle(id)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Vehicle not found")
         |> push_navigate(to: ~p"/bench")}
    end
  end

  defp load_vehicle(socket, id) do
    {:ok, vehicle} = Registry.fetch_vehicle(id)

    socket
    |> assign(:vehicle, vehicle)
    |> assign(:claims, Registry.list_claims(vehicle.id))
    |> assign(:artifacts, Registry.list_artifacts(vehicle.id))
    |> assign(:evidence_requests, Registry.list_evidence_requests(vehicle.id))
    |> assign(:comparison, Registry.claim_comparison(vehicle.id))
  end

  @impl true
  def handle_event("ratify_claim", %{"id" => id}, socket) do
    case Registry.ratify_claim(id) do
      {:ok, _claim} ->
        {:noreply, load_vehicle(socket, socket.assigns.vehicle.id)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Ratify failed: #{inspect(reason)}")}
    end
  end

  def handle_event("reject_claim", %{"id" => id}, socket) do
    case Registry.reject_claim(id) do
      {:ok, _claim} ->
        {:noreply, load_vehicle(socket, socket.assigns.vehicle.id)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Reject failed: #{inspect(reason)}")}
    end
  end

  def handle_event(
        "satisfy_request",
        %{"request_id" => request_id, "artifact_id" => artifact_id},
        socket
      ) do
    case Registry.satisfy_evidence_request(request_id, %{artifact_id: artifact_id}) do
      {:ok, _request} ->
        {:noreply, load_vehicle(socket, socket.assigns.vehicle.id)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Satisfy failed: #{inspect(reason)}")}
    end
  end

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("upload_artifact", %{"kind" => kind}, socket) when kind in @artifact_kinds do
    vehicle = socket.assigns.vehicle
    kind_atom = String.to_existing_atom(kind)

    consume_uploaded_entries(socket, :file, fn %{path: path}, entry ->
      {:ok, artifact} =
        Registry.create_upload_artifact(%{
          vehicle_id: vehicle.id,
          path: path,
          filename: entry.client_name,
          mime: entry.client_type,
          kind: kind_atom
        })

      {:ok, artifact}
    end)

    {:noreply, load_vehicle(socket, vehicle.id)}
  end

  def handle_event("run_vpic", _params, socket) do
    case Registry.ingest_vpic(socket.assigns.vehicle) do
      {:ok, _artifact} ->
        {:noreply, load_vehicle(socket, socket.assigns.vehicle.id)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "vPIC failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@vehicle.identity_key}
        <:subtitle>
          santo v{@vehicle.santo_version}
        </:subtitle>
        <:actions>
          <.button :if={@vehicle.identity_kind == :vin} phx-click="run_vpic">Run vPIC</.button>
        </:actions>
      </.header>

      <div class="flex items-center gap-2 mb-4">
        <span class="badge badge-outline">{@vehicle.identity_kind}</span>
        <span :if={@vehicle.identity_kind == :disputed} class="text-sm text-base-content/70">
          candidates: {Enum.join(@vehicle.candidates, ", ")}
        </span>
      </div>

      <h2 class="text-lg font-semibold mt-6">Facts</h2>
      <table class="table table-zebra">
        <thead>
          <tr>
            <th>predicate</th>
            <th>value</th>
            <th>status</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={{predicate, fact} <- @vehicle.facts} data-predicate={predicate}>
            <td>{predicate}</td>
            <td>{inspect(fact["value"])}</td>
            <td>
              <span class={["badge", badge_class(fact["status"])]}>{fact["status"]}</span>
            </td>
          </tr>
        </tbody>
      </table>

      <h2 class="text-lg font-semibold mt-6">Comparison</h2>
      <table class="table table-zebra">
        <thead>
          <tr>
            <th>predicate</th>
            <th>status</th>
            <th>claims</th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={row <- @comparison}
            data-predicate={row.predicate}
            class={row.status == :conflict && "bg-error/10"}
          >
            <td>{row.predicate}</td>
            <td>{row.status}</td>
            <td>
              <div :for={claim <- row.claims}>
                {claim.party}: {inspect(claim.value)}
              </div>
            </td>
          </tr>
        </tbody>
      </table>

      <h2 class="text-lg font-semibold mt-6">Claims</h2>
      <table class="table table-zebra">
        <thead>
          <tr>
            <th>predicate</th>
            <th>value</th>
            <th>scope</th>
            <th>state</th>
            <th>method</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={claim <- @claims} data-claim-id={claim.id}>
            <td>{claim.predicate}</td>
            <td>{inspect(claim.value)}</td>
            <td>{claim.scope_kind}</td>
            <td>{claim.state}</td>
            <td>{claim.method}</td>
            <td>
              <div :if={claim.state == :proposed} class="flex gap-2">
                <.button phx-click="ratify_claim" phx-value-id={claim.id}>Ratify</.button>
                <.button phx-click="reject_claim" phx-value-id={claim.id}>Reject</.button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>

      <h2 class="text-lg font-semibold mt-6">Evidence requests</h2>
      <table class="table table-zebra">
        <thead>
          <tr>
            <th>subject</th>
            <th>evidence classes</th>
            <th>status</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={request <- @evidence_requests} data-subject={request.subject}>
            <td>{request.subject}</td>
            <td>{Enum.join(request.evidence_classes, ", ")}</td>
            <td><span class="badge badge-outline">{request.status}</span></td>
            <td>
              <form
                :if={request.status == :open}
                id={"satisfy-#{request.id}"}
                phx-submit="satisfy_request"
              >
                <input type="hidden" name="request_id" value={request.id} />
                <select name="artifact_id" class="select select-sm">
                  <option :for={artifact <- @artifacts} value={artifact.id}>
                    {artifact.metadata["filename"] || artifact.source_url}
                  </option>
                </select>
                <.button>Satisfy</.button>
              </form>
            </td>
          </tr>
        </tbody>
      </table>

      <h2 class="text-lg font-semibold mt-6">Artifacts</h2>
      <table class="table table-zebra">
        <thead>
          <tr>
            <th>filename</th>
            <th>kind</th>
            <th>mime</th>
            <th>sha256</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={artifact <- @artifacts} data-artifact-id={artifact.id}>
            <td>{artifact.metadata["filename"] || artifact.source_url}</td>
            <td>{artifact.kind}</td>
            <td>{artifact.mime}</td>
            <td>{String.slice(artifact.sha256 || "", 0, 12)}</td>
          </tr>
        </tbody>
      </table>

      <form
        id="artifact-upload-form"
        phx-submit="upload_artifact"
        phx-change="validate_upload"
        class="mt-4 flex items-end gap-2"
      >
        <.live_file_input upload={@uploads.file} />
        <.input
          type="select"
          name="kind"
          label="Kind"
          value="document"
          options={[
            {"Document", "document"},
            {"Photo", "photo"},
            {"Receipt", "receipt"},
            {"Listing", "listing"}
          ]}
        />
        <.button>Upload</.button>
      </form>
      <p :for={entry <- @uploads.file.entries}>{entry.client_name} — {entry.progress}%</p>
    </Layouts.app>
    """
  end

  defp badge_class("verified"), do: "badge-success"
  defp badge_class("conflicted"), do: "badge-error"
  defp badge_class(_status), do: "badge-neutral"
end
