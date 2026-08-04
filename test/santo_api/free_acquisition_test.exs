defmodule SantoApi.FreeAcquisitionTest do
  use SantoApi.DataCase, async: false

  import ExUnit.CaptureIO

  alias SantoApi.FreeAcquisition
  alias SantoApi.FreeAcquisition.Cohort
  alias SantoApi.Registry
  alias SantoApi.Registry.{Artifact, Claim, Vehicle}
  alias SantoApi.VpicFixtures

  test "materializes transaction pointers and runs vPIC only for VIN targets" do
    Req.Test.stub(SantoApi.Vpic, fn conn -> Req.Test.json(conn, VpicFixtures.cgt_response()) end)

    entries = [vin_entry(), chassis_entry()]
    report = FreeAcquisition.run(entries)

    assert report.targets == 2
    assert report.registered == 2
    assert report.transaction_claims == 3
    assert report.identity_claims == 9
    assert report.sales_ratified == 0
    assert report.provider_attempts == 1
    assert report.provider_successes == 1
    assert report.provider_skips == 1
    assert report.failures == []

    assert Repo.aggregate(Vehicle, :count) == 2
    assert Repo.aggregate(Artifact, :count) == 4
    assert Repo.aggregate(Claim, :count) > 3

    references = Repo.all(from(a in Artifact, where: a.kind == :reference))
    assert length(references) == 3
    assert Enum.all?(references, &is_nil(&1.payload))
    assert Enum.all?(references, &(&1.metadata["retention"] == "pointer_only"))

    sale_claims = Repo.all(from(c in Claim, where: c.predicate == "event.sale"))
    assert length(sale_claims) == 3
    assert Enum.all?(sale_claims, &(&1.state == :proposed))

    assert Enum.all?(Repo.all(Vehicle), &(Registry.timeline(&1.id) == []))
  end

  test "each transaction source proposes artifact-backed structured identity claims" do
    entry = chassis_entry()

    assert %{identity_claims: 6, failures: []} =
             FreeAcquisition.run([entry], acquire: false)

    identity_claims =
      Repo.all(
        from(c in Claim,
          where: c.predicate in ["identity.marque", "identity.model", "identity.model_year"],
          preload: [:artifact, :asserted_by_party]
        )
      )

    assert length(identity_claims) == 6
    assert Enum.all?(identity_claims, &(&1.state == :proposed))
    assert Enum.all?(identity_claims, &(&1.artifact_id == &1.artifact.id))

    assert identity_claims
           |> Enum.map(& &1.asserted_by_party.name)
           |> Enum.frequencies() == %{"Bring a Trailer" => 3, "RM Auctions" => 3}

    assert Enum.all?(identity_claims, fn claim ->
             claim.value in [
               "ferrari",
               1972,
               %{"code" => "dino_246_gts", "label" => "Dino 246 GTS"}
             ]
           end)

    vehicle = Repo.get_by!(Vehicle, identity_key: "chassis:ferrari:pre_vin:04268")

    assert vehicle.facts["identity.marque"] == %{
             "value" => "ferrari",
             "status" => "unverified"
           }

    assert vehicle.facts["identity.model"] == %{
             "value" => %{"code" => "dino_246_gts", "label" => "Dino 246 GTS"},
             "status" => "unverified"
           }

    assert vehicle.facts["identity.model_year"] == %{
             "value" => 1972,
             "status" => "unverified"
           }
  end

  test "same-source transactions retain identity evidence from each artifact without rerun duplicates" do
    entry =
      Cohort.load!()["entries"]
      |> Enum.find(&(&1["id"] == "air-1988-930-wp0eb0932js070215"))

    assert %{identity_claims: 6, failures: []} =
             FreeAcquisition.run([entry], acquire: false)

    identity_claims =
      Repo.all(
        from(c in Claim,
          where:
            c.method == :human and
              c.predicate in ["identity.marque", "identity.model", "identity.model_year"]
        )
      )

    assert identity_claims
           |> Enum.map(& &1.artifact_id)
           |> Enum.frequencies()
           |> Map.values()
           |> Enum.sort() == [3, 3]

    counts = {Repo.aggregate(Artifact, :count), Repo.aggregate(Claim, :count)}

    assert %{identity_claims: 6, failures: []} =
             FreeAcquisition.run([entry], acquire: false)

    assert {Repo.aggregate(Artifact, :count), Repo.aggregate(Claim, :count)} == counts
  end

  test "ratification admits only manifest sales and is idempotent on rerun" do
    entry = chassis_entry()

    assert %{sales_ratified: 2, sales_already_ratified: 0, failures: []} =
             FreeAcquisition.run([entry], acquire: false, ratify: true)

    assert %{sales_ratified: 0, sales_already_ratified: 2, failures: []} =
             FreeAcquisition.run([entry], acquire: false, ratify: true)

    assert Repo.aggregate(Vehicle, :count) == 1
    assert Repo.aggregate(Artifact, :count) == 2
    assert Repo.aggregate(Claim, :count) == 8

    vehicle = Repo.get_by!(Vehicle, identity_key: "chassis:ferrari:pre_vin:04268")
    timeline = Registry.timeline(vehicle.id)

    assert Enum.map(timeline, & &1.date) == [~D[2023-07-27], ~D[2014-01-17]]

    sales =
      Repo.all(from(c in Claim, where: c.predicate == "event.sale", preload: :ratified_by_party))

    assert Enum.all?(sales, &(&1.state == :admitted))
    assert Enum.all?(sales, &(&1.ratified_by_party.name == "Vin Santo"))
    assert Enum.all?(sales, &(not Map.has_key?(&1.value, "outcome")))

    identity =
      Repo.all(
        from(c in Claim,
          where: c.predicate in ["identity.marque", "identity.model", "identity.model_year"]
        )
      )

    assert Enum.all?(identity, &(&1.state == :proposed))
  end

  test "not-sold appearances persist the high bid while sold values remain canonical" do
    entry =
      Cohort.load!()["entries"]
      |> Enum.find(&(&1["id"] == "air-1987-930-wp0jb093xhs051078"))

    assert %{failures: []} = FreeAcquisition.run([entry], acquire: false)

    sales = Repo.all(from(c in Claim, where: c.predicate == "event.sale"))
    not_sold = Enum.find(sales, &(&1.value["outcome"] == "not_sold"))
    sold = Enum.find(sales, &(not Map.has_key?(&1.value, "outcome")))

    assert not_sold.value == %{
             "venue" => "Mecum Auctions",
             "price" => 55_000,
             "currency" => "USD",
             "outcome" => "not_sold"
           }

    assert sold.value["price"] == 65_000
  end

  test "a secondary index asserts the result without becoming the sale venue" do
    entry =
      Cohort.load!()["entries"]
      |> Enum.find(&(&1["id"] == "air-1996-993-wp0aa2992ts322677"))

    assert %{transaction_claims: 2, failures: []} =
             FreeAcquisition.run([entry], acquire: false)

    broad_arrow_claim =
      Claim
      |> where([c], c.predicate == "event.sale")
      |> Repo.all()
      |> Enum.find(&(&1.value["venue"] == "Broad Arrow Auctions"))
      |> Repo.preload(:asserted_by_party)

    assert broad_arrow_claim.asserted_by_party.name == "Hagerty Valuation Tools"
  end

  test "the Mix task dry run touches neither Postgres nor providers" do
    output =
      capture_io(fn ->
        Mix.Tasks.Santo.Acquire.Free.run(["--dry-run", "--cohort", "limited_gt", "--limit", "2"])
      end)

    assert output =~ "dry run: 2 targets"
    assert output =~ "auction events: 2 (2 sold, 0 not sold)"
    assert Repo.aggregate(Vehicle, :count) == 0
    assert Repo.aggregate(Artifact, :count) == 0
  end

  test "the Mix task ratifies manifest sales only when the operator flag is present" do
    output =
      capture_io(fn ->
        Mix.Tasks.Santo.Acquire.Free.run([
          "--cohort",
          "vintage_ferrari",
          "--limit",
          "1",
          "--skip-providers",
          "--ratify-sales"
        ])
      end)

    assert output =~ "sales ratified: 1 newly admitted, 0 already admitted"

    sale = Repo.one!(from(c in Claim, where: c.predicate == "event.sale"))
    assert sale.state == :admitted

    identity =
      Repo.all(
        from(c in Claim,
          where: c.predicate in ["identity.marque", "identity.model", "identity.model_year"]
        )
      )

    assert length(identity) == 3
    assert Enum.all?(identity, &(&1.state == :proposed))
  end

  defp vin_entry do
    Cohort.load!()["entries"]
    |> Enum.find(&(&1["id"] == "gt-2005-carrera-gt-wp0ca298x5l001256"))
  end

  defp chassis_entry do
    Cohort.load!()["entries"]
    |> Enum.find(&(&1["id"] == "ferrari-1972-dino-04268"))
  end
end
