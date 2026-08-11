defmodule SantoApi.Demo.DmvSeedTest do
  use SantoApi.DataCase, async: false

  alias SantoApi.Accounts
  alias SantoApi.Accounts.Scope
  alias SantoApi.Demo.DmvSeed
  alias SantoApi.Events
  alias SantoApi.Owners
  alias SantoApi.Registry
  alias SantoApi.Social

  test "seeds believable public car accounts around real DMV event coordinates" do
    summary = DmvSeed.run!()

    assert map_size(summary.cars) == 4
    assert map_size(summary.events) == 3
    assert summary.events.katies_april_18.participation_count == 2

    assert {:ok, katies} =
             Events.fetch_public_event(summary.events.katies_april_18.public_id)

    assert katies.title == "Katie's Cars & Coffee · April 18"
    assert katies.starts_on == ~D[2026-04-18]
    assert katies.starts_at == ~T[06:00:00]
    assert katies.ends_at == ~T[09:00:00]
    assert katies.place_text =~ "Great Falls"
    assert katies.participant_count == 2
    assert katies.media_count == 1

    assert Enum.sort(Enum.map(katies.participations, & &1.user.handle)) == [
             "slowcarfast",
             "zedsunday"
           ]

    assert Enum.any?(katies.participations, fn participation ->
             Enum.any?(
               participation.attachments,
               &(is_binary(&1.url) and &1.url =~ "facebook.com/groups/710572889036708")
             )
           end)

    assert {:ok, wdcr} = Events.fetch_public_event(summary.events.wdcr_ax_2.public_id)
    assert wdcr.title == "WDCR 2026 AX Championship Event #2"
    assert wdcr.starts_on == ~D[2026-05-24]
    assert wdcr.place_text =~ "Regency Furniture Stadium"

    [participation] = wdcr.participations

    assert Enum.any?(participation.attachments, fn attachment ->
             attachment.kind == :photo and attachment.artifact.mime == "image/jpeg"
           end)

    assert Enum.map(participation.details, &{&1.label, &1.value}) == [
             {"Class", "S2"},
             {"Best run", "44.182 +1"},
             {"Tire pressure", "32F / 30R hot"},
             {"Change tried", "Rear bar one step softer"}
           ]

    {:ok, cayman} = Registry.fetch_by_public_id(summary.cars.cayman.public_id)
    refute Map.has_key?(cayman.current_state, "state.tire_pressure")
    assert get_in(cayman.current_state, ["state.suspension", "value", "summary"]) =~ "Öhlins"

    conversation = Social.conversation(nil, cayman, participation.entry_ref)
    assert conversation.like_count == 1
    assert conversation.comment_count == 1
  end

  test "is re-runnable without duplicating users, cars, events, entries, or conversation" do
    first = DmvSeed.run!()
    first_counts = counts(first)

    second = DmvSeed.run!()

    assert Map.drop(second, [:removed_placeholder_media]) ==
             Map.drop(first, [:removed_placeholder_media])

    assert second.removed_placeholder_media == 0
    assert counts(second) == first_counts
  end

  defp counts(summary) do
    car_entries =
      Map.new(summary.cars, fn {key, car} ->
        user = Accounts.get_user_by_email("#{car.handle}@demo.vinsanto.test")
        {:ok, vehicle} = Registry.fetch_by_public_id(car.public_id)
        {key, length(Owners.timeline(Scope.for_user(user), vehicle))}
      end)

    event_counts =
      Map.new(summary.events, fn {key, event} ->
        {:ok, occurrence} = Events.fetch_public_event(event.public_id)
        {key, occurrence.participant_count}
      end)

    %{car_entries: car_entries, event_counts: event_counts}
  end
end
