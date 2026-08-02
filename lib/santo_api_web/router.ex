defmodule SantoApiWeb.Router do
  use SantoApiWeb, :router

  import SantoApiWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SantoApiWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", SantoApiWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # The operator bench writes to the claim ledger, so it sits behind both an
  # authentication check and the operator flag — the plugs cover the initial
  # HTTP render, the live_session covers the socket join and live navigation.
  scope "/", SantoApiWeb do
    pipe_through [:browser, :require_authenticated_user, :require_operator_user]

    live_session :require_operator,
      on_mount: [
        {SantoApiWeb.UserAuth, :require_authenticated},
        {SantoApiWeb.UserAuth, :require_operator}
      ] do
      live "/bench", BenchLive.Index
      live "/bench/vehicles/:id", BenchLive.Show
    end
  end

  scope "/api", SantoApiWeb do
    pipe_through :api

    get "/vins/:vin", VinController, :show

    post "/vehicles", VehicleController, :create
    get "/vehicles/:id", VehicleController, :show
    post "/vehicles/:id/vpic", VehicleController, :vpic
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:santo_api, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SantoApiWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", SantoApiWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{SantoApiWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end
  end

  scope "/", SantoApiWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{SantoApiWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
