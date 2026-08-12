defmodule SantoApi.Accounts.AccessDecision do
  @moduledoc """
  One operator decision about whether an account credential may authenticate.

  Rows are append-only. The current state lives on the user for authentication
  queries; this table answers who changed it, why, and when without entangling
  account access with the user's permanent Party or per-car Stewardships.
  """

  use Ecto.Schema

  alias SantoApi.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "account_access_decisions" do
    belongs_to :user, User
    belongs_to :decided_by_user, User
    field :action, Ecto.Enum, values: [:suspended, :restored]
    field :reason, :string
    field :access_version, :integer
    field :decided_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
