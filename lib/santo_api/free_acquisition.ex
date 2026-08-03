defmodule SantoApi.FreeAcquisition do
  @moduledoc """
  Materializes the free collector-car cohort through the Registry.

  Marketplace pages enter only as reference artifacts with proposed identity
  and sale claims. An explicit operator option may ratify manifest sales; VIN
  targets are then checked against the currently registered free providers.
  """

  alias SantoApi.Registry
  alias SantoApi.Registry.{Artifact, Claim, Vehicle}
  alias SantoApi.Repo

  def run(entries, opts \\ []) when is_list(entries) do
    acquire? = Keyword.get(opts, :acquire, true)
    ratify_sales? = Keyword.get(opts, :ratify, false) == true

    entries
    |> Enum.reduce(empty_report(), &run_entry(&1, &2, acquire?, ratify_sales?))
    |> Map.update!(:failures, &Enum.reverse/1)
  end

  defp empty_report do
    %{
      targets: 0,
      registered: 0,
      transaction_claims: 0,
      identity_claims: 0,
      sales_ratified: 0,
      sales_already_ratified: 0,
      provider_attempts: 0,
      provider_successes: 0,
      provider_skips: 0,
      provider_failures: 0,
      failures: []
    }
  end

  defp run_entry(entry, report, acquire?, ratify_sales?) do
    report = Map.update!(report, :targets, &(&1 + 1))

    case persist_target(entry, ratify_sales?) do
      {:ok, {%Vehicle{} = vehicle, counts}} ->
        report
        |> Map.update!(:registered, &(&1 + 1))
        |> add_counts(counts)
        |> acquire_free_provider(entry, vehicle, acquire?)

      {:error, reason} ->
        add_failure(report, entry, :target, reason)
    end
  end

  defp add_counts(report, counts) do
    Enum.reduce(counts, report, fn {key, count}, report ->
      Map.update!(report, key, &(&1 + count))
    end)
  end

  defp persist_target(entry, ratify_sales?) do
    Repo.transaction(fn ->
      with {:ok, vehicle} <- register(entry["identity"]),
           {:ok, counts} <- persist_transactions(vehicle, entry, ratify_sales?) do
        {vehicle, counts}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp persist_transactions(vehicle, entry, ratify_sales?) do
    entry["transactions"]
    |> Enum.reduce_while({:ok, transaction_counts()}, fn transaction, {:ok, counts} ->
      source_party = source_party(transaction)

      with {:ok, %Artifact{} = artifact} <-
             reference_artifact(vehicle, source_party, entry, transaction),
           {:ok, identity_count} <- identity_claims(vehicle, source_party, artifact, entry),
           {:ok, %Claim{} = sale} <- sale_claim(vehicle, source_party, artifact, transaction),
           {:ok, ratification} <- maybe_ratify_sale(sale, ratify_sales?) do
        counts =
          counts
          |> Map.update!(:transaction_claims, &(&1 + 1))
          |> Map.update!(:identity_claims, &(&1 + identity_count))
          |> count_ratification(ratification)

        {:cont, {:ok, counts}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp transaction_counts do
    %{transaction_claims: 0, identity_claims: 0, sales_ratified: 0, sales_already_ratified: 0}
  end

  defp count_ratification(counts, :not_requested), do: counts
  defp count_ratification(counts, :ratified), do: Map.update!(counts, :sales_ratified, &(&1 + 1))

  defp count_ratification(counts, :already_ratified),
    do: Map.update!(counts, :sales_already_ratified, &(&1 + 1))

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

  defp reference_artifact(vehicle, source_party, entry, transaction) do
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

  defp identity_claims(vehicle, source_party, artifact, entry) do
    claims = [
      {"identity.marque", entry["marque"]},
      {"identity.model", entry["model"]},
      {"identity.model_year", entry["model_year"]}
    ]

    Enum.reduce_while(claims, {:ok, 0}, fn {predicate, value}, {:ok, count} ->
      attrs = %{predicate: predicate, value: value, artifact_id: artifact.id}

      case propose_claim(vehicle, source_party, attrs, distinct_by_artifact: true) do
        {:ok, %Claim{}} -> {:cont, {:ok, count + 1}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp sale_claim(vehicle, source_party, artifact, transaction) do
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

    propose_claim(vehicle, source_party, attrs, [])
  end

  defp propose_claim(vehicle, source_party, attrs, opts) do
    case Registry.propose_claim(vehicle, source_party, attrs, opts) do
      {:ok, %Claim{} = claim} -> {:ok, claim}
      {:error, changeset} -> existing_claim(vehicle, source_party, attrs, opts, changeset)
    end
  end

  defp existing_claim(vehicle, source_party, attrs, opts, changeset) do
    if Keyword.has_key?(changeset.errors, :content_hash) do
      vehicle.id
      |> Registry.list_claims()
      |> Enum.find(fn claim ->
        claim.predicate == attrs.predicate and claim.value == attrs.value and
          claim.scope_date == Map.get(attrs, :scope_date) and
          claim.asserted_by_party_id == source_party.id and
          (not opts[:distinct_by_artifact] or claim.artifact_id == attrs.artifact_id)
      end)
      |> case do
        %Claim{} = claim -> {:ok, claim}
        nil -> {:error, :duplicate_claim_not_found}
      end
    else
      {:error, changeset}
    end
  end

  defp maybe_ratify_sale(_claim, false), do: {:ok, :not_requested}

  defp maybe_ratify_sale(%Claim{predicate: "event.sale", state: :admitted}, true),
    do: {:ok, :already_ratified}

  defp maybe_ratify_sale(%Claim{predicate: "event.sale"} = claim, true) do
    case Registry.ratify_claim(claim.id, Registry.vin_santo_party()) do
      {:ok, %Claim{state: :admitted}} -> {:ok, :ratified}
      {:error, {:not_proposed, :admitted}} -> {:ok, :already_ratified}
      {:error, reason} -> {:error, reason}
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
