defmodule SantoApi.OriginationTest do
  @moduledoc """
  The front door (owner_surface §7b): one submit creates the user, the
  party, the car, the claims, and the stewardship in one transaction, and
  the magic link publishes rather than unlocks.
  """

  # Ingest-heavy: real VINs and shared parties deadlock under async (CLAUDE.md).
  use SantoApi.DataCase, async: false

  import Swoosh.TestAssertions
  import SantoApi.AccountsFixtures

  alias SantoApi.Accounts.Scope
  alias SantoApi.Origination
  alias SantoApi.Owners
  alias SantoApi.Registry

  @sentence "2024 Lexus GX 550, green, 35,000 miles"

  defp attrs(overrides \\ %{}) do
    Map.merge(
      %{
        email: unique_user_email(),
        handle: unique_user_handle(),
        sentence: @sentence,
        claims: [
          %{predicate: "identity.model_year", value: 2024},
          %{predicate: "identity.marque", value: "lexus"},
          %{predicate: "identity.model", value: %{"code" => "gx_550", "label" => "GX 550"}},
          %{predicate: "state.exterior", value: %{"summary" => "green"}},
          %{predicate: "observation.mileage", value: 35_000}
        ]
      },
      overrides
    )
  end

  defp link_url(token), do: "http://localhost/users/log-in/#{token}"

  defp drain_mailbox do
    receive do
      {:email, _email} -> drain_mailbox()
    after
      0 -> :ok
    end
  end

  describe "originate/2" do
    test "one submit creates user, party, car, claims, and stewardship" do
      input = attrs()

      assert {:ok, %{user: user, party: party, vehicle: vehicle}} =
               Origination.originate(input, &link_url/1)

      # The account, unconfirmed — the magic-link click publishes.
      assert user.email == input.email
      assert user.handle == input.handle
      assert is_nil(user.confirmed_at)

      # The party carries the reserved handle (§9.1), minted at this first
      # assertive act.
      assert party.name == input.handle
      assert Owners.party(user).id == party.id

      # A real registry row from minute one.
      assert vehicle.identity_kind == :asserted
      assert vehicle.input == @sentence
      assert Owners.steward(vehicle).id == party.id
    end

    test "identity claims self-ratify on the asserted car — the scoped §3 deviation" do
      assert {:ok, %{party: party, vehicle: vehicle}} =
               Origination.originate(attrs(), &link_url/1)

      identity_claims =
        Registry.list_claims(vehicle.id)
        |> Enum.filter(&String.starts_with?(&1.predicate, "identity."))

      assert length(identity_claims) == 3

      for claim <- identity_claims do
        assert claim.state == :admitted
        assert claim.ratified_by_party_id == party.id
        assert claim.method == :llm_extract
      end

      # The car has its name from minute one.
      assert %{"value" => 2024, "status" => "verified"} = vehicle.facts["identity.model_year"]
      assert %{"value" => 35_000} = vehicle.current_state["observation.mileage"]
    end

    test "the sentence is stored as the artifact and every claim cites it" do
      assert {:ok, %{party: party, vehicle: vehicle}} =
               Origination.originate(attrs(), &link_url/1)

      assert [artifact] = Registry.list_artifacts(vehicle.id)
      assert artifact.kind == :document
      assert artifact.source_party_id == party.id
      assert artifact.metadata["purpose"] == "origination_sentence"
      assert SantoApi.Storage.fetch(artifact.storage_ref) == {:ok, @sentence}

      for claim <- Registry.list_claims(vehicle.id) do
        assert claim.artifact_id == artifact.id
      end
    end

    test "the origination is one timeline tick — the build thread's opening post" do
      assert {:ok, %{vehicle: vehicle}} = Origination.originate(attrs(), &link_url/1)

      assert [entry] = Registry.timeline(vehicle.id)
      assert entry.date == Date.utc_today()

      predicates = Enum.map(entry.claims, & &1.predicate)
      assert "event.origination" in predicates
      assert "observation.mileage" in predicates

      origination = Enum.find(entry.claims, &(&1.predicate == "event.origination"))
      assert origination.value == %{"text" => @sentence}
      assert origination.method == :human
    end

    test "sends the magic link — publish, not unlock" do
      input = attrs()
      assert {:ok, _created} = Origination.originate(input, &link_url/1)

      assert_email_sent(fn email ->
        assert Enum.any?(email.to, fn {_name, address} -> address == input.email end)
      end)
    end

    test "a car nobody could describe still originates" do
      assert {:ok, %{vehicle: vehicle}} = Origination.originate(attrs(%{claims: []}), &link_url/1)

      assert [entry] = Registry.timeline(vehicle.id)
      assert [%{predicate: "event.origination"}] = entry.claims
      assert vehicle.facts == %{}
    end

    test "hand-typed lines carry :human, not :llm_extract" do
      assert {:ok, %{vehicle: vehicle}} =
               Origination.originate(attrs(%{method: :human}), &link_url/1)

      year = Enum.find(Registry.list_claims(vehicle.id), &(&1.predicate == "identity.model_year"))
      assert year.method == :human
    end

    test "a failed registration rolls everything back — no account, no row" do
      %{email: taken} = user_fixture()
      before_vehicles = length(Registry.list_vehicles())

      assert {:error, %Ecto.Changeset{}} =
               Origination.originate(attrs(%{email: taken}), &link_url/1)

      assert length(Registry.list_vehicles()) == before_vehicles
    end

    test "a taken handle rolls everything back too" do
      %{handle: taken} = user_fixture()
      before_vehicles = length(Registry.list_vehicles())

      assert {:error, %Ecto.Changeset{}} =
               Origination.originate(attrs(%{handle: taken}), &link_url/1)

      assert length(Registry.list_vehicles()) == before_vehicles
    end
  end

  describe "originate_for/2 — the signed-in door" do
    test "another car lands on the party the user already has" do
      {:ok, first} = Origination.originate(attrs(), &link_url/1)

      assert {:ok, second} =
               Origination.originate_for(first.user, %{
                 sentence: "1987 Porsche 911, grand prix white",
                 claims: [%{predicate: "identity.model_year", value: 1987}]
               })

      # Same party, second car — collectors have lots of cars.
      assert second.party.id == first.party.id
      assert second.vehicle.id != first.vehicle.id

      scope = Scope.for_user(first.user)
      assert length(Owners.list_stewarded_vehicles(scope)) == 2
    end

    test "sends no email — there is nothing to confirm" do
      user = user_fixture()

      # The fixture's own registration mail is not the question here.
      drain_mailbox()

      assert {:ok, %{vehicle: vehicle}} =
               Origination.originate_for(user, %{sentence: "a car", claims: []})

      refute_email_sent()

      # Public immediately: the account confirmed long ago.
      assert Owners.published?(vehicle)
    end

    test "a fresh reserved account mints its party here, at the first assertive act" do
      user = user_fixture()
      assert Owners.party(user) == nil

      assert {:ok, %{party: party}} =
               Origination.originate_for(user, %{sentence: "a car", claims: []})

      assert party.name == user.handle
    end

    test "a legacy account supplies a handle, and cannot take a reserved one" do
      %{handle: reserved} = user_fixture()
      legacy = legacy_user_fixture()

      assert {:error, :handle_required} =
               Origination.originate_for(legacy, %{sentence: "a car", claims: []})

      assert {:error, :handle_taken} =
               Origination.originate_for(legacy, %{
                 sentence: "a car",
                 claims: [],
                 handle: reserved
               })

      assert {:ok, %{party: party}} =
               Origination.originate_for(legacy, %{
                 sentence: "a car",
                 claims: [],
                 handle: "legacy-owner"
               })

      assert party.name == "legacy-owner"

      # Nothing survives a refused attempt — the rollbacks held.
      scope = Scope.for_user(legacy)
      assert length(Owners.list_stewarded_vehicles(scope)) == 1
    end
  end

  describe "Owners.resolve_asserted/3" do
    setup do
      {:ok, created} = Origination.originate(attrs(), &link_url/1)
      %{user: created.user, vehicle: created.vehicle, scope: Scope.for_user(created.user)}
    end

    test "the steward resolves an unoccupied VIN in place", ctx do
      assert {:ok, :resolved, resolved} =
               Owners.resolve_asserted(ctx.scope, ctx.vehicle, "WP0AB29827U782968")

      assert resolved.id == ctx.vehicle.id
      assert resolved.identity_kind == :vin
      assert resolved.public_id == ctx.vehicle.public_id

      # The decode landed :admitted and now audits the owner's word: they
      # said 2024, the VIN says 2007, and the page shows both.
      assert %{"status" => "conflicted"} = resolved.facts["identity.model_year"]
    end

    test "an occupied VIN records the assertion and routes to the counter-claim", ctx do
      {:ok, occupied} = Registry.ingest("WP0AB29827U782968")

      assert {:ok, :counter_claim, ^occupied, challenge} =
               Owners.resolve_asserted(ctx.scope, ctx.vehicle, "WP0AB29827U782968")

      assert challenge.vehicle_id == occupied.id
      assert challenge.user_id == ctx.user.id
      assert challenge.handle == ctx.user.handle

      # The asserted row and its log are untouched meanwhile.
      {:ok, unchanged} = Registry.fetch_vehicle(ctx.vehicle.id)
      assert unchanged.identity_kind == :asserted
    end

    test "a stranger has no identity to acquire", ctx do
      stranger = Scope.for_user(user_fixture())

      assert {:error, :not_stewarded} =
               Owners.resolve_asserted(stranger, ctx.vehicle, "WP0AB29827U782968")
    end
  end
end
