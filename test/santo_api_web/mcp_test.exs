defmodule SantoApiWeb.McpTest do
  @moduledoc """
  The agent entry surface (owner_surface §8).

  Streamable HTTP, hand-rolled and stateless: one POST endpoint returning
  `application/json`, GET answering 405. The spec permits both — a server
  "MUST either return Content-Type: text/event-stream ... or application/json"
  for a request, and GET "MUST either return text/event-stream ... or else
  return HTTP 405". Every tool here answers off a Postgres query in
  milliseconds, so there is nothing to stream.

  Statelessness is not an omission: MCP 2026-07-28 removed sessions and the
  initialize handshake outright. Answering `initialize` while storing nothing
  satisfies both that revision and the 2025-06-18 clients shipping today.
  """

  use SantoApiWeb.ConnCase, async: false

  import Ecto.Query
  import SantoApi.AccountsFixtures

  alias SantoApi.Accounts
  alias SantoApi.Accounts.Scope
  alias SantoApi.Owners
  alias SantoApi.Registry

  setup %{conn: conn} do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    user = user_fixture()
    {:ok, _} = Owners.grant_stewardship(user, vehicle, handle: "mhyrr")
    {:ok, token, _record} = Accounts.mint_mcp_token(user, "test client")

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")

    %{conn: conn, vehicle: vehicle, user: user, token: token, scope: Scope.for_user(user)}
  end

  defp rpc(conn, token, method, params \\ %{}, id \\ 1) do
    body = %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}

    conn
    |> put_req_header("authorization", "Bearer " <> token)
    |> post(~p"/mcp", body)
  end

  defp call_tool(conn, token, name, args) do
    conn
    |> rpc(token, "tools/call", %{"name" => name, "arguments" => args})
    |> json_response(200)
    |> get_in(["result"])
  end

  defp tool_text(result), do: result |> get_in(["content"]) |> hd() |> Map.get("text")

  describe "transport" do
    test "GET answers 405 — no SSE stream offered here", %{conn: conn} do
      conn = get(conn, ~p"/mcp")
      assert conn.status == 405
    end

    test "initialize answers without minting a session", %{conn: conn, token: token} do
      conn = rpc(conn, token, "initialize", %{"protocolVersion" => "2025-06-18"})

      assert %{"result" => result} = json_response(conn, 200)
      assert result["serverInfo"]["name"] =~ "Vin Santo"
      assert result["capabilities"]["tools"]

      # Sessions were removed by the 2026-07-28 revision, and were only ever
      # MAY for a server before it. Emitting one would be state we would then
      # have to store and expire.
      assert get_resp_header(conn, "mcp-session-id") == []
    end

    test "a notification is accepted with no body", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> post(~p"/mcp", %{"jsonrpc" => "2.0", "method" => "notifications/initialized"})

      assert conn.status == 202
      assert conn.resp_body == ""
    end

    test "an unknown method is a JSON-RPC error, not an HTTP one", %{conn: conn, token: token} do
      conn = rpc(conn, token, "no/such/method")

      assert %{"error" => %{"code" => -32601}} = json_response(conn, 200)
    end
  end

  describe "authorization" do
    test "no token, a junk token, and a revoked token are all 401", %{conn: conn, user: user} do
      assert conn
             |> post(~p"/mcp", %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize"})
             |> response(401)

      assert conn
             |> put_req_header("authorization", "Bearer nonsense")
             |> post(~p"/mcp", %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize"})
             |> response(401)

      {:ok, doomed, record} = Accounts.mint_mcp_token(user, "doomed")
      {:ok, :revoked} = Accounts.revoke_mcp_token(user, record.id)

      assert conn |> rpc(doomed, "initialize") |> response(401)
    end

    test "401 carries WWW-Authenticate so a client knows what to present", %{conn: conn} do
      conn = post(conn, ~p"/mcp", %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize"})

      assert [header] = get_resp_header(conn, "www-authenticate")
      assert header =~ "Bearer"
    end
  end

  describe "my_vehicles" do
    test "lists the caller's stewarded cars", %{conn: conn, token: token, vehicle: vehicle} do
      text = conn |> call_tool(token, "my_vehicles", %{}) |> tool_text()

      assert text =~ vehicle.public_id

      # The car is a Cayman S; santo decodes the 987 to "Boxster". A known
      # upstream bug, fixed in ../santo and never patched around here, so the
      # agent surface reports exactly what the ledger holds — including when
      # the ledger is wrong. The name comes from the page's own presenter, so
      # an owner hears the same thing they would read.
      assert text =~ "2007 Porsche Boxster"
    end

    test "a token whose stewardship was revoked sees nothing", ctx do
      stewardship = Owners.stewardship(ctx.scope, ctx.vehicle)
      {:ok, _} = Owners.revoke_stewardship(stewardship, "sold the car")

      text = ctx.conn |> call_tool(ctx.token, "my_vehicles", %{}) |> tool_text()

      # Scope is the user's stewardships read at call time, so revocation stops
      # a live token mid-flight rather than at the next mint.
      refute text =~ ctx.vehicle.public_id
    end
  end

  describe "log_entry" do
    test "writes an admitted entry attributed to the owner via :llm_extract", ctx do
      result =
        call_tool(ctx.conn, ctx.token, "log_entry", %{
          "vehicle" => ctx.vehicle.public_id,
          "date" => "2026-08-02",
          "claims" => [
            %{
              "predicate" => "event.fuel",
              "value" => %{"volume" => "13.1", "unit" => "gal", "cost" => "67.45"}
            },
            %{"predicate" => "observation.mileage", "value" => 41_660}
          ]
        })

      text = tool_text(result)
      assert text =~ "13.1"
      assert text =~ "41,660" or text =~ "41660"

      assert [entry] = Owners.timeline(ctx.scope, ctx.vehicle)
      assert entry.method == :llm_extract

      # No confirm step (Greg, 2026-08-03): the tool call is the owner's
      # assertive act, so the entry is admitted on arrival. Read the states off
      # the ledger rather than the timeline, which only ever shows admitted
      # claims and so could not tell the difference.
      states =
        SantoApi.Repo.all(
          from(c in SantoApi.Registry.Claim,
            where: c.entry_ref == ^entry.entry_ref,
            select: c.state
          )
        )

      assert states == [:admitted, :admitted]
    end

    test "a dictated price lands as integer cents, not as whatever shape it arrived in", ctx do
      call_tool(ctx.conn, ctx.token, "log_entry", %{
        "vehicle" => ctx.vehicle.public_id,
        "date" => "2026-08-02",
        "claims" => [
          %{
            "predicate" => "event.fuel",
            "value" => %{"volume" => "13.1", "unit" => "gal", "cost" => "67.45"}
          }
        ]
      })

      assert [entry] = Owners.timeline(ctx.scope, ctx.vehicle)
      assert [fuel] = entry.claims

      # The same fill-up typed into the composer and dictated to an assistant is
      # one shape in the ledger. Two shapes meant the money the owner dictated
      # went into a key nothing read, and no read path could compare them.
      assert fuel.value["total_cents"] == 6745
      refute Map.has_key?(fuel.value, "cost")
    end

    test "a price per gallon is multiplied out, because the ratio is never stored", ctx do
      call_tool(ctx.conn, ctx.token, "log_entry", %{
        "vehicle" => ctx.vehicle.public_id,
        "date" => "2026-08-02",
        "claims" => [
          %{
            "predicate" => "event.fuel",
            "value" => %{"volume" => "13.1", "unit" => "gal", "unit_price" => "5.15"}
          }
        ]
      })

      assert [entry] = Owners.timeline(ctx.scope, ctx.vehicle)
      assert [fuel] = entry.claims
      assert fuel.value["total_cents"] == 6747
      refute Map.has_key?(fuel.value, "unit_price")
    end

    test "what the vocabulary has no key for is kept as words, and the event still lands", ctx do
      call_tool(ctx.conn, ctx.token, "log_entry", %{
        "vehicle" => ctx.vehicle.public_id,
        "date" => "2026-08-02",
        "claims" => [
          %{
            "predicate" => "event.fuel",
            "value" => %{
              "volume" => "13.1",
              "unit" => "gal",
              "cost" => "about sixty bucks",
              "pump" => 4
            }
          }
        ]
      })

      assert [entry] = Owners.timeline(ctx.scope, ctx.vehicle)
      by_predicate = Map.new(entry.claims, &{&1.predicate, &1.value})

      # Still a fill-up. Losing the structure because one field was unreadable
      # would cost more than the field did.
      assert by_predicate["event.fuel"]["volume"] == "13.1"
      refute Map.has_key?(by_predicate["event.fuel"], "total_cents")

      # And the words survive, in the same entry, for a parser that does not
      # exist yet — notes are claims, so this is upgradeable later.
      assert by_predicate["event.note"]["text"] == "cost: about sixty bucks; pump: 4"
    end

    test "a residual rides with the owner's own note rather than replacing it", ctx do
      call_tool(ctx.conn, ctx.token, "log_entry", %{
        "vehicle" => ctx.vehicle.public_id,
        "date" => "2026-08-02",
        "note" => "Smelled like it was running rich",
        "claims" => [
          %{
            "predicate" => "event.fuel",
            "value" => %{"volume" => "13.1", "unit" => "gal", "attendant" => "Bob"}
          }
        ]
      })

      assert [entry] = Owners.timeline(ctx.scope, ctx.vehicle)
      text = Enum.find(entry.claims, &(&1.predicate == "event.note")).value["text"]

      # The owner's own words lead and the salvaged field is parenthetical —
      # the assistant reads this back, so it has to sound like a sentence
      # somebody wrote rather than like a parser reporting what it could not do.
      assert text == "Smelled like it was running rich (attendant: Bob)"
    end

    test "returns the entry_ref so a correction has something to name", ctx do
      result =
        call_tool(ctx.conn, ctx.token, "log_entry", %{
          "vehicle" => ctx.vehicle.public_id,
          "date" => "2026-08-02",
          "claims" => [%{"predicate" => "observation.mileage", "value" => 41_660}]
        })

      assert %{"entry_ref" => ref} = result["structuredContent"]
      assert {:ok, _} = Ecto.UUID.cast(ref)
    end

    test "an unknown predicate falls into the note residual, never rejected", ctx do
      result =
        call_tool(ctx.conn, ctx.token, "log_entry", %{
          "vehicle" => ctx.vehicle.public_id,
          "date" => "2026-08-02",
          "claims" => [
            %{"predicate" => "event.exorcism", "value" => %{"priest" => "Fr. Brown"}},
            %{"predicate" => "observation.mileage", "value" => 41_660}
          ]
        })

      refute result["isError"]

      assert [entry] = Owners.timeline(ctx.scope, ctx.vehicle)
      predicates = Enum.map(entry.claims, & &1.predicate) |> Enum.sort()

      # The vocabulary is closed and stays closed, but an owner is never told
      # their own logbook entry was invalid — the part that does not fit is
      # kept verbatim as a note (owner_surface §8).
      assert predicates == ["event.note", "observation.mileage"]
      note = Enum.find(entry.claims, &(&1.predicate == "event.note"))
      assert note.value["text"] =~ "exorcism"
    end

    test "a car the caller does not steward is refused", ctx do
      {:ok, other} = Registry.ingest("WP0ZZZ99ZTS392124")

      result =
        call_tool(ctx.conn, ctx.token, "log_entry", %{
          "vehicle" => other.public_id,
          "date" => "2026-08-02",
          "claims" => [%{"predicate" => "observation.mileage", "value" => 41_660}]
        })

      assert result["isError"]
      assert tool_text(result) =~ "maintain"
    end
  end

  describe "amend_entry and delete_entry" do
    setup ctx do
      result =
        call_tool(ctx.conn, ctx.token, "log_entry", %{
          "vehicle" => ctx.vehicle.public_id,
          "date" => "2026-08-02",
          "claims" => [%{"predicate" => "observation.mileage", "value" => 41_660}]
        })

      Map.put(ctx, :entry_ref, result["structuredContent"]["entry_ref"])
    end

    test "amend replaces the value and keeps the entry", ctx do
      result =
        call_tool(ctx.conn, ctx.token, "amend_entry", %{
          "vehicle" => ctx.vehicle.public_id,
          "entry_ref" => ctx.entry_ref,
          "claims" => [%{"predicate" => "observation.mileage", "value" => 41_680}]
        })

      refute result["isError"]

      assert [entry] = Owners.timeline(ctx.scope, ctx.vehicle)
      assert [claim] = entry.claims
      assert claim.value == 41_680
    end

    test "delete removes the entry from the timeline", ctx do
      result =
        call_tool(ctx.conn, ctx.token, "delete_entry", %{
          "vehicle" => ctx.vehicle.public_id,
          "entry_ref" => ctx.entry_ref
        })

      refute result["isError"]
      assert Owners.timeline(ctx.scope, ctx.vehicle) == []
    end
  end

  describe "get_timeline" do
    test "reads back the owner's own view, private entries included", ctx do
      {:ok, _} =
        Owners.compose_entry(ctx.scope, ctx.vehicle, %{
          date: ~D[2026-07-04],
          visibility: :private,
          claims: [%{predicate: "event.note", value: %{"text" => "hidden from the public page"}}]
        })

      text =
        ctx.conn
        |> call_tool(ctx.token, "get_timeline", %{
          "vehicle" => ctx.vehicle.public_id
        })
        |> tool_text()

      # The token is the owner's, so the read is the owner's. A reader that
      # hid the owner's own entry would be a bug in a new surface.
      assert text =~ "hidden from the public page"
    end
  end

  describe "what the assistant reads aloud" do
    test "renders entries through the page's own presenter, not raw JSON", ctx do
      {:ok, _} =
        Owners.compose_entry(ctx.scope, ctx.vehicle, %{
          date: ~D[2026-08-02],
          claims: [
            %{
              predicate: "event.modification",
              value: %{"summary" => "Wrapped it Signal Green", "area" => "exterior"}
            }
          ]
        })

      text =
        ctx.conn
        |> call_tool(ctx.token, "get_timeline", %{"vehicle" => ctx.vehicle.public_id})
        |> tool_text()

      # One renderer for the page and the agent. A JSON blob read out loud is
      # an assistant sounding broken, and two renderers drift.
      assert text =~ "Wrapped it Signal Green"
      refute text =~ "{"
      refute text =~ "\"summary\""
    end

    test "money reads as money and an unlogged entry_ref is not an empty label", ctx do
      call_tool(ctx.conn, ctx.token, "log_entry", %{
        "vehicle" => ctx.vehicle.public_id,
        "date" => "2026-08-02",
        "claims" => [
          %{
            "predicate" => "event.fuel",
            "value" => %{
              "volume" => "13.1",
              "unit" => "gal",
              "cost" => "67.45",
              "currency" => "USD"
            }
          }
        ]
      })

      text =
        ctx.conn
        |> call_tool(ctx.token, "get_timeline", %{"vehicle" => ctx.vehicle.public_id})
        |> tool_text()

      # Asserted, not merely un-mangled: the negative on its own passed happily
      # through the whole period when a fill-up showed no money at all.
      assert text =~ "$67.45"
      assert text =~ "$5.15/gal"
      refute text =~ "USD67.45"
      refute text =~ "entry_ref: )"
    end

    test "the residual note reads as a sentence, not as a failed parse", ctx do
      result =
        call_tool(ctx.conn, ctx.token, "log_entry", %{
          "vehicle" => ctx.vehicle.public_id,
          "date" => "2026-08-01",
          "claims" => [
            %{"predicate" => "event.alignment", "value" => %{"camber" => "-2.5 front"}}
          ]
        })

      assert [entry] = Owners.timeline(ctx.scope, ctx.vehicle)
      note = Enum.find(entry.claims, &(&1.predicate == "event.note"))

      # The owner's words survive; the shape we could not type them into does
      # not leak into the note as JSON punctuation.
      assert note.value["text"] =~ "camber"
      assert note.value["text"] =~ "-2.5 front"
      refute note.value["text"] =~ "{"
      refute tool_text(result) =~ "{"
    end

    test "a fill-up's salvaged words are read back with the fill-up", ctx do
      call_tool(ctx.conn, ctx.token, "log_entry", %{
        "vehicle" => ctx.vehicle.public_id,
        "date" => "2026-08-02",
        "claims" => [
          %{
            "predicate" => "event.fuel",
            "value" => %{
              "volume" => "13.1",
              "unit" => "gal",
              "cost" => "about sixty bucks",
              "pump" => "4"
            }
          }
        ]
      })

      text =
        ctx.conn
        |> call_tool(ctx.token, "get_timeline", %{"vehicle" => ctx.vehicle.public_id})
        |> tool_text()

      # One renderer, so the page's fix is the assistant's fix. Both halves of
      # the entry come back: the fill-up we understood and the words we did not.
      assert text =~ "13.1 gal of fuel"
      assert text =~ "about sixty bucks"
      assert text =~ "pump"
    end
  end

  describe "tools/list" do
    test "advertises the five tools with schemas", %{conn: conn, token: token} do
      assert %{"result" => %{"tools" => tools}} =
               conn |> rpc(token, "tools/list") |> json_response(200)

      names = tools |> Enum.map(& &1["name"]) |> Enum.sort()

      assert names == [
               "amend_entry",
               "delete_entry",
               "get_timeline",
               "log_entry",
               "my_vehicles"
             ]

      assert Enum.all?(tools, &is_map(&1["inputSchema"]))
      assert Enum.all?(tools, &(String.length(&1["description"]) > 30))
    end
  end
end
