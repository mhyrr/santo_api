defmodule Mix.Tasks.Santo.Acquire.Free do
  @shortdoc "Materialize the free transaction-weighted collector-car cohort"

  @moduledoc """
  Loads the checked-in free-acquisition manifest, creates source-reference and
  proposed sale claims, then runs every applicable free provider.

      mix santo.acquire.free
      mix santo.acquire.free --skip-providers
      mix santo.acquire.free --dry-run
      mix santo.acquire.free --cohort limited_gt --limit 5

  The task never copies marketplace pages or media. `--dry-run` validates and
  summarizes the manifest without starting the application, touching Postgres,
  or making network requests.
  """

  use Mix.Task

  alias SantoApi.FreeAcquisition
  alias SantoApi.FreeAcquisition.Cohort
  alias SantoApi.Repo

  @switches [dry_run: :boolean, skip_providers: :boolean, cohort: :string, limit: :integer]

  @impl Mix.Task
  def run(args) do
    opts = parse!(args)
    manifest = Cohort.load!()
    entries = Cohort.select(manifest, opts)
    summary = Cohort.summary(entries)

    if opts[:dry_run] do
      print_summary("dry run", summary)
      print_price_paths(entries)
    else
      Mix.Task.run("app.start")
      ensure_migrated!()
      print_summary("cohort", summary)
      print_price_paths(entries)
      report = FreeAcquisition.run(entries, acquire: !opts[:skip_providers])
      print_report(report)

      if report.failures != [] do
        Mix.raise("free acquisition completed with #{length(report.failures)} failure(s)")
      end
    end
  end

  defp ensure_migrated! do
    pending = Enum.filter(Ecto.Migrator.migrations(Repo), &match?({:down, _, _}, &1))

    if pending != [] do
      versions =
        Enum.map_join(pending, ", ", fn {:down, version, name} -> "#{version}_#{name}" end)

      Mix.raise(
        "database has pending migrations (#{versions}); run `mix ecto.migrate` before acquisition"
      )
    end
  end

  defp parse!(args) do
    case OptionParser.parse(args, strict: @switches) do
      {opts, [], []} -> validate_options!(opts)
      {_opts, rest, invalid} -> Mix.raise("invalid arguments: #{inspect(rest ++ invalid)}")
    end
  end

  defp validate_options!(opts) do
    cohort = opts[:cohort]
    limit = opts[:limit]

    cond do
      cohort && cohort not in Cohort.cohorts() ->
        Mix.raise(
          "unknown cohort #{inspect(cohort)}; choose #{Enum.join(Cohort.cohorts(), ", ")}"
        )

      limit && limit < 1 ->
        Mix.raise("--limit must be positive")

      true ->
        opts
    end
  end

  defp print_summary(label, summary) do
    Mix.shell().info("#{label}: #{summary.count} targets")

    for {cohort, count} <- Enum.sort(summary.cohorts) do
      Mix.shell().info("  #{cohort}: #{count}")
    end

    Mix.shell().info("  identities: #{summary.vin_count} VIN, #{summary.chassis_count} chassis")

    Mix.shell().info(
      "  auction events: #{summary.transaction_count} " <>
        "(#{summary.sold_count} sold, #{summary.not_sold_count} not sold)"
    )

    Mix.shell().info(
      "  longitudinal: #{summary.repeat_appearance_vehicle_count} repeat appearances, " <>
        "#{summary.repeat_sale_vehicle_count} repeat sales, " <>
        "#{summary.cross_venue_vehicle_count} cross-venue"
    )

    venues =
      summary.venues
      |> Enum.sort_by(fn {venue, count} -> {-count, venue} end)
      |> Enum.map_join(", ", fn {venue, count} -> "#{venue} #{count}" end)

    Mix.shell().info("  venues: #{venues}")
  end

  defp print_price_paths(entries) do
    for path <- Cohort.price_paths(entries) do
      transactions = Enum.map_join(path.transactions, " -> ", &format_transaction/1)
      Mix.shell().info("  #{path.id}: #{transactions}")
    end
  end

  defp format_transaction(transaction) do
    result =
      if transaction["outcome"] == "sold",
        do: "sold",
        else: "high bid, not sold"

    "#{transaction["date"]} #{transaction["venue"]} " <>
      "#{transaction["currency"]} #{format_integer(transaction["price"])} #{result}"
  end

  defp format_integer(integer) do
    integer
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end

  defp print_report(report) do
    Mix.shell().info(
      "free acquisition: #{report.registered}/#{report.targets} targets materialized"
    )

    Mix.shell().info("  transaction claims: #{report.transaction_claims}")

    Mix.shell().info(
      "  providers: #{report.provider_successes}/#{report.provider_attempts} succeeded, " <>
        "#{report.provider_skips} skipped"
    )

    for failure <- report.failures do
      Mix.shell().error("  #{failure.id} [#{failure.stage}]: #{failure.reason}")
    end
  end
end
