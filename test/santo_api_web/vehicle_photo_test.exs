defmodule SantoApiWeb.VehiclePhotoTest do
  use SantoApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias SantoApi.Accounts.Scope
  alias SantoApi.Owners
  alias SantoApi.Owners.Photos
  alias SantoApi.Registry
  alias SantoApi.Repo
  alias SantoApi.Social
  alias SantoApi.Storage

  setup :register_and_log_in_user

  setup ctx do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    {:ok, _stewardship} = Owners.grant_stewardship(ctx.user, vehicle)

    %{vehicle: vehicle, scope: Scope.for_user(ctx.user)}
  end

  test "a photograph can be the whole update and receives stripped responsive variants", ctx do
    assert {:ok, entry} =
             Owners.compose_entry(ctx.scope, ctx.vehicle, %{
               date: ~D[2026-08-10],
               claims: [],
               photos: [photo(:cayman, "The Cayman waiting between autocross runs")]
             })

    assert entry.claims == []

    assert [%{hero: true, alt_text: "The Cayman waiting between autocross runs"} = placement] =
             entry.photos

    assert Registry.timeline(ctx.vehicle.id) == []

    assert [%{entry_ref: entry_ref, claims: [], photos: [listed]}] =
             Owners.timeline(nil, ctx.vehicle)

    assert entry_ref == entry.entry_ref
    assert listed.id == placement.id

    variants = Photos.variants(placement)
    assert Enum.map(variants, & &1["width"]) == [480, 960, 1536]
    assert Enum.all?(variants, &(&1["mime"] == "image/jpeg"))

    for variant <- variants do
      assert {:ok, <<0xFF, 0xD8, _rest::binary>>} = Storage.fetch(variant["storage_ref"])
    end
  end

  test "hero, order, and alt text are mutable presentation choices", ctx do
    {:ok, first} = photo_entry(ctx, :cayman, "Cayman in the paddock")
    {:ok, second} = photo_entry(ctx, :gt3, "GT3 at Summit Point")
    [first_photo] = first.photos
    [second_photo] = second.photos

    assert {:ok, %{hero: true}} = Photos.set_hero(ctx.scope, ctx.vehicle, second_photo.id)
    assert Photos.hero(ctx.vehicle).id == second_photo.id

    assert {:ok, _moved} = Photos.move(ctx.scope, ctx.vehicle, second_photo.id, :earlier)
    assert [moved, _other] = Photos.list_photos(ctx.vehicle)
    assert moved.id == second_photo.id

    assert {:ok, updated} =
             Photos.update_alt(ctx.scope, ctx.vehicle, first_photo.id, "Arctic Silver Cayman")

    assert updated.alt_text == "Arctic Silver Cayman"
  end

  test "a reused upload keeps each entry's visibility on its placement", ctx do
    attrs = photo(:cayman, "The same photograph")

    {:ok, private} =
      Owners.compose_entry(ctx.scope, ctx.vehicle, %{
        date: ~D[2026-08-09],
        claims: [],
        photos: [attrs],
        visibility: :private
      })

    {:ok, public} =
      Owners.compose_entry(ctx.scope, ctx.vehicle, %{
        date: ~D[2026-08-10],
        claims: [],
        photos: [attrs],
        visibility: :public
      })

    assert hd(private.artifacts).id == hd(public.artifacts).id
    assert hd(private.photos).visibility == :private
    assert hd(public.photos).visibility == :public
    assert [%{entry_ref: entry_ref}] = Owners.timeline(nil, ctx.vehicle)
    assert entry_ref == public.entry_ref
  end

  test "the public route serves only a derivative and private media requires its steward", ctx do
    {:ok, public} = photo_entry(ctx, :cayman, "Cayman in the paddock")
    [public_photo] = public.photos
    public_width = public_photo |> Photos.variants() |> List.first() |> Map.fetch!("width")

    conn =
      get(
        build_conn(),
        "/v/#{ctx.vehicle.public_id}/photos/#{public_photo.id}/#{public_width}"
      )

    assert <<0xFF, 0xD8, _rest::binary>> = response(conn, 200)
    assert get_resp_header(conn, "content-type") == ["image/jpeg"]
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]

    assert_error_sent 404, fn ->
      get(
        build_conn(),
        "/v/#{ctx.vehicle.public_id}/photos/#{public_photo.id}/original"
      )
    end

    {:ok, private} =
      Owners.compose_entry(ctx.scope, ctx.vehicle, %{
        date: ~D[2026-08-11],
        claims: [],
        photos: [photo(:gt3, "Private garage view")],
        visibility: :private
      })

    [private_photo] = private.photos
    width = private_photo |> Photos.variants() |> List.first() |> Map.fetch!("width")
    path = "/v/#{ctx.vehicle.public_id}/photos/#{private_photo.id}/#{width}"

    assert_error_sent 404, fn -> get(build_conn(), path) end

    owner_conn = get(ctx.conn, path)
    assert response(owner_conn, 200)
    assert get_resp_header(owner_conn, "cache-control") == ["private, no-store"]
  end

  test "removing a photo-only update removes presentation but retains the artifact", ctx do
    {:ok, entry} = photo_entry(ctx, :cayman, "Cayman in the paddock")
    [artifact] = entry.artifacts

    assert {:ok, 1} = Owners.retract_entry(ctx.scope, ctx.vehicle, entry.entry_ref)
    assert Owners.timeline(nil, ctx.vehicle) == []
    assert Repo.get(SantoApi.Registry.Artifact, artifact.id)
  end

  test "a photo-first permalink keeps the ordinary update conversation", ctx do
    {:ok, entry} = photo_entry(ctx, :cayman, "Cayman in the paddock")
    visitor = SantoApi.AccountsFixtures.user_fixture(%{handle: "paddockfriend"})
    visitor_scope = Scope.for_user(visitor)

    assert {:ok, :added} = Social.toggle_like(visitor_scope, ctx.vehicle, entry.entry_ref)

    assert {:ok, _comment} =
             Social.create_comment(visitor_scope, ctx.vehicle, entry.entry_ref, %{
               body: "That light suits Arctic Silver."
             })

    {:ok, view, _html} =
      live(build_conn(), ~p"/v/#{ctx.vehicle.public_id}/updates/#{entry.entry_ref}")

    assert has_element?(view, "#update-card", "Photo update")
    assert has_element?(view, "#update-photos img[srcset]")
    assert has_element?(view, "#update-conversation", "That light suits Arctic Silver")

    card_conn =
      get(
        build_conn(),
        ~p"/v/#{ctx.vehicle.public_id}/updates/#{entry.entry_ref}/share-card.jpg"
      )

    assert <<0xFF, 0xD8, _rest::binary>> = bytes = response(card_conn, 200)
    assert {:ok, image} = Image.open(bytes)
    assert Image.shape(image) == {1080, 1350, 3}
  end

  defp photo_entry(ctx, asset, alt_text) do
    Owners.compose_entry(ctx.scope, ctx.vehicle, %{
      date: ~D[2026-08-10],
      claims: [],
      photos: [photo(asset, alt_text)]
    })
  end

  defp photo(asset, alt_text) do
    filename =
      case asset do
        :cayman -> "cayman-autocross-paddock.jpg"
        :gt3 -> "gt3-touring-summit-point.jpg"
      end

    %{
      path: Path.join("priv/demo/media", filename),
      filename: filename,
      mime: "image/jpeg",
      alt_text: alt_text
    }
  end
end
