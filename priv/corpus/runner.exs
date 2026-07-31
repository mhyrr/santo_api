defmodule SantoApi.Corpus.Runner do
  @moduledoc """
  Drives one corpus car through the real registry paths (TK-001): ingest,
  vPIC, upload artifacts, propose → ratify document-borne claims. No
  hand-inserted rows — everything goes through `SantoApi.Registry`.

  Re-runnable: artifacts dedupe by content hash, claims by content hash;
  a second run reports what already exists and ratifies anything still
  proposed.
  """

  alias SantoApi.Registry
  alias SantoApi.Registry.Claim

  def run(%{vin: vin} = car) do
    {:ok, vehicle} = Registry.ingest(vin)
    IO.puts("== #{car.name} — #{vin}")
    IO.puts("   vehicle #{vehicle.id}")

    ingest_vpic(vehicle)
    artifacts = upload_artifacts(vehicle, car)
    Enum.each(car.claims, &propose_and_ratify(vehicle, &1, artifacts))
    report(vehicle)
  end

  defp ingest_vpic(vehicle) do
    case Registry.ingest_vpic(vehicle) do
      {:ok, artifact} -> IO.puts("   vPIC snapshot #{artifact.id}")
      {:error, reason} -> IO.puts("   vPIC FAILED (continuing): #{inspect(reason)}")
    end
  end

  defp upload_artifacts(vehicle, car) do
    Map.new(car.artifacts, fn spec ->
      {:ok, artifact} =
        Registry.create_upload_artifact(%{
          vehicle_id: vehicle.id,
          path: Path.join(car.dir, spec.file),
          filename: spec.file,
          mime: spec.mime,
          kind: spec.kind,
          source_url: spec.source_url,
          metadata: %{
            "rights" => "manual corpus research, internal use",
            "note" => spec.note
          }
        })

      IO.puts("   artifact #{spec.kind}: #{spec.file}")
      {spec.file, artifact}
    end)
  end

  defp propose_and_ratify(vehicle, spec, artifacts) do
    attrs = %{
      predicate: spec.predicate,
      value: spec.value,
      scope_date: spec[:scope_date],
      artifact_id: artifacts[spec.artifact].id
    }

    case Registry.propose_claim(vehicle, attrs) do
      {:ok, claim} ->
        {:ok, _admitted} = Registry.ratify_claim(claim.id)
        IO.puts("   claim #{spec.predicate} = #{inspect(spec.value)} → admitted")

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if Keyword.has_key?(errors, :content_hash) do
          ratify_existing(vehicle, spec)
        else
          raise "claim #{spec.predicate} rejected: #{inspect(changeset.errors)}"
        end
    end
  end

  # A re-run: the proposal already exists; make sure it is admitted.
  defp ratify_existing(vehicle, spec) do
    vehicle.id
    |> Registry.list_claims()
    |> Enum.find(fn %Claim{} = claim ->
      claim.method == :human and claim.predicate == spec.predicate and
        claim.value == normalize(spec.value) and claim.scope_date == spec[:scope_date]
    end)
    |> case do
      %Claim{state: :proposed, id: id} ->
        {:ok, _} = Registry.ratify_claim(id)
        IO.puts("   claim #{spec.predicate}: existing proposal ratified")

      %Claim{} ->
        IO.puts("   claim #{spec.predicate} = #{inspect(spec.value)}: already recorded")

      nil ->
        raise "duplicate content_hash but no matching claim for #{spec.predicate}"
    end
  end

  # Claim values round-trip through jsonb: atoms and dates come back as strings.
  defp normalize(value), do: value |> Jason.encode!() |> Jason.decode!()

  defp report(vehicle) do
    {:ok, vehicle} = Registry.fetch_vehicle(vehicle.id)

    IO.puts("   facts:")

    for {predicate, %{"value" => value, "status" => status}} <- Enum.sort(vehicle.facts) do
      IO.puts("     #{predicate}: #{inspect(value)} [#{status}]")
    end

    comparison = Registry.claim_comparison(vehicle.id)
    IO.puts("   comparison:")

    for %{predicate: predicate, status: status, claims: claims} <- comparison do
      IO.puts("     #{predicate}: #{status} (#{length(claims)} claims)")
    end

    :ok
  end
end
