defmodule SantoApi.RegistryUnboxedTest do
  @moduledoc """
  Registry write paths exercised OUTSIDE the Ecto sandbox transaction.

  The sandbox wraps every other test in a transaction, and that is exactly what
  hid TK-011: `Repo.insert(changeset, mode: :savepoint)` needs an open
  transaction, so the suite stayed green while all three corpus scripts died on
  `DBConnection.TransactionError`. These tests take a raw connection instead —
  the same conditions `mix run priv/corpus/*.exs` runs under.

  Nothing rolls back here, so each test cleans up the rows it made.
  """
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias SantoApi.Registry
  alias SantoApi.Registry.{Artifact, Claim, EvidenceRequest, Vehicle}
  alias SantoApi.Repo

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    on_exit(fn -> Sandbox.unboxed_run(Repo, &delete_test_vehicles/0) end)
    :ok
  end

  test "propose_claim/2 works with no surrounding transaction" do
    refute Repo.in_transaction?()

    {:ok, vehicle} = Registry.register_chassis(:porsche, :nine_three, chassis_number())

    {:ok, claim} =
      Registry.propose_claim(vehicle, %{
        predicate: "build.paint_code",
        value: %{"code" => "226", "label" => "Linden Green"}
      })

    assert claim.state == :proposed
    assert {:ok, admitted} = Registry.ratify_claim(claim.id)
    assert admitted.state == :admitted
  end

  test "propose_claim/2 outside a transaction still reports a duplicate as a changeset error" do
    {:ok, vehicle} = Registry.register_chassis(:porsche, :nine_three, chassis_number())
    attrs = %{predicate: "identity.marque", value: "porsche"}

    {:ok, _claim} = Registry.propose_claim(vehicle, attrs)

    assert {:error, %Ecto.Changeset{} = changeset} = Registry.propose_claim(vehicle, attrs)
    assert Keyword.has_key?(changeset.errors, :content_hash)
  end

  # The savepoint's original intent: a caller recovering a duplicate claim inside
  # a larger transaction must not have that transaction aborted by the constraint
  # error. Guards against "fixing" TK-011 by dropping the savepoint outright.
  test "a duplicate proposal inside a caller's transaction leaves that transaction usable" do
    {:ok, vehicle} = Registry.register_chassis(:porsche, :nine_three, chassis_number())
    attrs = %{predicate: "identity.marque", value: "porsche"}
    {:ok, _claim} = Registry.propose_claim(vehicle, attrs)

    {:ok, count} =
      Repo.transaction(fn ->
        {:error, %Ecto.Changeset{}} = Registry.propose_claim(vehicle, attrs)
        Repo.aggregate(from(c in Claim, where: c.vehicle_id == ^vehicle.id), :count)
      end)

    assert count == 1
  end

  defp chassis_number, do: "TK011-#{System.unique_integer([:positive])}"

  defp delete_test_vehicles do
    ids =
      Repo.all(from(v in Vehicle, where: like(v.identity_key, "%TK011-%"), select: v.id))

    for schema <- [Claim, EvidenceRequest, Artifact] do
      Repo.delete_all(from(r in schema, where: r.vehicle_id in ^ids))
    end

    Repo.delete_all(from(v in Vehicle, where: v.id in ^ids))
  end
end
