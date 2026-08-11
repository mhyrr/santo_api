defmodule SantoApi.Owners.Notifier do
  @moduledoc """
  What a claim sends, and to whom (owner_surface §4, §9.1).

  Email only in v1 — no push, no digest. These are messages somebody
  is actually waiting for: a receipt when the photo arrives, the decision when
  it is made, and the counter-claim alert, which is the one that must not be
  missed. Somebody is asking for a car another person maintains, and that person
  hears about it before an operator decides anything.

  Plain text in the same register as the pages: what happened, what it means for
  you, and where to look. Links are built from the endpoint's configured host —
  the one place this context reaches at the web layer, and only for a URL.
  """

  import Swoosh.Email

  require Logger

  alias SantoApi.Accounts.User
  alias SantoApi.Mailer
  alias SantoApi.Registry.Vehicle
  alias SantoApiWeb.VehicleLive.Presenter

  @doc "The photo arrived and a person will look at it."
  def claim_received(%User{} = user, %Vehicle{} = vehicle) do
    deliver(user, "Your claim is with an operator", """
    We have your photo for the #{Presenter.title(vehicle)}.

    Somebody here reads every claim — no model decides this — and you will hear
    either way. If the photo turns out not to show the code, we will say so and
    you can send another.

    #{car_url(vehicle)}
    """)
  end

  @doc "Somebody has claimed a car this person maintains (§4's escalation)."
  def counter_claim(%User{} = incumbent, %Vehicle{} = vehicle, handle) do
    deliver(incumbent, "Someone else has claimed a car you maintain", """
    #{handle} has claimed the #{Presenter.title(vehicle)}, which you maintain.

    So far nothing has changed: you are still the person on the page, and your
    entries are untouched. An operator decides contested claims on evidence —
    registration, title, service records in your name — and will ask you for it
    before deciding anything.

    If this is a sale you already made, tell us and we will hand the log over.

    #{car_url(vehicle)}
    """)
  end

  @doc "A contested claim was resolved without changing the incumbent stewardship."
  def dispute_kept(%User{} = incumbent, %Vehicle{} = vehicle, claimant_handle, reason) do
    deliver(incumbent, "You remain the maintainer of the #{Presenter.title(vehicle)}", """
    The contested claim from #{claimant_handle} has been resolved. You remain
    the person maintaining the #{Presenter.title(vehicle)} on Vin Santo, and
    your entries and access are unchanged.

    The operator's reason: #{reason}

    #{car_url(vehicle)}
    """)
  end

  @doc "A contested claim transferred stewardship to the claimant."
  def dispute_transferred(%User{} = incumbent, %Vehicle{} = vehicle, claimant_handle, reason) do
    deliver(incumbent, "The #{Presenter.title(vehicle)} log has been transferred", """
    The contested claim from #{claimant_handle} has been resolved, and that
    person now maintains the #{Presenter.title(vehicle)} on Vin Santo.

    The operator's reason: #{reason}

    Your prior entries remain in the record under your handle. You no longer
    have access to add or change entries for this car.

    #{car_url(vehicle)}
    """)
  end

  @doc "The claim was approved. Session zero starts at the spec panel."
  def claim_approved(%User{} = user, %Vehicle{} = vehicle) do
    deliver(user, "The #{Presenter.title(vehicle)} is yours to maintain", """
    Your claim was approved. The page now reads maintained by your handle, and
    the log is yours to keep.

    Start with what the car is now — engine, wheels, paint, the mileage on it
    today. Ten minutes there and the page has a spine; everything after is one
    entry at a time.

    #{car_url(vehicle)}/spec
    """)
  end

  @doc "The claim was turned down, and why. Denial is never the end of it."
  def claim_denied(%User{} = user, %Vehicle{} = vehicle, reason) do
    deliver(user, "Your claim was not approved", """
    We could not approve your claim on the #{Presenter.title(vehicle)}.

    The reason: #{reason}

    You can try again with a fresh code — start from the car's page. Most
    denials are a photo where the code or the VIN could not be read.

    #{car_url(vehicle)}
    """)
  end

  defp car_url(%Vehicle{public_id: public_id}) do
    SantoApiWeb.Endpoint.url() <> "/v/" <> public_id
  end

  # A claim's outcome is decided in the database; the email only reports it. A
  # mail server having a bad afternoon must not cost somebody their car, so a
  # failure here is logged and swallowed rather than returned to the caller.
  defp deliver(%User{} = user, subject, body) do
    email =
      new()
      |> to(user.email)
      |> from(Application.fetch_env!(:santo_api, :email_from))
      |> subject(subject)
      |> text_body(body)

    case Mailer.deliver(email) do
      {:ok, _metadata} -> {:ok, email}
      {:error, reason} -> log_failure(user, subject, reason)
    end
  rescue
    exception -> log_failure(user, subject, exception)
  end

  defp log_failure(user, subject, reason) do
    Logger.error("claim mail #{inspect(subject)} to #{user.id} failed: #{inspect(reason)}")
    {:error, reason}
  end
end
