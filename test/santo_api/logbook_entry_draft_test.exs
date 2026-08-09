defmodule SantoApi.Logbook.EntryDraftTest do
  use ExUnit.Case, async: true

  alias SantoApi.Logbook.EntryDraft

  test "a stated unit price is deterministically multiplied into the editable total" do
    reading = %{
      mode: :fuel,
      date: ~D[2026-08-08],
      odometer: 41_660,
      volume: "13.1",
      unit: "gal",
      total_price: nil,
      unit_price: "5.15",
      currency: "USD",
      summary: nil,
      performer: nil,
      area: nil,
      outing_kind: nil,
      venue: nil,
      result: nil,
      note: nil
    }

    assert {:fuel, params} = EntryDraft.from_reading(reading, "original")
    assert params["price"] == "67.47"
    assert params["currency"] == "USD"

    assert {:ok, claims} = EntryDraft.claims(:fuel, params)
    by_predicate = Map.new(claims, &{&1.predicate, &1.value})
    assert by_predicate["event.fuel"]["total_cents"] == 6_747
    assert by_predicate["event.fuel"]["currency"] == "USD"
    assert by_predicate["observation.mileage"] == 41_660
  end

  test "a stated non-dollar currency survives extraction and review" do
    reading = %{
      mode: :fuel,
      date: ~D[2026-08-08],
      odometer: nil,
      volume: "42.0",
      unit: "l",
      total_price: "78.50",
      unit_price: nil,
      currency: "EUR",
      summary: nil,
      performer: nil,
      area: nil,
      outing_kind: nil,
      venue: nil,
      result: nil,
      note: nil
    }

    assert {:fuel, params} = EntryDraft.from_reading(reading, "original")
    assert params["currency"] == "EUR"
    assert {:ok, [%{value: value}]} = EntryDraft.claims(:fuel, params)
    assert value["currency"] == "EUR"
    assert value["total_cents"] == 7_850
  end

  test "an unavailable parser loses none of the owner's sentence" do
    assert {:note, params} =
             EntryDraft.note_fallback("  Heard a new rattle behind the dash.  ", ~D[2026-08-09])

    assert params == %{
             "date" => "2026-08-09",
             "text" => "Heard a new rattle behind the dash."
           }

    assert {:ok, [%{predicate: "event.note", value: %{"text" => text}}]} =
             EntryDraft.claims(:note, params)

    assert text == "Heard a new rattle behind the dash."
  end

  test "a drive becomes an outing and preserves its narrative" do
    assert {:ok, [%{predicate: "event.outing", value: value}]} =
             EntryDraft.claims(:outing, %{
               "summary" => "Dawn run up Angeles Crest",
               "outing_kind" => "drive",
               "venue" => "Angeles Crest Highway"
             })

    assert value == %{
             "kind" => "drive",
             "summary" => "Dawn run up Angeles Crest",
             "venue" => "Angeles Crest Highway"
           }
  end
end
