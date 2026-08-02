defmodule SantoApi.RateLimit do
  @moduledoc """
  A fixed-window rate limiter over one ETS table.

  Hand-rolled rather than a dependency: the whole mechanism is a counter per
  `{key, window}` and a periodic sweep, which is less code than configuring
  `hammer` would be (owner_surface.md §9.4, minimal-deps rule).

  Fixed windows, not sliding: a caller can spend two windows' worth of budget
  across a window boundary. For deterring email floods and scripted lookups
  that is fine — the limits below are set with the doubling in mind. If a
  bucket ever needs a real guarantee, that bucket gets a sliding window, not
  the whole table.

  Counts live in memory on one node. A second node means a second budget;
  revisit when there is one.
  """

  use GenServer

  @table __MODULE__
  @sweep_interval :timer.minutes(5)

  @doc """
  Counts one request against `key` and says whether to serve it.

  Returns `{:allow, count_including_this_one}` or `{:deny, retry_after_ms}`,
  where the retry time is how long until the current window rolls over.
  """
  @spec check(String.t(), pos_integer(), pos_integer()) ::
          {:allow, pos_integer()} | {:deny, non_neg_integer()}
  def check(key, limit, window) when is_binary(key) and limit > 0 and window > 0 do
    now = System.system_time(:millisecond)
    window_start = div(now, window) * window
    expires_at = window_start + window

    count = :ets.update_counter(@table, {key, window_start}, {2, 1}, {{key, window_start}, 0, 0})
    :ets.update_element(@table, {key, window_start}, {3, expires_at})

    if count <= limit do
      {:allow, count}
    else
      {:deny, expires_at - now}
    end
  end

  @doc """
  Forgets everything counted against `key`.

  Used after an act that proves the caller is not who the limit is aimed at —
  a successful log in, say — so an honest user who fat-fingered their address
  is not left sitting out the window.
  """
  @spec reset(String.t()) :: :ok
  def reset(key) when is_binary(key) do
    :ets.match_delete(@table, {{key, :_}, :_, :_})
    :ok
  end

  @doc """
  The `{limit, window_ms}` configured for a named bucket.

  Raises for an unknown bucket. A typo in a router pipeline should be a loud
  failure at request time, not a silently unlimited endpoint.
  """
  @spec limits(atom()) :: {pos_integer(), pos_integer()}
  def limits(bucket) when is_atom(bucket) do
    case Application.get_env(:santo_api, :rate_limits, [])[bucket] do
      [limit: limit, window: window] when limit > 0 and window > 0 ->
        {limit, window}

      nil ->
        raise ArgumentError,
              "no rate limit configured for bucket #{inspect(bucket)} — " <>
                "add it to config :santo_api, :rate_limits"

      other ->
        raise ArgumentError,
              "malformed rate limit for bucket #{inspect(bucket)}: #{inspect(other)} " <>
                "(expected [limit: pos_integer, window: pos_integer])"
    end
  end

  @doc """
  Drops windows that have already expired. Runs on a timer; exposed so tests
  do not have to wait for one.
  """
  @spec sweep() :: :ok
  def sweep do
    now = System.system_time(:millisecond)
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:"=<", :"$1", now}], [true]}])
    :ok
  end

  ## Supervision

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep()
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval)
  end
end
