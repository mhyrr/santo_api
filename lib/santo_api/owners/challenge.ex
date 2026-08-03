defmodule SantoApi.Owners.Challenge do
  @moduledoc """
  One attempt to prove possession of one car (owner_surface §4).

  The code is the whole mechanism. It defeats a photo taken before the claim
  existed — a stranger who photographed the VIN plate at a show has a picture
  without the code in it, and getting one means going back to the physical car.
  For a $4.5M car that is a problem of physical access, not of this flow.

  What a claim unlocks is bounded on purpose: the log, under the claimant's own
  attributed handle. Not identity, not facts, not anything verified. So the
  decision an operator makes here is about access to a page, never about title.
  """

  use Ecto.Schema

  alias SantoApi.Accounts.User
  alias SantoApi.Registry.{Artifact, Vehicle}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "possession_challenges" do
    belongs_to :user, User
    belongs_to :vehicle, Vehicle

    field :code, :string
    # `:expired` is a code that ran out before a photo arrived. It exists as a
    # status rather than as "issued and past its date" so the one-live-challenge
    # index stays true without a job sweeping the table.
    field :status, Ecto.Enum,
      values: [:issued, :submitted, :approved, :denied, :expired],
      default: :issued

    field :expires_at, :utc_datetime_usec
    field :handle, :string

    belongs_to :proof_artifact, Artifact
    field :reason, :string
    belongs_to :decided_by_user, User
    field :decided_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  # No 0/O, 1/I/L: the code is read off a photograph of handwriting, and a
  # character a person could read two ways turns a good claim into a denial.
  @alphabet ~c"ABCDEFGHJKMNPQRSTUVWXYZ23456789"
  @length 8

  @doc "A fresh challenge code — eight characters nobody has to squint at."
  def mint_code do
    for _each <- 1..@length, into: "", do: <<Enum.random(@alphabet)>>
  end

  @doc "How the code is written down, so it gets copied onto paper correctly."
  def spaced(code) when is_binary(code) do
    code |> String.graphemes() |> Enum.chunk_every(4) |> Enum.map_join(" ", &Enum.join/1)
  end
end
