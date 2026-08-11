defmodule Mix.Tasks.Santo.Demo.Seed do
  @shortdoc "Seed the fictional DMV review garage"

  @moduledoc """
  Creates a re-runnable local review dataset using public DMV event coordinates
  and fictional member activity.

      mix santo.demo.seed

  This task is blocked in production. It does not run from `mix ecto.setup`.
  """

  use Mix.Task

  alias SantoApi.Demo.DmvSeed
  alias SantoApi.Repo

  @impl Mix.Task
  def run([]) do
    if Mix.env() == :prod, do: Mix.raise("the DMV demo dataset cannot be seeded in production")

    Mix.Task.run("app.start")
    ensure_migrated!()

    summary = DmvSeed.run!()

    Mix.shell().info("DMV demo garage ready")

    if summary.removed_placeholder_media > 0 do
      Mix.shell().info(
        "  removed #{summary.removed_placeholder_media} retired placeholder media link(s)"
      )
    end

    Enum.each(summary.cars, fn {_key, car} ->
      Mix.shell().info("  /v/#{car.public_id} · @#{car.handle}")
    end)

    Enum.each(summary.events, fn {_key, event} ->
      Mix.shell().info(
        "  /events/#{event.public_id} · #{event.title} · #{event.participation_count} account(s)"
      )
    end)
  end

  def run(args), do: Mix.raise("unexpected arguments: #{Enum.join(args, " ")}")

  defp ensure_migrated! do
    pending = Enum.filter(Ecto.Migrator.migrations(Repo), &match?({:down, _, _}, &1))

    if pending != [] do
      versions =
        Enum.map_join(pending, ", ", fn {:down, version, name} -> "#{version}_#{name}" end)

      Mix.raise("database has pending migrations (#{versions}); run `mix ecto.migrate` first")
    end
  end
end
