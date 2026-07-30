defmodule SantoApi.Repo do
  use Ecto.Repo,
    otp_app: :santo_api,
    adapter: Ecto.Adapters.Postgres
end
