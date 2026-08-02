defmodule SantoApi.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SantoApiWeb.Telemetry,
      SantoApi.Repo,
      {DNSCluster, query: Application.get_env(:santo_api, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SantoApi.PubSub},
      SantoApi.RateLimit,
      # Start a worker by calling: SantoApi.Worker.start_link(arg)
      # {SantoApi.Worker, arg},
      # Start to serve requests, typically the last entry
      SantoApiWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SantoApi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SantoApiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
