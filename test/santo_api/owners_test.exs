defmodule SantoApi.OwnersTest do
  @moduledoc """
  The owner side of the house: who a user is in the ledger, which cars they
  steward, and what they may assert about them.
  """

  # Ingest-heavy and party-creating: two sandbox transactions inserting the
  # same VINs and parties in opposite order deadlock (CLAUDE.md).
  use SantoApi.DataCase, async: false

  import SantoApi.AccountsFixtures

  alias SantoApi.Owners
  alias SantoApi.Registry

  describe "ensure_party/2" do
    test "mints an owner party from a handle and links it to the user" do
      user = user_fixture(%{handle: "mhyrr"})

      assert {:ok, party} = Owners.ensure_party(user, "mhyrr")
      assert party.name == "mhyrr"
      assert party.kind == :owner
      assert Owners.party(user).id == party.id
    end

    test "is idempotent — a second call returns the party already linked" do
      user = user_fixture(%{handle: "mhyrr"})

      assert {:ok, party} = Owners.ensure_party(user, "mhyrr")
      assert {:ok, ^party} = Owners.ensure_party(user, "mhyrr")
    end

    test "refuses a rename, because the handle is hashed into every claim" do
      user = user_fixture(%{handle: "mhyrr"})

      assert {:ok, _party} = Owners.ensure_party(user, "mhyrr")
      assert {:error, :handle_immutable} = Owners.ensure_party(user, "someone-else")
    end

    test "normalizes case and surrounding space before it becomes permanent" do
      user = user_fixture(%{handle: "mhyrr"})

      assert {:ok, party} = Owners.ensure_party(user, "  MHyrr  ")
      assert party.name == "mhyrr"
    end

    test "rejects a handle that cannot be read back off a page" do
      user = legacy_user_fixture()

      for handle <- [
            "ab",
            "has spaces",
            "trailing-",
            "-leading",
            "no@sign",
            String.duplicate("x", 33)
          ] do
        assert {:error, changeset} = Owners.ensure_party(user, handle)
        assert %Ecto.Changeset{} = changeset
        refute changeset.valid?
      end
    end

    test "refuses a handle another owner already holds" do
      taken = user_fixture(%{handle: "mhyrr"})
      assert {:ok, _party} = Owners.ensure_party(taken, "mhyrr")

      assert {:error, changeset} = Owners.ensure_party(legacy_user_fixture(), "mhyrr")
      assert "has already been taken" in errors_on(changeset).name
    end

    test "leaves the user unlinked when the handle is refused" do
      user = legacy_user_fixture()

      assert {:error, _changeset} = Owners.ensure_party(user, "ab")
      assert Owners.party(user) == nil
    end

    test "a reserved user mints only under its reservation (§9.1)" do
      user = user_fixture()

      assert {:error, :handle_immutable} = Owners.ensure_party(user, "different-name")
      assert Owners.party(user) == nil
    end
  end

  describe "party/1" do
    test "is nil until the user has asserted anything" do
      assert Owners.party(user_fixture()) == nil
    end
  end

  describe "handles and the ledger" do
    test "the handle is what a claim is attributed to" do
      user = user_fixture(%{handle: "mhyrr"})
      {:ok, party} = Owners.ensure_party(user, "mhyrr")
      {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")

      {:ok, claim} =
        Registry.propose_claim(vehicle, party, %{
          "predicate" => "observation.mileage",
          "value" => 41_660,
          "scope_date" => "2026-08-02"
        })

      assert claim.asserted_by_party_id == party.id
      assert Registry.timeline(vehicle.id) == []

      {:ok, _claim} = Registry.ratify_claim(claim.id, party)
      assert [entry] = Registry.timeline(vehicle.id)
      assert entry.party == "mhyrr"
    end
  end
end
