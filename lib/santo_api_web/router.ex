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
    plug SantoApiWeb.Plugs.RateLimit, bucket: :api, by: :user_or_ip
  end

  # The session and registration endpoints. Magic-link sending carries its own
  # per-address limit in `Accounts.request_login_link/2`; this one is the
  # per-caller ceiling on the endpoints themselves.
  pipeline :rate_limited_auth do
    plug SantoApiWeb.Plugs.RateLimit, bucket: :auth, by: :user_or_ip
  end

  # The instrument-face document shell, shared by the public record and the
  # owner's surfaces — an owner logging a fill-up stays on the car.
  pipeline :public_chrome do
    plug :put_root_layout, html: {SantoApiWeb.Layouts, :public_root}
  end

  pipeline :public_lookup do
    plug SantoApiWeb.Plugs.RateLimit, bucket: :public_lookup
  end

  # The public record. No auth: an unclaimed page is the thing an owner finds
  # before they have any reason to sign up. `/vin/:vin` resolves to the
  # canonical `/v/:public_id` — identity is correctable, the URL is not. The
  # POST is the only public creation boundary; keeping it here makes anonymous
  # builds possible while ensuring every one crosses the lookup rate limiter.
  scope "/", SantoApiWeb do
    pipe_through [:browser, :public_chrome, :public_lookup]

    post "/builds", VehicleBuildController, :create
    get "/vin/:vin", VehiclePageController, :resolve

    # Media delivery stays in the optional-auth public browser pipeline. An
    # anonymous visitor may see a published public placement; the same route
    # can read the mounted session to let a steward see private media without
    # inventing a second signed-in URL or exposing the original upload.
    get "/events/:public_id/attachments/:id", EventAttachmentController, :show
    get "/events/:public_id/attachments/:id/:variant", EventAttachmentController, :show
    get "/v/:public_id/photos/:id/:variant", VehiclePhotoController, :show
    get "/v/:public_id/updates/:entry_ref/share-card.jpg", DistributionController, :share_card
    get "/v/:public_id/badge.svg", DistributionController, :badge

    # Anonymous is the normal case here, so the scope is mounted but never
    # required — it only decides whether the page admits you are signed in.
    # /start is anonymous by design: origination registers the account
    # (owner_surface §7b), so it lives with the public pages, and its own
    # throttle (the :origination bucket) is checked inside the LiveView
    # because the expensive submit never crosses the router.
    live_session :public,
      layout: {SantoApiWeb.Layouts, :public},
      on_mount: [{SantoApiWeb.UserAuth, :mount_current_scope}] do
      live "/", HomeLive
      live "/cars", VehicleLive.Index
      live "/start", OriginationLive
      live "/v/:public_id", VehicleLive.Show
      live "/v/:public_id/updates/:entry_ref", VehicleLive.Update
      # A shared event is a public coordinate. Optional auth stays mounted so
      # the same page can render the real signed-in shell without making a
      # visitor register merely to see what happened.
      live "/events/:public_id", EventLive.Show
    end
  end

  # The owner's own surfaces. Authenticated but *not* operator: these are the
  # first routes in the app a non-operator may write through. Stewardship is the
  # real gate and it is per-car, so the router can only check that somebody is
  # signed in — each LiveView's mount checks `Owners.stewarding?/2` and sends a
  # stranger back to the public page.
  #
  # Its own live_session rather than joining `:require_authenticated_user`,
  # because these pages wear the public record's car-first layout: an owner
  # arriving to log a fill-up should stay on the car, not cross into the dense
  # operator workbench.
  scope "/", SantoApiWeb do
    pipe_through [:browser, :public_chrome, :require_authenticated_user]

    live_session :owner,
      layout: {SantoApiWeb.Layouts, :public},
      on_mount: [{SantoApiWeb.UserAuth, :require_authenticated}] do
      live "/v/:public_id/claim", OwnerLive.Claim
      live "/v/:public_id/log", OwnerLive.Composer
      # Correcting an entry is the same surface with the entry already in it —
      # one composer, two entry points (owner_surface §8).
      live "/v/:public_id/log/:entry_ref", OwnerLive.Composer
      # Creating a participation writes both event data and an ordinary car
      # update. Login is the router gate; stewardship is rechecked in Events.
      live "/v/:public_id/events/new", OwnerLive.EventComposer
      live "/v/:public_id/spec", OwnerLive.Spec
    end
  end

  # The operator bench writes to the claim ledger, so it sits behind both an
  # authentication check and the operator flag — the plugs cover the initial
  # HTTP render, the live_session covers the socket join and live navigation.
  scope "/", SantoApiWeb do
    pipe_through [:browser, :require_authenticated_user, :require_operator_user]

    # Artifact bytes live behind the same gate: serving them publicly is an open
    # rights question, and a possession proof is somebody's VIN plate.
    get "/bench/artifacts/:id", ArtifactController, :show

    live_session :require_operator,
      on_mount: [
        {SantoApiWeb.UserAuth, :require_authenticated},
        {SantoApiWeb.UserAuth, :require_operator}
      ] do
      live "/bench", BenchLive.Index
      live "/bench/claims", BenchLive.Claims
      live "/bench/comments", BenchLive.Comments
      live "/bench/vehicles/:id", BenchLive.Show
    end
  end

  # The agent entry surface (owner_surface §8). Deliberately in no pipeline:
  # it carries a bearer token, not a session, so fetching one would only invite
  # a cookie to authorize a write. `Plug.Parsers` runs inside the plug, after
  # the credential is checked, so an unauthorized caller never gets a body
  # parsed on its behalf.
  forward "/mcp", SantoApiWeb.MCP.Plug

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
      # The garage is the authenticated daily-use home. It lives here because
      # the list and intake are account-scoped; each save still rechecks the
      # selected car's stewardship in the owner context.
      live "/garage", GarageLive
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end
  end

  scope "/", SantoApiWeb do
    pipe_through [:browser, :rate_limited_auth]

    live_session :current_user,
      on_mount: [{SantoApiWeb.UserAuth, :mount_current_scope}] do
      live "/theme", ThemeLive
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
