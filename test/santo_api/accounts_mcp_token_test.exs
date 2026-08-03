defmodule SantoApi.AccountsMcpTokenTest do
  @moduledoc """
  The credential behind the agent surface (owner_surface §8, §9.1).

  A long-lived bearer token is a different risk from a fifteen-minute login
  link, so the properties worth pinning are the ones that make a leak
  survivable: the plaintext exists once and is never recoverable from the
  database, revocation is immediate, and use leaves a stamp.
  """

  use SantoApi.DataCase, async: true

  import SantoApi.AccountsFixtures

  alias SantoApi.Accounts
  alias SantoApi.Accounts.UserToken

  describe "mint_mcp_token/2" do
    test "returns a plaintext token that is not what gets stored" do
      user = user_fixture()

      {:ok, plaintext, %UserToken{} = record} = Accounts.mint_mcp_token(user, "laptop")

      assert is_binary(plaintext)
      assert record.context == "mcp"
      assert record.name == "laptop"
      assert record.user_id == user.id

      # The whole point of hashing: a database read cannot reconstruct the
      # credential. Comparing the two directly is the test that would fail if
      # someone stored the token as-is.
      refute record.token == plaintext
      assert record.token == :crypto.hash(:sha256, Base.url_decode64!(plaintext, padding: false))
    end

    test "mints distinct tokens for repeated calls" do
      user = user_fixture()

      {:ok, first, _} = Accounts.mint_mcp_token(user, "laptop")
      {:ok, second, _} = Accounts.mint_mcp_token(user, "phone")

      refute first == second
      assert length(Accounts.list_mcp_tokens(user)) == 2
    end

    test "requires a name so two tokens can be told apart when revoking one" do
      user = user_fixture()

      assert {:error, :name_required} = Accounts.mint_mcp_token(user, "")
      assert {:error, :name_required} = Accounts.mint_mcp_token(user, "   ")
    end
  end

  describe "fetch_mcp_scope/1" do
    test "resolves a minted token to that user's scope" do
      user = user_fixture()
      {:ok, plaintext, _record} = Accounts.mint_mcp_token(user, "laptop")

      assert {:ok, scope} = Accounts.fetch_mcp_scope(plaintext)
      assert scope.user.id == user.id
    end

    test "stamps last_used_at so a leaked token is noticeable" do
      user = user_fixture()
      {:ok, plaintext, record} = Accounts.mint_mcp_token(user, "laptop")

      assert is_nil(record.last_used_at)

      {:ok, _scope} = Accounts.fetch_mcp_scope(plaintext)

      assert %UserToken{last_used_at: %DateTime{}} = Repo.get!(UserToken, record.id)
    end

    test "refuses garbage, the wrong context, and a revoked token" do
      user = user_fixture()
      {:ok, plaintext, record} = Accounts.mint_mcp_token(user, "laptop")

      assert {:error, :invalid_token} = Accounts.fetch_mcp_scope("not-a-token")
      assert {:error, :invalid_token} = Accounts.fetch_mcp_scope("")

      # A session token is a valid credential for a different door. Presenting
      # one here has to fail, or the context column is decoration.
      session_token = Accounts.generate_user_session_token(user)
      assert {:error, :invalid_token} = Accounts.fetch_mcp_scope(session_token)

      {:ok, _} = Accounts.revoke_mcp_token(user, record.id)
      assert {:error, :invalid_token} = Accounts.fetch_mcp_scope(plaintext)
    end
  end

  describe "revoke_mcp_token/2" do
    test "will not let one user revoke another's token" do
      owner = user_fixture()
      stranger = user_fixture()
      {:ok, plaintext, record} = Accounts.mint_mcp_token(owner, "laptop")

      assert {:error, :not_found} = Accounts.revoke_mcp_token(stranger, record.id)
      assert {:ok, _scope} = Accounts.fetch_mcp_scope(plaintext)
    end
  end

  describe "account changes and live tokens" do
    test "changing the email revokes MCP tokens along with sessions" do
      user = user_fixture() |> set_password()
      {:ok, plaintext, _record} = Accounts.mint_mcp_token(user, "laptop")

      {:ok, {_user, _expired}} =
        Accounts.update_user_password(user, %{password: "a brand new password"})

      # Deliberate, and the settings page says so: an account credential change
      # is the account-takeover recovery path, so it has to invalidate every
      # credential, not only the ones with a browser attached. The cost is that
      # an owner reconnects their assistant afterwards.
      assert {:error, :invalid_token} = Accounts.fetch_mcp_scope(plaintext)
      assert Accounts.list_mcp_tokens(user) == []
    end
  end

  describe "list_mcp_tokens/1" do
    test "never returns anything that could be replayed as a credential" do
      user = user_fixture()
      {:ok, _plaintext, _record} = Accounts.mint_mcp_token(user, "laptop")

      [listed] = Accounts.list_mcp_tokens(user)

      assert listed.name == "laptop"
      assert Map.has_key?(listed, :inserted_at)
      assert Map.has_key?(listed, :last_used_at)
      refute Map.has_key?(listed, :token)
    end

    test "excludes tokens from other contexts and other users" do
      user = user_fixture()
      other = user_fixture()

      _session = Accounts.generate_user_session_token(user)
      {:ok, _, _} = Accounts.mint_mcp_token(other, "not mine")

      assert Accounts.list_mcp_tokens(user) == []
    end
  end
end
