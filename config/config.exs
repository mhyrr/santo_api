# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :santo_api, :scopes,
  user: [
    default: true,
    module: SantoApi.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: SantoApi.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :santo_api,
  ecto_repos: [SantoApi.Repo],
  generators: [timestamp_type: :utc_datetime]

# Acquisition runs keep their product state in Santo's own tables; Oban owns
# only delivery, retries, and crash recovery for the provider steps.
config :santo_api, Oban,
  repo: SantoApi.Repo,
  queues: [acquisitions: 4],
  plugins: [{Oban.Plugins.Pruner, max_age: 7 * 24 * 60 * 60}]

# Rate limit buckets (owner_surface.md §9.4). Fixed windows — see
# `SantoApi.RateLimit` on what that costs. A bucket named in a router
# pipeline but missing here raises at request time rather than quietly
# serving unlimited traffic.
#
#   :api      — unauthenticated VIN lookup and vehicle reads
#   :auth     — session and registration endpoints
#   :login_email — magic links, counted per address so one mailbox cannot be
#                  flooded from many IPs
config :santo_api, :rate_limits,
  api: [limit: 60, window: :timer.minutes(1)],
  auth: [limit: 20, window: :timer.minutes(15)],
  login_email: [limit: 5, window: :timer.hours(1)],
  # The public page and the VIN resolver. Generous — this is the shareable
  # surface and a forum thread linking one car should never trip it — but the
  # resolver is an enumeration path, so it is not unbounded.
  public_lookup: [limit: 120, window: :timer.minutes(1)],
  # The agent surface, keyed per token rather than per address: the budget
  # belongs to the credential, so a runaway assistant spends only its owner's.
  # Room for a conversation that logs a season of track days in one sitting.
  mcp: [limit: 120, window: :timer.minutes(1)],
  # Origination (owner_surface §7b.5): a second door that mints vehicle rows
  # and spends an LLM call per try. Tight on purpose — a person describes one
  # car, not a hundred an hour.
  origination: [limit: 10, window: :timer.hours(1)]

# Artifact storage. Local disk is fine for the operator bench; owner uploads
# (claiming photos, documents) need object storage before the first real
# owner — see docs/design/owner_surface.md §9.4.
config :santo_api, :storage_adapter, SantoApi.Storage.Local

# The one-box extractor (owner_surface §7b) — the project's first hosted LLM
# call. The api_key arrives via runtime.exs (ANTHROPIC_API_KEY); without one,
# extraction degrades to the empty read-back rather than crashing anything.
config :santo_api, :extraction, model: "claude-opus-5"

# Configure the endpoint
config :santo_api, SantoApiWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SantoApiWeb.ErrorHTML, json: SantoApiWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SantoApi.PubSub,
  live_view: [signing_salt: "gF3aiRsI"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :santo_api, SantoApi.Mailer, adapter: Swoosh.Adapters.Local

# Sender identity for every outbound email. Overridden at runtime in
# production (config/runtime.exs) so the address follows the deployed domain
# rather than being baked into the release.
#
# TODO(greg): set the real sending domain and address here once DNS is
# decided; the local default is deliberately undeliverable.
config :santo_api, :email_from, {"Vin Santo", "no-reply@localhost"}

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  santo_api: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  santo_api: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
