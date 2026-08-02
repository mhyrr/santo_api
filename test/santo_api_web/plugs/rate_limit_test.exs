defmodule SantoApiWeb.Plugs.RateLimitTest do
  use SantoApiWeb.ConnCase, async: true

  alias SantoApiWeb.Plugs.RateLimit

  # A distinct address per caller, so one test's budget is never another's.
  defp distinct_ip do
    <<a, b, c>> = <<System.unique_integer([:positive])::24>>
    {127, a, b, c}
  end

  defp call(conn, opts), do: RateLimit.call(conn, RateLimit.init(opts))

  defp conn_from(ip, headers \\ []) do
    Enum.reduce(headers, Map.put(build_conn(:get, "/"), :remote_ip, ip), fn {k, v}, conn ->
      put_req_header(conn, k, v)
    end)
  end

  @opts [bucket: :test, limit: 1, window: :timer.minutes(1)]

  test "passes requests under the limit and reports what is left" do
    conn = call(conn_from(distinct_ip()), bucket: :test, limit: 2, window: :timer.minutes(1))

    refute conn.halted
    assert get_resp_header(conn, "x-ratelimit-limit") == ["2"]
    assert get_resp_header(conn, "x-ratelimit-remaining") == ["1"]
  end

  test "halts with 429 and a retry-after header once the limit is spent" do
    ip = distinct_ip()

    refute call(conn_from(ip), @opts).halted

    limited = call(conn_from(ip), @opts)

    assert limited.halted
    assert limited.status == 429
    assert [retry_after] = get_resp_header(limited, "retry-after")
    assert String.to_integer(retry_after) >= 0
  end

  test "different clients get their own budget" do
    refute call(conn_from(distinct_ip()), @opts).halted
    refute call(conn_from(distinct_ip()), @opts).halted
  end

  test "buckets are independent, so a spent lookup budget leaves log-in alone" do
    ip = distinct_ip()

    refute call(conn_from(ip), @opts).halted
    assert call(conn_from(ip), @opts).halted
    refute call(conn_from(ip), Keyword.put(@opts, :bucket, :other_test)).halted
  end

  test "authenticated callers are keyed by user, not by address" do
    scope = SantoApi.Accounts.Scope.for_user(SantoApi.AccountsFixtures.user_fixture())
    opts = Keyword.put(@opts, :by, :user_or_ip)

    as_user = fn -> assign(conn_from(distinct_ip()), :current_scope, scope) end

    refute call(as_user.(), opts).halted
    # Same user, different address — still the same budget.
    assert call(as_user.(), opts).halted
  end

  test "answers JSON requests with JSON" do
    ip = distinct_ip()
    headers = [{"accept", "application/json"}]

    call(conn_from(ip, headers), @opts)
    limited = call(conn_from(ip, headers), @opts)

    assert limited.status == 429
    assert get_resp_header(limited, "content-type") |> hd() =~ "application/json"
    assert limited.resp_body =~ "rate_limited"
  end

  test "falls back to the configured limits when the plug is given only a bucket" do
    {limit, _window} = SantoApi.RateLimit.limits(:api)

    conn = call(conn_from(distinct_ip()), bucket: :api)

    refute conn.halted
    assert get_resp_header(conn, "x-ratelimit-limit") == [to_string(limit)]
  end
end
