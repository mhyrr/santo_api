defmodule SantoApiWeb.BenchLive.Show do
  @moduledoc """
  The operator workbench for a single vehicle: facts, comparison,
  claims, evidence requests, and artifacts, each with the actions that
  move it forward. Every action reloads through `load_vehicle/2` so the
  page never drifts from the registry's state.
  """

  use SantoApiWeb, :live_view

  alias SantoApi.AcquisitionRuns
  alias SantoApi.Registry
  alias SantoApi.Registry.Vehicle

  @artifact_kinds ~w(document photo receipt listing)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Registry.fetch_vehicle(id) do
      {:ok, vehicle} ->
        if connected?(socket) do
          :ok = AcquisitionRuns.subscribe(socket.assigns.current_scope, vehicle)
        end

        {:ok,
         socket
         |> allow_upload(:file,
           accept: ~w(.pdf .jpg .jpeg .png),
           max_entries: 1,
           max_file_size: 20_000_000
         )
         |> load_vehicle(vehicle)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Vehicle not found")
         |> push_navigate(to: ~p"/bench")}
    end
  end

  defp load_vehicle(socket, id) when is_binary(id) do
    {:ok, vehicle} = Registry.fetch_vehicle(id)
    load_vehicle(socket, vehicle)
  end

  defp load_vehicle(socket, vehicle) do
    run = AcquisitionRuns.latest_for_vehicle(socket.assigns.current_scope, vehicle)
    steps = if run, do: run.steps, else: []
    artifact_ids = steps |> Enum.map(& &1.artifact_id) |> Enum.reject(&is_nil/1)
    reference_findings = Registry.reference_findings(artifact_ids)

    socket
    |> assign(:vehicle, vehicle)
    |> assign(:acquisition_run, run)
    |> stream(:acquisition_steps, steps, reset: true)
    |> assign(:recall_campaign_count, reference_count(reference_findings, "recall_campaigns"))
    |> assign(
      :technical_bulletin_count,
      reference_count(reference_findings, "technical_bulletins")
    )
    |> stream(:reference_findings, reference_findings,
      reset: true,
      dom_id: &"reference-finding-#{&1.artifact_id}"
    )
    |> assign(:claims, Registry.list_claims(vehicle.id))
    |> assign(:artifacts, Registry.list_artifacts(vehicle.id))
    |> assign(:adjudications, Registry.list_adjudications(vehicle.id))
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
        "adjudicate_claims",
        %{
          "claim_a_id" => claim_a_id,
          "claim_b_id" => claim_b_id,
          "prevailing_claim_id" => prevailing_claim_id,
          "note" => note
        } = params,
        socket
      ) do
    evidence_artifact_ids = normalize_ids(params["evidence_artifact_ids"])

    case Registry.adjudicate_claims(
           Registry.vin_santo_party(),
           claim_a_id,
           claim_b_id,
           %{
             outcome: :supersede,
             prevailing_claim_id: prevailing_claim_id,
             evidence_artifact_ids: evidence_artifact_ids,
             note: note
           }
         ) do
      {:ok, _adjudication} ->
        {:noreply, load_vehicle(socket, socket.assigns.vehicle.id)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Adjudication failed: #{inspect(reason)}")}
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

  def handle_event(
        "run_acquisition",
        _params,
        %{assigns: %{vehicle: %Vehicle{identity_kind: :vin} = vehicle}} = socket
      ) do
    case AcquisitionRuns.start_operator(socket.assigns.current_scope, vehicle.input) do
      {:ok, disposition, _vehicle, _run} ->
        {:noreply,
         socket
         |> put_flash(:info, acquisition_message(disposition))
         |> load_vehicle(vehicle.id)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Acquisition failed: #{inspect(reason)}")}
    end
  end

  def handle_event("run_acquisition", _params, socket) do
    {:noreply, put_flash(socket, :error, "A standard VIN is required for provider lookups.")}
  end

  @impl true
  def handle_info({:acquisition_run_updated, _run_id}, socket) do
    {:noreply, load_vehicle(socket, socket.assigns.vehicle.id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@vehicle.identity_key}
        <:subtitle>
          santo v{@vehicle.santo_version}
        </:subtitle>
        <:actions>
          <.button href={~p"/v/#{@vehicle.public_id}"}>Public record</.button>
          <.button
            :if={@vehicle.identity_kind == :vin}
            id="run-acquisition-button"
            phx-click="run_acquisition"
            variant="primary"
          >
            Run all free providers
          </.button>
        </:actions>
      </.header>

      <div class="flex items-center gap-2 mb-4">
        <span class="badge badge-outline">{@vehicle.identity_kind}</span>
        <span :if={@vehicle.identity_kind == :disputed} class="text-sm text-base-content/70">
          candidates: {Enum.join(@vehicle.candidates, ", ")}
        </span>
      </div>

      <section
        id="acquisition-run"
        data-run-id={@acquisition_run && @acquisition_run.id}
        data-run-status={@acquisition_run && @acquisition_run.status}
        class="mt-6 overflow-hidden rounded-2xl border border-base-300 bg-base-100 shadow-sm"
      >
        <div class="flex flex-wrap items-start justify-between gap-4 border-b border-base-300 px-5 py-4">
          <div>
            <div class="flex items-center gap-2">
              <h2 class="text-lg font-semibold">Acquisition run</h2>
              <span
                :if={@acquisition_run}
                id="acquisition-run-status"
                class={[
                  "rounded-full px-2.5 py-1 text-xs font-semibold uppercase tracking-wide",
                  run_status_class(@acquisition_run.status)
                ]}
              >
                {@acquisition_run.status}
              </span>
            </div>
            <p class="mt-1 text-sm text-base-content/60">
              Every configured free lookup is recorded, including unsupported questions and failures.
            </p>
          </div>

          <dl :if={@acquisition_run} class="grid grid-cols-2 gap-x-5 gap-y-1 text-xs">
            <dt class="text-base-content/50">Run</dt>
            <dd class="font-mono text-right">{short_id(@acquisition_run.id)}</dd>
            <dt class="text-base-content/50">Started</dt>
            <dd class="text-right">{format_timestamp(@acquisition_run.started_at)}</dd>
            <dt class="text-base-content/50">Finished</dt>
            <dd class="text-right">{format_timestamp(@acquisition_run.finished_at)}</dd>
          </dl>
        </div>

        <div
          :if={is_nil(@acquisition_run)}
          id="no-acquisition-run"
          class="px-5 py-8 text-sm text-base-content/60"
        >
          <%= if @vehicle.identity_kind == :vin do %>
            No acquisition has run for this VIN yet.
          <% else %>
            Provider acquisition requires a standard 17-character VIN.
          <% end %>
        </div>

        <div
          :if={@acquisition_run}
          id="acquisition-steps"
          phx-update="stream"
          class="divide-y divide-base-300"
        >
          <div
            id="acquisition-steps-empty"
            class="hidden px-5 py-8 text-center text-sm text-base-content/50 only:block"
          >
            No acquisition steps were planned.
          </div>
          <article
            :for={{id, step} <- @streams.acquisition_steps}
            id={id}
            data-step-key={step.step_key}
            data-step-status={step.status}
            class="grid min-w-0 grid-cols-[minmax(0,1fr)_auto] gap-x-4 gap-y-2 px-5 py-4 text-sm sm:grid-cols-[minmax(0,1fr)_minmax(0,1.35fr)_auto] sm:gap-x-5"
          >
            <div class="min-w-0">
              <div class="font-medium">{step_source(step)}</div>
              <div class="mt-0.5 text-xs text-base-content/60">
                {humanize_atom(step.capability)}
              </div>
            </div>

            <div class="col-span-2 min-w-0 border-t border-base-300 pt-3 text-base-content/70 sm:col-span-1 sm:col-start-2 sm:row-start-1 sm:border-0 sm:pt-0">
              <div>{step_result(step)}</div>
              <div :if={step.missing_selectors != []} class="mt-1 text-xs text-warning">
                Missing: {Enum.join(step.missing_selectors, ", ")}
              </div>
              <div :if={step.conflicted_selectors != []} class="mt-1 text-xs text-error">
                Conflicted: {Enum.join(step.conflicted_selectors, ", ")}
              </div>
              <a
                :if={step.artifact_id}
                href={~p"/bench/artifacts/#{step.artifact_id}"}
                target="_blank"
                class="link mt-1 inline-block text-xs"
              >
                Open snapshot
              </a>
            </div>

            <div class="col-start-2 row-start-1 justify-self-end sm:col-start-3">
              <span class={[
                "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold",
                step_status_class(step.status)
              ]}>
                {humanize_atom(step.status)}
              </span>
            </div>

            <div class="col-span-2 flex min-w-0 items-start justify-between gap-4 pt-1 text-xs text-base-content/60 sm:col-span-3">
              <span class="tabular-nums">Attempts {step.attempt_count}</span>
              <details :if={step_details?(step)} class="group min-w-0 text-right">
                <summary class="cursor-pointer font-medium hover:text-base-content">
                  Diagnostics
                </summary>
                <pre class="mt-2 max-w-full whitespace-pre-wrap break-words rounded-lg bg-base-200 p-3 text-left text-xs">{step_details(step)}</pre>
              </details>
            </div>
          </article>
        </div>
      </section>

      <section
        id="nhtsa-reference-findings"
        class="mt-6 overflow-hidden rounded-2xl border border-base-300 bg-base-100 shadow-sm"
      >
        <div class="flex flex-wrap items-start justify-between gap-4 border-b border-base-300 px-5 py-4">
          <div>
            <h2 class="text-lg font-semibold">NHTSA reference findings</h2>
            <p class="mt-1 text-sm text-base-content/60">
              Model-population records from preserved official corpus releases.
            </p>
          </div>
          <dl class="grid grid-cols-2 gap-x-5 gap-y-1 text-xs tabular-nums">
            <dt class="text-base-content/50">Recall campaigns</dt>
            <dd id="recall-campaign-count" class="text-right">{@recall_campaign_count}</dd>
            <dt class="text-base-content/50">Technical bulletins</dt>
            <dd id="technical-bulletin-count" class="text-right">{@technical_bulletin_count}</dd>
          </dl>
        </div>

        <div id="reference-findings" phx-update="stream" class="divide-y divide-base-300">
          <div
            id="reference-findings-empty"
            class="hidden px-5 py-8 text-sm text-base-content/60 only:block"
          >
            No NHTSA reference findings have been acquired for this run.
          </div>
          <article
            :for={{id, finding} <- @streams.reference_findings}
            id={id}
            data-capability={finding.capability}
            class="px-5 py-5"
          >
            <div class="flex flex-wrap items-center justify-between gap-3">
              <h3 class="font-semibold">{humanize_string(finding.capability)}</h3>
              <span class="rounded-full bg-base-200 px-2.5 py-1 text-xs font-semibold">
                {length(finding.records)} records · {humanize_string(finding.coverage)}
              </span>
            </div>

            <p class="mt-1 text-xs font-medium text-warning">
              {finding.applicability_label}
            </p>

            <div class="mt-4 grid gap-3">
              <div
                :for={record <- finding.records}
                id={"reference-record-#{short_id(finding.artifact_id)}-#{dom_key(record["identifier"])}"}
                class="rounded-xl border border-base-300 bg-base-50 p-4"
              >
                <div class="flex flex-wrap items-start justify-between gap-3">
                  <div class="min-w-0">
                    <div class="font-mono text-xs font-semibold text-base-content/60">
                      {record_identifier(record)}
                    </div>
                    <h4 class="mt-1 font-medium">{record["title"] || record["summary"]}</h4>
                  </div>
                  <a
                    :if={record["document_url"] || record["source_url"]}
                    href={record["document_url"] || record["source_url"]}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="link text-sm"
                  >
                    Official source
                  </a>
                </div>

                <p :if={record["summary"]} class="mt-2 line-clamp-3 text-sm text-base-content/70">
                  {record["summary"]}
                </p>

                <div class="mt-3 flex flex-wrap gap-x-5 gap-y-1 text-xs text-base-content/60">
                  <span>{format_applicability(record["applicability"])}</span>
                  <span>Corpus release {get_in(record, ["corpus_release", "released_on"])}</span>
                </div>
              </div>
            </div>
          </article>
        </div>
      </section>

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
              <form
                :if={row.status == :conflict and length(row.claims) == 2 and @artifacts != []}
                id={"adjudicate-#{dom_key(row.predicate)}"}
                phx-submit="adjudicate_claims"
                class="mt-3 grid gap-2 border-t border-base-300 pt-3"
              >
                <.input
                  type="hidden"
                  name="claim_a_id"
                  value={Enum.at(row.claims, 0).claim_id}
                />
                <.input
                  type="hidden"
                  name="claim_b_id"
                  value={Enum.at(row.claims, 1).claim_id}
                />
                <.input
                  type="select"
                  name="prevailing_claim_id"
                  label="Keep claim"
                  value={Enum.at(row.claims, 0).claim_id}
                  options={claim_options(row.claims)}
                />
                <.input
                  type="select"
                  name="evidence_artifact_ids[]"
                  label="Decision evidence"
                  value={nil}
                  prompt="Choose an artifact"
                  options={artifact_options(@artifacts)}
                  required
                />
                <.input
                  type="text"
                  name="note"
                  label="Decision note"
                  value=""
                  required
                />
                <.button>Supersede losing claim</.button>
              </form>
              <p
                :if={row.status == :conflict and @artifacts == []}
                class="mt-2 text-sm text-base-content/60"
              >
                Upload decision evidence to adjudicate.
              </p>
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
          <tr :for={claim <- @claims} data-claim-id={claim.id} data-state={claim.state}>
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

      <h2 class="text-lg font-semibold mt-6">Adjudications</h2>
      <table id="adjudications" class="table table-zebra">
        <thead>
          <tr>
            <th>outcome</th>
            <th>claims</th>
            <th>decided by</th>
            <th>note</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={adjudication <- @adjudications} data-adjudication-id={adjudication.id}>
            <td>{adjudication.outcome}</td>
            <td>
              {short_id(adjudication.claim_a_id)} ↔ {short_id(adjudication.claim_b_id)}
            </td>
            <td>{adjudication.decided_by_party.name}</td>
            <td>{adjudication.note}</td>
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

  defp acquisition_message(:created), do: "Vehicle added. Free provider lookups are running."
  defp acquisition_message(:restarted), do: "Fresh free-provider acquisition started."
  defp acquisition_message(:active), do: "The active acquisition is already running."

  defp run_status_class(:pending), do: "bg-warning/15 text-warning"
  defp run_status_class(:running), do: "bg-info/15 text-info"
  defp run_status_class(:complete), do: "bg-success/15 text-success"

  defp step_status_class(:pending), do: "bg-warning/15 text-warning"
  defp step_status_class(:running), do: "bg-info/15 text-info"
  defp step_status_class(:complete), do: "bg-success/15 text-success"
  defp step_status_class(:no_record), do: "bg-base-300 text-base-content/70"
  defp step_status_class(:needs_input), do: "bg-warning/15 text-warning"
  defp step_status_class(:failed), do: "bg-error/15 text-error"
  defp step_status_class(:unsupported), do: "bg-base-300 text-base-content/60"

  defp step_source(%{kind: :santo_decode}), do: "Santo decoder"
  defp step_source(%{provider: :nhtsa_vpic}), do: "NHTSA vPIC"
  defp step_source(%{provider: :nhtsa_public_corpus}), do: "NHTSA public corpus"
  defp step_source(%{kind: :gap}), do: "No free provider"
  defp step_source(%{provider: provider}) when is_atom(provider), do: humanize_atom(provider)
  defp step_source(_step), do: "Registry"

  defp step_result(%{kind: :santo_decode}), do: "Deterministic decode admitted"

  defp step_result(%{status: :pending, depends_on_step_id: dependency})
       when not is_nil(dependency),
       do: "Waiting for identity selectors"

  defp step_result(%{status: :pending}), do: "Queued"
  defp step_result(%{status: :running}), do: "Lookup in progress"
  defp step_result(%{status: :no_record}), do: "Provider returned no record"
  defp step_result(%{status: :needs_input}), do: "Additional selectors required"
  defp step_result(%{status: :failed}), do: "Lookup failed after retries"
  defp step_result(%{status: :unsupported}), do: "No configured free provider"

  defp step_result(%{status: :complete, diagnostics: diagnostics}) do
    case diagnostics["coverage"] do
      nil -> "Evidence acquired"
      coverage -> humanize_string(coverage)
    end
  end

  defp step_details?(step) do
    map_size(step.diagnostics || %{}) > 0 or not is_nil(step.last_error)
  end

  defp step_details(step) do
    %{}
    |> maybe_put_detail(:diagnostics, step.diagnostics)
    |> maybe_put_detail(:last_error, step.last_error)
    |> inspect(pretty: true, limit: 50, printable_limit: 2_000)
  end

  defp maybe_put_detail(details, _key, value) when value in [nil, %{}], do: details
  defp maybe_put_detail(details, key, value), do: Map.put(details, key, value)

  defp humanize_atom(value) when is_atom(value),
    do: value |> Atom.to_string() |> humanize_string()

  defp humanize_string(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp humanize_string(_value), do: "Unknown"

  defp format_timestamp(nil), do: "—"

  defp format_timestamp(%DateTime{} = timestamp) do
    Calendar.strftime(timestamp, "%Y-%m-%d %H:%M UTC")
  end

  defp badge_class("verified"), do: "badge-success"
  defp badge_class("conflicted"), do: "badge-error"
  defp badge_class(_status), do: "badge-neutral"

  defp normalize_ids(ids) when is_list(ids), do: ids
  defp normalize_ids(id) when is_binary(id) and id != "", do: [id]
  defp normalize_ids(_ids), do: []

  defp claim_options(claims) do
    Enum.map(claims, &{"#{&1.party}: #{inspect(&1.value)}", &1.claim_id})
  end

  defp artifact_options(artifacts) do
    Enum.map(artifacts, &{&1.metadata["filename"] || &1.source_url || short_id(&1.id), &1.id})
  end

  defp reference_count(findings, capability) do
    findings
    |> Enum.filter(&(&1.capability == capability))
    |> Enum.reduce(0, &(length(&1.records) + &2))
  end

  defp record_identifier(%{"nhtsa_id" => nhtsa_id, "identifier" => identifier})
       when is_binary(nhtsa_id),
       do: "NHTSA #{nhtsa_id} · #{identifier}"

  defp record_identifier(record), do: record["identifier"]

  defp format_applicability([first | rest]) do
    first = applicability_tuple(first)

    if rest == [] do
      first
    else
      first <> " +#{length(rest)} application rows"
    end
  end

  defp format_applicability(_applicability), do: "Applicability unavailable"

  defp applicability_tuple(applicability) do
    [
      applicability["model_year"] && to_string(applicability["model_year"]),
      applicability["marque"],
      applicability["model"]
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp dom_key(value) do
    value
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_-]+/, "-")
  end

  defp short_id(id), do: String.slice(id || "", 0, 8)
end
