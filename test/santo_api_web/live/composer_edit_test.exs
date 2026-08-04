defmodule SantoApiWeb.ComposerEditTest do
  @moduledoc """
  Correcting an entry on the web (owner_surface §8, decided 2026-08-03).

  The other half of what ticket H left open: the agent surface could already
  amend, the page could only remove. One entry surface with two entry points —
  the composer prefilled from an entry it wrote, saving through
  `Owners.amend_entry/4` instead of `compose_entry/3`.

  The rule these tests hold to is the doctrine one: the composer offers an edit
  only for an entry it can restate exactly. Anything it would have to drop on
  the way through is not editable here, because a correction that silently ate a
  field is worse than no correction at all.
  """

  # Ingest-heavy: real VINs and shared parties deadlock under async (CLAUDE.md).
  use SantoApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias SantoApi.Accounts.Scope
  alias SantoApi.Owners
  alias SantoApi.Registry
  alias SantoApi.Registry.Claim

  setup :register_and_log_in_user

  setup ctx do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    {:ok, _stewardship} = Owners.grant_stewardship(ctx.user, vehicle, handle: "mhyrr")

    %{vehicle: vehicle, scope: Scope.for_user(ctx.user)}
  end

  # Shaped exactly as the composer's fill-up mode writes one, because an entry
  # the composer did not write is not one it promises to be able to edit.
  defp fill_up(ctx, attrs \\ %{}) do
    {:ok, entry} =
      Owners.compose_entry(
        ctx.scope,
        ctx.vehicle,
        Map.merge(
          %{
            date: ~D[2026-08-02],
            claims: [
              %{
                predicate: "event.fuel",
                value: %{
                  "volume" => "13.1",
                  "unit" => "gal",
                  "total_cents" => 6745,
                  "currency" => "USD"
                }
              },
              %{predicate: "observation.mileage", value: 41_660}
            ]
          },
          attrs
        )
      )

    entry
  end

  defp edit_path(ctx, entry), do: ~p"/v/#{ctx.vehicle.public_id}/log/#{entry.entry_ref}"

  describe "opening an entry for correction" do
    test "arrives on the entry's own mode with its values in the fields", ctx do
      entry = fill_up(ctx)

      {:ok, view, _html} = live(ctx.conn, edit_path(ctx, entry))

      assert has_element?(view, "[data-mode=fuel][aria-current=true]")
      assert view |> element("#entry_volume") |> render() =~ "13.1"
      assert view |> element("#entry_odometer") |> render() =~ "41660"
      assert view |> element("#entry_price") |> render() =~ "67.45"
      assert view |> element("#entry_date") |> render() =~ "2026-08-02"
    end

    test "a service entry opens on Service, performer and all", ctx do
      {:ok, entry} =
        Owners.compose_entry(ctx.scope, ctx.vehicle, %{
          date: ~D[2026-08-02],
          claims: [
            %{
              predicate: "event.service",
              value: %{"summary" => "Oil and filter", "performer" => "Bruce Canepa"}
            },
            %{predicate: "observation.mileage", value: 41_700}
          ]
        })

      {:ok, view, _html} = live(ctx.conn, edit_path(ctx, entry))

      assert has_element?(view, "[data-mode=service][aria-current=true]")
      assert view |> element("#entry_summary") |> render() =~ "Oil and filter"
      assert view |> element("#entry_performer") |> render() =~ "Bruce Canepa"
    end

    test "a mod opens with its trait delta still attached", ctx do
      {:ok, entry} =
        Owners.compose_entry(ctx.scope, ctx.vehicle, %{
          date: ~D[2026-08-02],
          claims: [
            %{
              predicate: "event.modification",
              value: %{
                "summary" => "Wrapped it Signal Green",
                "area" => "exterior",
                "sets" => [
                  %{
                    "predicate" => "state.exterior",
                    "value" => %{"summary" => "Signal Green wrap over Slate Grey"}
                  }
                ]
              }
            }
          ]
        })

      {:ok, view, _html} = live(ctx.conn, edit_path(ctx, entry))

      assert has_element?(view, "[data-mode=modification][aria-current=true]")
      assert view |> element("#entry_area") |> render() =~ "exterior"
      assert view |> element("#entry_trait_summary") |> render() =~ "Signal Green wrap"
      assert has_element?(view, "option[value='state.exterior'][selected]")
    end

    test "the page says it is correcting, not logging", ctx do
      entry = fill_up(ctx)

      {:ok, _view, html} = live(ctx.conn, edit_path(ctx, entry))

      assert html =~ "Correct"
      refute html =~ "Log an entry"
    end
  end

  describe "saving a correction" do
    test "the entry keeps its ref and the timeline shows one corrected line", ctx do
      entry = fill_up(ctx)

      {:ok, view, _html} = live(ctx.conn, edit_path(ctx, entry))

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form("#composer-form",
                 entry: %{odometer: "41660", volume: "13.5", price: "67.45"}
               )
               |> render_submit()

      assert to == "/v/#{ctx.vehicle.public_id}"

      assert [corrected] = Registry.timeline(ctx.vehicle.id)
      assert corrected.entry_ref == entry.entry_ref

      by_predicate = Map.new(corrected.claims, &{&1.predicate, &1.value})
      assert by_predicate["event.fuel"]["volume"] == "13.5"
      assert by_predicate["observation.mileage"] == 41_660
    end

    test "the superseded value is retracted in the ledger, never deleted", ctx do
      entry = fill_up(ctx)
      original = Enum.find(entry.claims, &(&1.predicate == "event.fuel"))

      {:ok, view, _html} = live(ctx.conn, edit_path(ctx, entry))

      view
      |> form("#composer-form", entry: %{odometer: "41660", volume: "13.5", price: "67.45"})
      |> render_submit()

      withdrawn = SantoApi.Repo.get!(Claim, original.id)
      assert withdrawn.state == :retracted
      assert withdrawn.value["volume"] == "13.1"
    end

    test "the date is correctable too — a back-fill entered on the wrong day", ctx do
      entry = fill_up(ctx)

      {:ok, view, _html} = live(ctx.conn, edit_path(ctx, entry))

      view
      |> form("#composer-form",
        entry: %{odometer: "41660", volume: "13.1", price: "67.45", date: "2019-04-12"}
      )
      |> render_submit()

      assert [corrected] = Registry.timeline(ctx.vehicle.id)
      assert corrected.entry_ref == entry.entry_ref
      assert corrected.date == ~D[2019-04-12]
    end

    test "an entry kept off the public page stays off it", ctx do
      entry = fill_up(ctx, %{visibility: :private})

      {:ok, view, _html} = live(ctx.conn, edit_path(ctx, entry))

      view
      |> form("#composer-form", entry: %{odometer: "41660", volume: "13.5", price: "67.45"})
      |> render_submit()

      # Still invisible to a visitor: correcting a value is not consent to publish.
      assert Registry.timeline(ctx.vehicle.id) == []
      assert [_corrected] = Owners.timeline(ctx.scope, ctx.vehicle)
    end

    test "a correction that empties a required field refuses and keeps the entry", ctx do
      entry = fill_up(ctx)

      {:ok, view, _html} = live(ctx.conn, edit_path(ctx, entry))

      html =
        view
        |> form("#composer-form", entry: %{odometer: "41660", volume: "", price: ""})
        |> render_submit()

      assert html =~ "how much fuel"
      assert [untouched] = Registry.timeline(ctx.vehicle.id)
      fuel = Enum.find(untouched.claims, &(&1.predicate == "event.fuel"))
      assert fuel.value["volume"] == "13.1"
    end
  end

  describe "what may not be corrected here" do
    test "a signed-in stranger is turned away from a car they do not steward", ctx do
      entry = fill_up(ctx)
      conn = log_in_user(build_conn(), SantoApi.AccountsFixtures.user_fixture())

      assert {:error, {:redirect, %{to: to, flash: %{"error" => error}}}} =
               live(conn, edit_path(ctx, entry))

      assert to == "/v/#{ctx.vehicle.public_id}"
      assert error =~ "maintain"
    end

    test "an entry the caller did not assert is not theirs to correct", ctx do
      # The registry's own hand-entered service event: same `method: :human`,
      # different asserting party. The line is the party, not the method.
      {:ok, claim} =
        Registry.propose_claim(ctx.vehicle, %{
          "predicate" => "event.service",
          "value" => %{"summary" => "Annual service, per the invoice", "performer" => nil},
          "scope_date" => "2019-04-12",
          "entry_ref" => Registry.new_entry_ref()
        })

      {:ok, ratified} = Registry.ratify_claim(claim.id)

      assert {:error, {:redirect, %{to: to, flash: %{"error" => error}}}} =
               live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/log/#{ratified.entry_ref}")

      assert to == "/v/#{ctx.vehicle.public_id}"
      assert error =~ "yours"
      assert SantoApi.Repo.get!(Claim, claim.id).state == :admitted
    end

    test "an entry with no such ref turns away rather than opening a blank composer", ctx do
      assert {:error, {:redirect, %{to: _to, flash: %{"error" => _error}}}} =
               live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/log/#{Registry.new_entry_ref()}")
    end

    test "an entry the composer cannot restate exactly is refused, not mangled", ctx do
      # An outing logged through the agent surface: no composer mode produces
      # `event.outing`, so prefilling it would mean saving it as something else.
      {:ok, entry} =
        Owners.compose_entry(ctx.scope, ctx.vehicle, %{
          date: ~D[2026-08-02],
          claims: [
            %{
              predicate: "event.outing",
              value: %{"kind" => "autocross", "summary" => "Best run 2nd in class"}
            }
          ]
        })

      assert {:error, {:redirect, %{to: _to, flash: %{"error" => error}}}} =
               live(ctx.conn, edit_path(ctx, entry))

      assert error =~ "here"
      assert [_untouched] = Registry.timeline(ctx.vehicle.id)
    end
  end

  describe "the control on the car's page" do
    test "sits beside Remove on the steward's own entry", ctx do
      entry = fill_up(ctx)

      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}")

      assert has_element?(view, "a[href='/v/#{ctx.vehicle.public_id}/log/#{entry.entry_ref}']")
      assert has_element?(view, ~s{button[phx-value-entry_ref="#{entry.entry_ref}"]})
    end

    test "a visitor is offered no correction anywhere on the page", ctx do
      fill_up(ctx)

      {:ok, _view, html} = live(build_conn(), ~p"/v/#{ctx.vehicle.public_id}")

      assert html =~ "13.1"
      refute html =~ "/log/"
    end

    test "an entry the registry asserted carries none, on the steward's own page", ctx do
      fill_up(ctx)

      # A service event hand-entered at the bench off an invoice: same shape the
      # composer writes, same `method: :human`, different asserting party. It is
      # editable in form and not the owner's to edit in fact.
      {:ok, claim} =
        Registry.propose_claim(ctx.vehicle, %{
          "predicate" => "event.service",
          "value" => %{"summary" => "Annual service, per the invoice", "performer" => nil},
          "scope_date" => "2019-04-12",
          "entry_ref" => Registry.new_entry_ref()
        })

      {:ok, _ratified} = Registry.ratify_claim(claim.id)

      {:ok, _view, html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}")

      assert html =~ "Annual service"
      # Gated on the asserting handle, exactly as Remove is: a previous
      # steward's entries and the registry's own are not this owner's to revise.
      assert length(Regex.scan(~r{/log/[0-9a-f-]+}, html)) == 1
    end

    test "an entry the composer cannot restate keeps Remove and loses Edit", ctx do
      {:ok, entry} =
        Owners.compose_entry(ctx.scope, ctx.vehicle, %{
          date: ~D[2026-08-02],
          claims: [
            %{
              predicate: "event.outing",
              value: %{"kind" => "autocross", "summary" => "Best run 2nd in class"}
            }
          ]
        })

      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}")

      # Removing and re-logging is still open to them; what is refused is the
      # one path that would silently reshape the entry on the way through.
      assert has_element?(view, ~s{button[phx-value-entry_ref="#{entry.entry_ref}"]})
      refute has_element?(view, "a[href='/v/#{ctx.vehicle.public_id}/log/#{entry.entry_ref}']")
    end
  end

  describe "what the correction form does not offer" do
    test "no photo field, because an amendment does not carry artifacts", ctx do
      entry = fill_up(ctx)

      {:ok, view, _html} = live(ctx.conn, edit_path(ctx, entry))

      refute has_element?(view, "input[type=file]")
      assert has_element?(view, "#composer-save")
    end

    test "no visibility toggle — flipping it after the fact is its own decision", ctx do
      entry = fill_up(ctx)

      {:ok, view, _html} = live(ctx.conn, edit_path(ctx, entry))

      refute has_element?(view, "#entry_visibility")
    end
  end
end
