defmodule SantoApi.ApplicationConfigTest do
  use ExUnit.Case, async: true

  test "the non-test Oban configuration is valid" do
    oban_options =
      "config/config.exs"
      |> Config.Reader.read!(env: :dev)
      |> Keyword.fetch!(:santo_api)
      |> Keyword.fetch!(Oban)

    assert :ok = Oban.Config.validate(oban_options)
  end
end
