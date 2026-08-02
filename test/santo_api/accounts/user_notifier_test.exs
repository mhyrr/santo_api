defmodule SantoApi.Accounts.UserNotifierTest do
  use SantoApi.DataCase, async: true

  import Swoosh.TestAssertions
  import SantoApi.AccountsFixtures

  alias SantoApi.Accounts.UserNotifier

  test "sends from the configured address, not a hardcoded one" do
    from = Application.fetch_env!(:santo_api, :email_from)

    refute from == {"SantoApi", "contact@example.com"}

    {:ok, _email} =
      UserNotifier.deliver_login_instructions(
        unconfirmed_user_fixture(),
        "https://example.test/link"
      )

    assert_email_sent(fn email -> assert email.from == from end)
  end
end
