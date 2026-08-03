defmodule SantoApi.FreeAcquisition.CohortTest do
  use ExUnit.Case, async: true

  alias SantoApi.FreeAcquisition.Cohort

  test "loads a balanced, unique 30-car transaction cohort" do
    assert {:ok, manifest} = Cohort.load()
    entries = manifest["entries"]

    assert Cohort.summary(entries) == %{
             count: 30,
             cohorts: %{
               "air_cooled_911" => 10,
               "limited_gt" => 10,
               "vintage_ferrari" => 10
             },
             vin_count: 20,
             chassis_count: 10,
             transaction_count: 40,
             sold_count: 37,
             not_sold_count: 3,
             repeat_appearance_vehicle_count: 10,
             repeat_sale_vehicle_count: 7,
             cross_venue_vehicle_count: 6,
             venues: %{
               "Bring a Trailer" => 34,
               "Broad Arrow Auctions" => 1,
               "Mecum Auctions" => 3,
               "RM Auctions" => 2
             }
           }

    assert length(Enum.uniq_by(entries, & &1["id"])) == 30

    assert Enum.all?(entries, fn entry ->
             is_binary(entry["marque"]) and
               match?(
                 %{"code" => code, "label" => label} when is_binary(code) and is_binary(label),
                 entry["model"]
               ) and
               Enum.all?(entry["transactions"], &(&1["url"] =~ "https://"))
           end)

    assert length(Cohort.price_paths(entries)) == 10
  end

  test "selects one cohort and applies a limit" do
    manifest = Cohort.load!()

    selected = Cohort.select(manifest, cohort: "vintage_ferrari", limit: 3)

    assert length(selected) == 3
    assert Enum.all?(selected, &(&1["cohort"] == "vintage_ferrari"))
  end

  test "requires explicit marque plus model code and label" do
    manifest = Cohort.load!()

    invalid_entries = [
      Map.delete(hd(manifest["entries"]), "marque"),
      put_in(hd(manifest["entries"]), ["model", "label"], nil)
    ]

    for invalid_entry <- invalid_entries do
      invalid_manifest = put_in(manifest, ["entries", Access.at(0)], invalid_entry)
      path = temporary_manifest(invalid_manifest)

      assert {:error, {:entry, 1, :invalid_shape}} = Cohort.load(path)
    end
  end

  defp temporary_manifest(manifest) do
    path =
      Path.join(
        System.tmp_dir!(),
        "santo-free-acquisition-#{System.unique_integer([:positive])}.json"
      )

    File.write!(path, Jason.encode!(manifest))
    on_exit(fn -> File.rm(path) end)
    path
  end
end
