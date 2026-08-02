defmodule SantoApiWeb.Plugs.RateLimit do
  @moduledoc """
  Counts a request against a named bucket and answers 429 when it is spent.

  ## Options

    * `:bucket` — required. Names the budget and, unless overridden, supplies
      the limits from `config :santo_api, :rate_limits`.
    * `:limit`, `:window` — override the configured limits.
    * `:by` — `:ip` (default) or `:user_or_ip`, which keys authenticated
      callers by user so they carry their budget across addresses.

  ## Examples

      plug SantoApiWeb.Plugs.RateLimit, bucket: :api
      plug SantoApiWeb.Plugs.RateLimit, bucket: :auth, by: :user_or_ip
  """

  import Plug.Conn

  alias SantoApi.RateLimit

  def init(opts) do
    bucket = Keyword.fetch!(opts, :bucket)

    {limit, window} =
      case {opts[:limit], opts[:window]} do
        {nil, nil} -> RateLimit.limits(bucket)
        {limit, window} when is_integer(limit) and is_integer(window) -> {limit, window}
      end

    %{bucket: bucket, limit: limit, window: window, by: Keyword.get(opts, :by, :ip)}
  end

  def call(conn, %{bucket: bucket, limit: limit, window: window} = opts) do
    case RateLimit.check(key(conn, bucket, opts.by), limit, window) do
      {:allow, count} ->
        conn
        |> put_resp_header("x-ratelimit-limit", to_string(limit))
        |> put_resp_header("x-ratelimit-remaining", to_string(limit - count))

      {:deny, retry_after} ->
        conn
        |> put_resp_header("retry-after", to_string(ceil(retry_after / 1000)))
        |> deny(retry_after)
        |> halt()
    end
  end

  defp deny(conn, retry_after) do
    if json?(conn) do
      body =
        Jason.encode!(%{
          error: "rate_limited",
          retry_after_seconds: ceil(retry_after / 1000)
        })

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(429, body)
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(429, "Too many requests. Try again shortly.")
    end
  end

  defp json?(conn) do
    conn
    |> get_req_header("accept")
    |> Enum.any?(&String.contains?(&1, "json"))
  end

  defp key(conn, bucket, :user_or_ip) do
    case conn.assigns[:current_scope] do
      %{user: %{id: id}} -> "#{bucket}:user:#{id}"
      _ -> key(conn, bucket, :ip)
    end
  end

  defp key(conn, bucket, :ip) do
    "#{bucket}:ip:#{conn.remote_ip |> :inet.ntoa() |> to_string()}"
  end
end
