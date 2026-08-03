defmodule SantoApi.RegistryTimelineTest do
  @moduledoc """
  The logbook as the page reads it (owner_surface §6): claims sharing an
  `entry_ref` presented as one entry, newest first.
  """
  use SantoApi.DataCase, async: false

  alias SantoApi.Registry

  @nine_three "WP0ZZZ99ZTS392124"

  defp admit(vehicle, attrs) do
    {:ok, claim} = Registry.propose_claim(vehicle, attrs)
    {:ok, admitted} = Registry.ratify_claim(claim.id)
    admitted
  end

  defp fuel(volume), do: %{"volume" => volume, "unit" => "gal"}

  test "claims born of one entry present as one entry" do
    {:ok, vehicle} = Registry.ingest(@nine_three)
    entry_ref = Registry.new_entry_ref()

    admit(vehicle, %{
      predicate: "event.fuel",
      value: fuel("13.1"),
      scope_date: ~D[2026-03-01],
      entry_ref: entry_ref
    })

    admit(vehicle, %{
      predicate: "observation.mileage",
      value: 51_200,
      scope_date: ~D[2026-03-01],
      entry_ref: entry_ref
    })

    assert [entry] = Registry.timeline(vehicle.id)
    assert entry.entry_ref == entry_ref
    assert entry.date == ~D[2026-03-01]

    assert Enum.map(entry.claims, & &1.predicate) |> Enum.sort() ==
             ["event.fuel", "observation.mileage"]
  end

  test "two entries on one date stay two entries" do
    {:ok, vehicle} = Registry.ingest(@nine_three)
    date = ~D[2026-03-01]

    for volume <- ["10.0", "11.0"] do
      admit(vehicle, %{
        predicate: "event.fuel",
        value: fuel(volume),
        scope_date: date,
        entry_ref: Registry.new_entry_ref()
      })
    end

    assert length(Registry.timeline(vehicle.id)) == 2
  end

  test "a claim with no entry_ref stands on its own — the corpus is all of these" do
    {:ok, vehicle} = Registry.ingest(@nine_three)

    admit(vehicle, %{
      predicate: "event.service",
      value: %{"summary" => "annual", "performer" => "the shop"},
      scope_date: ~D[2025-05-05]
    })

    admit(vehicle, %{
      predicate: "event.note",
      value: %{"text" => "washed it"},
      scope_date: ~D[2025-05-05]
    })

    assert length(Registry.timeline(vehicle.id)) == 2
  end

  test "newest first" do
    {:ok, vehicle} = Registry.ingest(@nine_three)

    for date <- [~D[2024-01-01], ~D[2026-01-01], ~D[2025-01-01]] do
      admit(vehicle, %{
        predicate: "event.note",
        value: %{"text" => "note #{date}"},
        scope_date: date,
        entry_ref: Registry.new_entry_ref()
      })
    end

    assert Enum.map(Registry.timeline(vehicle.id), & &1.date) ==
             [~D[2026-01-01], ~D[2025-01-01], ~D[2024-01-01]]
  end

  test "only admitted claims reach the page — proposed is not the record" do
    {:ok, vehicle} = Registry.ingest(@nine_three)

    {:ok, _proposed} =
      Registry.propose_claim(vehicle, %{
        predicate: "event.note",
        value: %{"text" => "unconfirmed"},
        scope_date: ~D[2026-01-01]
      })

    assert Registry.timeline(vehicle.id) == []
  end

  test "private claims stay off the public timeline but stay in the ledger" do
    {:ok, vehicle} = Registry.ingest(@nine_three)

    claim =
      admit(vehicle, %{
        predicate: "event.note",
        value: %{"text" => "where I keep it"},
        scope_date: ~D[2026-01-01]
      })

    assert length(Registry.timeline(vehicle.id)) == 1

    {:ok, _hidden} = Registry.set_visibility(claim, :private)

    assert Registry.timeline(vehicle.id) == []
    assert Enum.any?(Registry.list_claims(vehicle.id), &(&1.id == claim.id))
  end

  test "a private entry is readable when the caller is allowed to see it, and says so" do
    {:ok, vehicle} = Registry.ingest(@nine_three)

    public =
      admit(vehicle, %{
        predicate: "event.note",
        value: %{"text" => "washed it"},
        scope_date: ~D[2026-01-02]
      })

    private =
      admit(vehicle, %{
        predicate: "event.note",
        value: %{"text" => "where I keep it"},
        scope_date: ~D[2026-01-01]
      })

    {:ok, _hidden} = Registry.set_visibility(private, :private)

    assert [shown] = Registry.timeline(vehicle.id)
    assert shown.visibility == :public

    assert [newest, oldest] = Registry.timeline(vehicle.id, include_private: true)
    assert newest.visibility == :public
    assert hd(newest.claims).claim_id == public.id
    assert oldest.visibility == :private
    assert hd(oldest.claims).claim_id == private.id
  end

  test "an entry is private if any part of it is — a half-shown entry would mislead" do
    {:ok, vehicle} = Registry.ingest(@nine_three)
    entry_ref = Registry.new_entry_ref()

    admit(vehicle, %{
      predicate: "event.fuel",
      value: fuel("13.1"),
      scope_date: ~D[2026-03-01],
      entry_ref: entry_ref
    })

    mileage =
      admit(vehicle, %{
        predicate: "observation.mileage",
        value: 51_200,
        scope_date: ~D[2026-03-01],
        entry_ref: entry_ref
      })

    {:ok, _hidden} = Registry.set_visibility(mileage, :private)

    assert [entry] = Registry.timeline(vehicle.id, include_private: true)
    assert entry.visibility == :private
    assert length(entry.claims) == 2
  end

  test "factory claims are the record, not the logbook — they never appear" do
    {:ok, vehicle} = Registry.ingest(@nine_three)
    admit(vehicle, %{predicate: "build.variant", value: "coupe"})

    assert Registry.timeline(vehicle.id) == []
  end

  test "each entry carries who asserted it, so the page can attribute" do
    {:ok, vehicle} = Registry.ingest(@nine_three)

    admit(vehicle, %{
      predicate: "event.note",
      value: %{"text" => "hello"},
      scope_date: ~D[2026-01-01]
    })

    assert [entry] = Registry.timeline(vehicle.id)
    assert entry.party == "Vin Santo"
  end
end
