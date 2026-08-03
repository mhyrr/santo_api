defmodule SantoApiWeb.MCP.Server do
  @moduledoc """
  JSON-RPC 2.0 dispatch for the agent surface.

  Four methods: `initialize`, `ping`, `tools/list`, `tools/call`. Everything
  else is a `-32601`. Notifications — a message with no `id` — get 202 and no
  body, which is what the spec requires of a server that accepts one.

  A tool that fails answers `200` with `isError: true` and a sentence the
  assistant can read aloud, not a JSON-RPC error. That distinction is the
  protocol's: a JSON-RPC error means the call could not be dispatched; a failed
  tool means it ran and the answer was no. An assistant can relay the second
  to its owner and do something about it.
  """

  import Plug.Conn

  alias SantoApiWeb.MCP.Tools

  # What we answer when a client offers nothing. 2025-06-18 is what the
  # clients shipping today negotiate; a client asking for a newer revision is
  # echoed its own version, since a stateless tools-only server is compatible
  # across every revision that has existed.
  @default_protocol_version "2025-06-18"
  @server_version Mix.Project.config()[:version]

  def handle(conn, scope) do
    case conn.body_params do
      %{"method" => method} = message ->
        respond(conn, scope, method, Map.get(message, "params", %{}), Map.get(message, "id"))

      _malformed ->
        json(conn, 400, %{
          jsonrpc: "2.0",
          id: nil,
          error: %{code: -32600, message: "Invalid Request"}
        })
    end
  end

  # No id means a notification or a response: accept it and say nothing.
  defp respond(conn, _scope, _method, _params, nil), do: send_resp(conn, 202, "")

  defp respond(conn, _scope, "initialize", params, id) do
    version = params["protocolVersion"] || @default_protocol_version

    json(conn, 200, %{
      jsonrpc: "2.0",
      id: id,
      result: %{
        protocolVersion: version,
        capabilities: %{tools: %{listChanged: false}},
        serverInfo: %{name: "Vin Santo", version: @server_version},
        instructions: """
        The logbook for cars this person maintains. Entries you write are
        recorded as theirs, with a note that a model transcribed them.

        Write what they tell you; do not round, infer, or tidy numbers. If part
        of what they say has no matching field, log it anyway — it is kept
        verbatim as a note rather than dropped. Read the entry back to them
        after logging so a mishearing is caught while they are still talking,
        and use amend_entry or delete_entry when they correct you.
        """
      }
    })
  end

  defp respond(conn, _scope, "ping", _params, id) do
    json(conn, 200, %{jsonrpc: "2.0", id: id, result: %{}})
  end

  defp respond(conn, _scope, "tools/list", _params, id) do
    json(conn, 200, %{jsonrpc: "2.0", id: id, result: %{tools: Tools.list()}})
  end

  defp respond(conn, scope, "tools/call", params, id) do
    name = params["name"]
    arguments = params["arguments"] || %{}

    case Tools.call(scope, name, arguments) do
      {:ok, result} ->
        json(conn, 200, %{jsonrpc: "2.0", id: id, result: result})

      {:error, :unknown_tool} ->
        json(conn, 200, %{
          jsonrpc: "2.0",
          id: id,
          error: %{code: -32601, message: "Unknown tool", data: %{name: name}}
        })
    end
  end

  defp respond(conn, _scope, method, _params, id) do
    json(conn, 200, %{
      jsonrpc: "2.0",
      id: id,
      error: %{code: -32601, message: "Method not found", data: %{method: method}}
    })
  end

  defp json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode_to_iodata!(payload))
  end
end
