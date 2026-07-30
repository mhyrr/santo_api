defmodule SantoApi.Registry.Party do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "parties" do
    field :name, :string
    field :kind, Ecto.Enum, values: [:owner, :vendor, :shop, :registry, :vin_santo]
    timestamps(type: :utc_datetime_usec)
  end
end
