import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :santo_api, SantoApi.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "santo_api_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :santo_api, SantoApiWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "WOvJdqre63HZqRnB4514L5PEmbg5iB38WLtSMwkmELGSdDB7L92Ktjd75/W72zcm",
  server: false

# In test we don't send emails
config :santo_api, SantoApi.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :santo_api, :vpic_req_options, plug: {Req.Test, SantoApi.Vpic}
config :santo_api, :nhtsa_corpus_req_options, plug: {Req.Test, SantoApi.NhtsaCorpus}
config :santo_api, :extraction_req_options, plug: {Req.Test, SantoApi.Extraction}
config :santo_api, :extraction, model: "claude-opus-5", api_key: "test-key"

# Jobs stay database-backed in tests, but never run behind the test process's
# back. Individual worker attempts are driven with Oban.Testing.
config :santo_api, Oban, testing: :manual, queues: false, plugins: false

config :santo_api, :uploads_dir, Path.join(System.tmp_dir!(), "santo_api_test_uploads")

# The whole suite shares one loopback address, so production limits would have
# tests throttling each other. The limiter itself is exercised directly, with
# explicit limits, in its own tests.
config :santo_api, :rate_limits,
  api: [limit: 1_000_000, window: :timer.minutes(1)],
  auth: [limit: 1_000_000, window: :timer.minutes(15)],
  # Kept small and real: it is keyed per address, and every test uses a fresh
  # one, so exercising it here cannot throttle anything else.
  login_email: [limit: 3, window: :timer.hours(1)],
  public_lookup: [limit: 1_000_000, window: :timer.minutes(1)],
  mcp: [limit: 1_000_000, window: :timer.minutes(1)],
  origination: [limit: 1_000_000, window: :timer.hours(1)]
