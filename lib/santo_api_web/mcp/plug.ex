defmodule SantoApiWeb.MCP.Plug do
  @moduledoc """
  Streamable HTTP transport for the agent entry surface (owner_surface §8).

  Hand-rolled rather than a dependency, for the same reason `SantoApi.RateLimit`
  is: the whole transport is one POST that returns JSON and one GET that
  declines to stream. Tidewave — vendored in this project's own `deps/` —
  serves MCP from Phoenix exactly this way.

  The spec permits both halves. For a request, a server "MUST either return
  `Content-Type: text/event-stream` ... or `application/json`, to return one
  JSON object"; for GET it "MUST either return `Content-Type:
  text/event-stream` ... or else return HTTP 405 Method Not Allowed". Every
  tool here answers off a Postgres query in milliseconds, so there is nothing
  worth streaming and no stream to keep alive.

  Stateless on purpose. MCP 2026-07-28 removed sessions and the
  initialize/initialized handshake outright; before that, `Mcp-Session-Id` was
  only ever a server MAY. Answering `initialize` while storing nothing is
  simultaneously correct for the clients shipping today and for the revision
  that deleted the concept.

  Auth is a bearer token minted in account settings (§9.1). The spec makes
  authorization OPTIONAL and OAuth 2.1 the conformant path when it is offered;
  a static token is a deliberate v1 deviation, and §8 defers OAuth "when a
  real client demands it". The 401 still carries `WWW-Authenticate` so a
  client is told what to present.
  """

  import Plug.Conn

  alias SantoApi.Accounts
  alias SantoApi.RateLimit
  alias SantoApiWeb.MCP.Server

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "POST"} = conn, _opts) do
    with {:ok, token} <- bearer_token(conn),
         :ok <- within_rate_limit(token),
         {:ok, scope} <- Accounts.fetch_mcp_scope(token) do
      conn
      |> Plug.Parsers.call(parser_opts())
      |> Server.handle(scope)
    else
      {:error, :rate_limited, retry_after_ms} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(div(retry_after_ms, 1000) + 1))
        |> send_resp(429, "Too Many Requests")

      {:error, _unauthorized} ->
        conn
        |> put_resp_header("www-authenticate", ~s(Bearer realm="vin-santo"))
        |> send_resp(401, "Unauthorized")
    end
    |> halt()
  end

  # Declining the stream rather than failing to open one. A client reading this
  # correctly simply never asks again.
  def call(%Plug.Conn{method: "GET"} = conn, _opts) do
    conn |> send_resp(405, "Method Not Allowed") |> halt()
  end

  # Session teardown for clients that still send it; there is no session to
  # tear down, and the spec allows saying so.
  def call(%Plug.Conn{method: "DELETE"} = conn, _opts) do
    conn |> send_resp(405, "Method Not Allowed") |> halt()
  end

  def call(conn, _opts), do: conn |> send_resp(405, "Method Not Allowed") |> halt()

  defp parser_opts do
    Plug.Parsers.init(parsers: [:json], pass: ["application/json"], json_decoder: Jason)
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, String.trim(token)}
      ["bearer " <> token] -> {:ok, String.trim(token)}
      _absent -> {:error, :no_credentials}
    end
  end

  # Keyed on the token rather than the IP: the budget belongs to the credential,
  # so one owner's runaway assistant cannot spend another's, and a shared egress
  # address is not a shared limit.
  defp within_rate_limit(token) do
    {limit, window} = RateLimit.limits(:mcp)
    key = "mcp:" <> Base.encode16(:crypto.hash(:sha256, token), case: :lower)

    case RateLimit.check(key, limit, window) do
      {:allow, _count} -> :ok
      {:deny, retry_after_ms} -> {:error, :rate_limited, retry_after_ms}
    end
  end
end
