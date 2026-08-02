ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(SantoApi.Repo, :manual)

# The artifact store is a fixed directory that outlives the run, while
# `System.unique_integer/1` restarts with the VM — so a ref minted today
# collides with yesterday's file and "this ref does not exist yet" tests fail
# at random. Start every run from an empty store.
uploads_dir = Application.fetch_env!(:santo_api, :uploads_dir)

if String.ends_with?(uploads_dir, "santo_api_test_uploads") do
  File.rm_rf!(uploads_dir)
end

File.mkdir_p!(uploads_dir)
