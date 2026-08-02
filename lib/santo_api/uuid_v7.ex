defmodule SantoApi.UUIDv7 do
  @moduledoc """
  Time-ordered UUIDs, RFC 9562 §5.7.

  Hand-rolled rather than vendored: the layout is 48 bits of Unix milliseconds,
  the version and variant nibbles, and random filler. Ordering by value orders
  by creation time, which is why `entry_ref` uses it — logbook entries read
  chronologically without a second sort key.
  """

  @doc "A fresh v7 UUID in Ecto's canonical string form."
  def generate do
    milliseconds = System.system_time(:millisecond)
    <<rand_a::12, rand_b::62, _rest::bitstring>> = :crypto.strong_rand_bytes(10)

    Ecto.UUID.load!(<<milliseconds::48, 7::4, rand_a::12, 2::2, rand_b::62>>)
  end
end
