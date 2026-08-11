defmodule SantoApi.OwnersLinksTest do
  @moduledoc """
  Links are curation, not evidence (owner_surface §2, §7b.1 decision 8): they
  are mutable and deletable, gated on stewardship, and scoped to the vehicle
  they were added to.
  """

  # Ingest-heavy: real VINs and shared parties deadlock under async (CLAUDE.md).
  use SantoApi.DataCase, async: false

  import SantoApi.AccountsFixtures

  alias SantoApi.Accounts.Scope
  alias SantoApi.Owners
  alias SantoApi.Owners.{Links, VehicleLink}
  alias SantoApi.Registry

  setup do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    user = user_fixture(%{handle: "linktester"})
    {:ok, _stewardship} = Owners.grant_stewardship(user, vehicle)

    %{vehicle: vehicle, user: user, scope: Scope.for_user(user)}
  end

  describe "add_link/3" do
    test "appends at the end, with increasing position", ctx do
      assert {:ok, first} =
               Links.add_link(ctx.scope, ctx.vehicle, %{
                 url: "https://youtube.com/watch?v=abc123",
                 label: "Build thread teaser"
               })

      assert {:ok, second} =
               Links.add_link(ctx.scope, ctx.vehicle, %{url: "https://rennlist.com/thread/1"})

      assert first.position == 0
      assert second.position == 1
    end

    test "refuses a caller with no stewardship on the car", ctx do
      stranger = Scope.for_user(user_fixture())

      assert {:error, :not_stewarded} =
               Links.add_link(stranger, ctx.vehicle, %{url: "https://youtube.com/watch?v=abc"})
    end

    test "refuses a URL with no scheme", ctx do
      assert {:error, changeset} =
               Links.add_link(ctx.scope, ctx.vehicle, %{url: "rennlist.com/thread/1"})

      refute changeset.valid?
      assert %{url: [_error]} = errors_on(changeset)
    end

    test "refuses a javascript: URL", ctx do
      assert {:error, changeset} =
               Links.add_link(ctx.scope, ctx.vehicle, %{url: "javascript:alert(1)"})

      refute changeset.valid?
      assert %{url: [_error]} = errors_on(changeset)
    end
  end

  describe "list_links/1" do
    test "returns links in position order", ctx do
      {:ok, first} = Links.add_link(ctx.scope, ctx.vehicle, %{url: "https://example.com/1"})
      {:ok, second} = Links.add_link(ctx.scope, ctx.vehicle, %{url: "https://example.com/2"})
      {:ok, third} = Links.add_link(ctx.scope, ctx.vehicle, %{url: "https://example.com/3"})

      assert Links.list_links(ctx.vehicle) |> Enum.map(& &1.id) ==
               [first.id, second.id, third.id]
    end
  end

  describe "build thread" do
    test "stores one replaceable forum destination without disturbing other links", ctx do
      {:ok, other} =
        Links.add_link(ctx.scope, ctx.vehicle, %{url: "https://youtube.com/watch?v=one"})

      assert {:ok, thread} =
               Links.set_build_thread(ctx.scope, ctx.vehicle, %{
                 url: "https://rennlist.com/forums/builds/first"
               })

      assert thread.kind == :build_thread
      assert thread.label == "Build thread"
      assert Links.build_thread(ctx.vehicle).id == thread.id

      assert {:ok, replaced} =
               Links.set_build_thread(ctx.scope, ctx.vehicle, %{
                 "url" => "https://rennlist.com/forums/builds/second"
               })

      assert replaced.id == thread.id
      assert replaced.url =~ "/second"
      assert Enum.map(Links.list_links(ctx.vehicle), & &1.id) == [other.id, thread.id]

      assert {:ok, _removed} = Links.clear_build_thread(ctx.scope, ctx.vehicle)
      assert Links.build_thread(ctx.vehicle) == nil
      assert [remaining] = Links.list_links(ctx.vehicle)
      assert remaining.id == other.id
    end

    test "requires stewardship", ctx do
      stranger = Scope.for_user(user_fixture())

      assert {:error, :not_stewarded} =
               Links.set_build_thread(stranger, ctx.vehicle, %{
                 url: "https://rennlist.com/forums/builds/nope"
               })

      assert {:error, :not_stewarded} = Links.clear_build_thread(stranger, ctx.vehicle)
    end
  end

  describe "remove_link/3" do
    test "deletes the row", ctx do
      {:ok, link} = Links.add_link(ctx.scope, ctx.vehicle, %{url: "https://example.com/1"})

      assert {:ok, _deleted} = Links.remove_link(ctx.scope, ctx.vehicle, link.id)
      assert Links.list_links(ctx.vehicle) == []
    end

    test "refuses a caller with no stewardship on the car", ctx do
      {:ok, link} = Links.add_link(ctx.scope, ctx.vehicle, %{url: "https://example.com/1"})
      stranger = Scope.for_user(user_fixture())

      assert {:error, :not_stewarded} = Links.remove_link(stranger, ctx.vehicle, link.id)
      assert [_link] = Links.list_links(ctx.vehicle)
    end

    test "a link on another vehicle is not removable through this one", ctx do
      {:ok, other_vehicle} = Registry.ingest("WP0AC2A97JS176473")
      other_user = user_fixture(%{handle: "otherowner"})

      {:ok, _stewardship} =
        Owners.grant_stewardship(other_user, other_vehicle)

      {:ok, other_link} =
        Links.add_link(Scope.for_user(other_user), other_vehicle, %{
          url: "https://example.com/other"
        })

      assert {:error, :not_found} = Links.remove_link(ctx.scope, ctx.vehicle, other_link.id)
      assert [_link] = Links.list_links(other_vehicle)
    end
  end

  describe "update_link/4" do
    test "changes the label", ctx do
      {:ok, link} =
        Links.add_link(ctx.scope, ctx.vehicle, %{url: "https://example.com/1", label: "old"})

      assert {:ok, updated} =
               Links.update_link(ctx.scope, ctx.vehicle, link.id, %{label: "new label"})

      assert updated.label == "new label"
    end

    test "refuses a caller with no stewardship on the car", ctx do
      {:ok, link} = Links.add_link(ctx.scope, ctx.vehicle, %{url: "https://example.com/1"})
      stranger = Scope.for_user(user_fixture())

      assert {:error, :not_stewarded} =
               Links.update_link(stranger, ctx.vehicle, link.id, %{label: "hijacked"})
    end
  end

  describe "provider/1" do
    test "classifies a youtube watch URL" do
      assert VehicleLink.provider("https://www.youtube.com/watch?v=dQw4w9WgXcQ") ==
               {:youtube, "dQw4w9WgXcQ"}
    end

    test "classifies a youtu.be short URL" do
      assert VehicleLink.provider("https://youtu.be/dQw4w9WgXcQ") == {:youtube, "dQw4w9WgXcQ"}
    end

    test "classifies a youtube shorts URL" do
      assert VehicleLink.provider("https://youtube.com/shorts/dQw4w9WgXcQ") ==
               {:youtube, "dQw4w9WgXcQ"}
    end

    test "an instagram URL is :other — no oEmbed rights yet (§9.3)" do
      assert VehicleLink.provider("https://www.instagram.com/p/abc123/") == :other
    end

    test "garbage is :other" do
      assert VehicleLink.provider("not a url") == :other
    end
  end
end
