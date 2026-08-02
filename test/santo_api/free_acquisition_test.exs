defmodule SantoApi.FreeAcquisitionTest do
  use SantoApi.DataCase, async: false

  import ExUnit.CaptureIO

  alias SantoApi.FreeAcquisition
  alias SantoApi.FreeAcquisition.Cohort
  alias SantoApi.Registry.{Artifact, Claim, Vehicle}
  alias SantoApi.VpicFixtures

  test "materializes transaction pointers and runs vPIC only for VIN targets" do
    Req.Test.stub(SantoApi.Vpic, fn conn -> Req.Test.json(conn, VpicFixtures.cgt_response()) end)

    entries = [vin_entry(), chassis_entry()]
    report = FreeAcquisition.run(entries)

    assert report.targets == 2
    assert report.registered == 2
    assert report.transaction_claims == 3
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
  end

  test "re-running target materialization deduplicates references and sale claims" do
    entry = chassis_entry()

    assert %{registered: 1, provider_skips: 1} = FreeAcquisition.run([entry], acquire: false)
    assert %{registered: 1, provider_skips: 1} = FreeAcquisition.run([entry], acquire: false)

    assert Repo.aggregate(Vehicle, :count) == 1
    assert Repo.aggregate(Artifact, :count) == 2
    assert Repo.aggregate(Claim, :count) == 2
  end

  test "a secondary index asserts the result without becoming the sale venue" do
    entry =
      Cohort.load!()["entries"]
      |> Enum.find(&(&1["id"] == "air-1996-993-wp0aa2992ts322677"))

    assert %{transaction_claims: 2, failures: []} =
             FreeAcquisition.run([entry], acquire: false)

    broad_arrow_claim =
      Claim
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

  defp vin_entry do
    Cohort.load!()["entries"]
    |> Enum.find(&(&1["id"] == "gt-2005-carrera-gt-wp0ca298x5l001256"))
  end

  defp chassis_entry do
    Cohort.load!()["entries"]
    |> Enum.find(&(&1["id"] == "ferrari-1972-dino-04268"))
  end
end
