defmodule Mix.Tasks.Santo.Nhtsa.Refresh do
  @shortdoc "Refresh the local NHTSA recalls and manufacturer-communications corpus"

  @moduledoc """
  Downloads official NHTSA bulk archives with Req, preserves each release, and
  imports its model/year lookup rows.

      mix santo.nhtsa.refresh
      mix santo.nhtsa.refresh --dataset recall_campaigns
      mix santo.nhtsa.refresh --dataset technical_bulletins

  VIN acquisitions never download these archives; they query the latest local
  releases imported by this task.
  """

  use Mix.Task

  alias SantoApi.Nhtsa.Corpus
  alias SantoApi.Repo

  @switches [dataset: :string]

  @impl Mix.Task
  def run(args) do
    dataset = parse!(args)
    Mix.Task.run("app.start")
    ensure_migrated!()

    results = Corpus.refresh(dataset)

    Enum.each(results, fn
      {:ok, disposition, release} ->
        Mix.shell().info(
          "#{release.dataset}/#{release.source_key}: #{disposition} " <>
            "#{release.record_count} records, #{release.malformed_row_count} malformed"
        )

      {:error, reason} ->
        Mix.shell().error("NHTSA refresh failed: #{inspect(reason)}")
    end)

    failures = Enum.count(results, &match?({:error, _reason}, &1))
    if failures > 0, do: Mix.raise("NHTSA refresh completed with #{failures} failure(s)")
  end

  defp parse!(args) do
    case OptionParser.parse(args, strict: @switches) do
      {opts, [], []} -> parse_dataset(opts[:dataset])
      {_opts, rest, invalid} -> Mix.raise("invalid arguments: #{inspect(rest ++ invalid)}")
    end
  end

  defp parse_dataset(nil), do: :all
  defp parse_dataset("recall_campaigns"), do: :recall_campaigns
  defp parse_dataset("technical_bulletins"), do: :technical_bulletins

  defp parse_dataset(dataset) do
    Mix.raise(
      "unknown dataset #{inspect(dataset)}; choose recall_campaigns or technical_bulletins"
    )
  end

  defp ensure_migrated! do
    pending = Enum.filter(Ecto.Migrator.migrations(Repo), &match?({:down, _, _}, &1))

    if pending != [] do
      versions =
        Enum.map_join(pending, ", ", fn {:down, version, name} -> "#{version}_#{name}" end)

      Mix.raise("database has pending migrations (#{versions}); run `mix ecto.migrate` first")
    end
  end
end
