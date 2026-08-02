defmodule SantoApi.FreeAcquisition do
  @moduledoc """
  Materializes the free collector-car cohort through the Registry.

  Marketplace pages enter only as reference artifacts and proposed sale facts.
  VIN targets are then checked against the currently registered free providers.
  """

  alias SantoApi.Registry
  alias SantoApi.Registry.{Artifact, Claim, Vehicle}
  alias SantoApi.Repo

  def run(entries, opts \\ []) when is_list(entries) do
    acquire? = Keyword.get(opts, :acquire, true)

    entries
    |> Enum.reduce(empty_report(), &run_entry(&1, &2, acquire?))
    |> Map.update!(:failures, &Enum.reverse/1)
  end

  defp empty_report do
    %{
      targets: 0,
      registered: 0,
      transaction_claims: 0,
      provider_attempts: 0,
      provider_successes: 0,
      provider_skips: 0,
      provider_failures: 0,
      failures: []
    }
  end

  defp run_entry(entry, report, acquire?) do
    report = Map.update!(report, :targets, &(&1 + 1))

    case persist_target(entry) do
      {:ok, {%Vehicle{} = vehicle, transaction_count}} ->
        report
        |> Map.update!(:registered, &(&1 + 1))
        |> Map.update!(:transaction_claims, &(&1 + transaction_count))
        |> acquire_free_provider(entry, vehicle, acquire?)

      {:error, reason} ->
        add_failure(report, entry, :target, reason)
    end
  end

  defp persist_target(entry) do
    Repo.transaction(fn ->
      with {:ok, vehicle} <- register(entry["identity"]),
           {:ok, transaction_count} <- persist_transactions(vehicle, entry) do
        {vehicle, transaction_count}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp persist_transactions(vehicle, entry) do
    entry["transactions"]
    |> Enum.reduce_while({:ok, 0}, fn transaction, {:ok, count} ->
      with {:ok, %Artifact{} = artifact} <- reference_artifact(vehicle, entry, transaction),
           {:ok, %Claim{}} <- sale_claim(vehicle, artifact, transaction) do
        {:cont, {:ok, count + 1}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp register(%{"kind" => "vin", "value" => vin}) do
    case Registry.ingest(vin) do
      {:ok, %Vehicle{} = vehicle} ->
        {:ok, vehicle}

      {:error, %Santo.Invalid{} = invalid} ->
        if vin |> String.trim() |> String.upcase() |> String.starts_with?("ZFF") do
          Registry.register_vin(:ferrari, vin)
        else
          {:error, invalid}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp register(%{
         "kind" => "chassis",
         "marque" => "ferrari",
         "era" => "pre_vin",
         "value" => number
       }),
       do: Registry.register_chassis(:ferrari, :pre_vin, number)

  defp reference_artifact(vehicle, entry, transaction) do
    source_party = source_party(transaction)

    Registry.create_reference_artifact(vehicle, source_party, %{
      source_url: transaction["url"],
      metadata: %{
        "access_class" => "public_web",
        "cohort" => entry["cohort"],
        "manifest_id" => entry["id"],
        "retention" => "pointer_only",
        "rights_profile" => "public-pointer-only-v1"
      }
    })
  end

  defp sale_claim(vehicle, artifact, transaction) do
    source_party = source_party(transaction)

    value = %{
      "venue" => transaction["venue"],
      "price" => transaction["price"],
      "currency" => transaction["currency"]
    }

    value =
      if transaction["outcome"] == "not_sold",
        do: Map.put(value, "outcome", "not_sold"),
        else: value

    attrs = %{
      predicate: "event.sale",
      value: value,
      scope_date: Date.from_iso8601!(transaction["date"]),
      artifact_id: artifact.id
    }

    case Registry.propose_claim(vehicle, source_party, attrs) do
      {:ok, %Claim{} = claim} -> {:ok, claim}
      {:error, changeset} -> existing_sale_claim(vehicle, source_party, attrs, changeset)
    end
  end

  defp existing_sale_claim(vehicle, source_party, attrs, changeset) do
    if Keyword.has_key?(changeset.errors, :content_hash) do
      vehicle.id
      |> Registry.list_claims()
      |> Enum.find(fn claim ->
        claim.predicate == attrs.predicate and claim.value == attrs.value and
          claim.scope_date == attrs.scope_date and
          claim.asserted_by_party_id == source_party.id
      end)
      |> case do
        %Claim{} = claim -> {:ok, claim}
        nil -> {:error, :duplicate_sale_claim_not_found}
      end
    else
      {:error, changeset}
    end
  end

  defp source_party(transaction) do
    Registry.ensure_party(transaction["source"] || transaction["venue"], :vendor)
  end

  defp acquire_free_provider(report, _entry, _vehicle, false),
    do: Map.update!(report, :provider_skips, &(&1 + 1))

  defp acquire_free_provider(report, %{"identity" => %{"kind" => "chassis"}}, _vehicle, true),
    do: Map.update!(report, :provider_skips, &(&1 + 1))

  defp acquire_free_provider(report, entry, vehicle, true) do
    report = Map.update!(report, :provider_attempts, &(&1 + 1))

    case Registry.ingest_vpic(vehicle) do
      {:ok, %Artifact{}} ->
        Map.update!(report, :provider_successes, &(&1 + 1))

      {:error, reason} ->
        report
        |> Map.update!(:provider_failures, &(&1 + 1))
        |> add_failure(entry, :nhtsa_vpic, reason)
    end
  end

  defp add_failure(report, entry, stage, reason) do
    failure = %{id: entry["id"], stage: stage, reason: inspect(reason)}
    Map.update!(report, :failures, &[failure | &1])
  end
end
