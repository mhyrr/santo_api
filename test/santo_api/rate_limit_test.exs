defmodule SantoApi.RateLimitTest do
  use ExUnit.Case, async: true

  alias SantoApi.RateLimit

  defp key(name), do: "test:#{name}:#{System.unique_integer([:positive])}"

  describe "check/3" do
    test "allows requests up to the limit and counts them" do
      key = key("allow")

      assert {:allow, 1} = RateLimit.check(key, 3, :timer.minutes(1))
      assert {:allow, 2} = RateLimit.check(key, 3, :timer.minutes(1))
      assert {:allow, 3} = RateLimit.check(key, 3, :timer.minutes(1))
    end

    test "denies past the limit and reports when to retry" do
      key = key("deny")
      window = :timer.minutes(1)

      for _ <- 1..2, do: {:allow, _} = RateLimit.check(key, 2, window)

      assert {:deny, retry_after} = RateLimit.check(key, 2, window)
      assert retry_after > 0
      assert retry_after <= window
    end

    test "keys are independent" do
      one = key("independent")
      two = key("independent")

      assert {:allow, 1} = RateLimit.check(one, 1, :timer.minutes(1))
      assert {:deny, _} = RateLimit.check(one, 1, :timer.minutes(1))
      assert {:allow, 1} = RateLimit.check(two, 1, :timer.minutes(1))
    end

    test "a new window starts a fresh count" do
      key = key("window")

      assert {:allow, 1} = RateLimit.check(key, 1, 1)
      Process.sleep(5)
      assert {:allow, 1} = RateLimit.check(key, 1, 1)
    end
  end

  describe "reset/1" do
    test "clears the count for a key" do
      key = key("reset")

      assert {:allow, 1} = RateLimit.check(key, 1, :timer.minutes(1))
      assert {:deny, _} = RateLimit.check(key, 1, :timer.minutes(1))

      assert :ok = RateLimit.reset(key)
      assert {:allow, 1} = RateLimit.check(key, 1, :timer.minutes(1))
    end
  end

  describe "limits/1" do
    test "reads the configured bucket" do
      assert {limit, window} = RateLimit.limits(:api)
      assert is_integer(limit) and limit > 0
      assert is_integer(window) and window > 0
    end

    test "raises for an unconfigured bucket rather than silently not limiting" do
      assert_raise ArgumentError, ~r/no rate limit configured/, fn ->
        RateLimit.limits(:nonexistent_bucket)
      end
    end
  end

  describe "sweep/1" do
    test "drops windows that have expired and keeps live ones" do
      stale = key("stale")
      live = key("live")

      assert {:allow, 1} = RateLimit.check(stale, 5, 1)
      Process.sleep(5)
      assert {:allow, 1} = RateLimit.check(live, 5, :timer.minutes(10))

      RateLimit.sweep()

      # The stale window is gone, so the next call starts over; the live one
      # kept its count.
      assert {:allow, 1} = RateLimit.check(stale, 5, 1)
      assert {:allow, 2} = RateLimit.check(live, 5, :timer.minutes(10))
    end
  end
end
