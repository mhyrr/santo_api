defmodule SantoApi.Providers.VpicTest do
  use ExUnit.Case, async: true

  alias SantoApi.Providers.Vpic
  alias SantoApi.VpicFixtures

  describe "facts/1" do
    test "maps a clean decode onto vocabulary predicates, normalized" do
      assert Vpic.facts(VpicFixtures.cgt_values()) |> Enum.sort() ==
               Enum.sort([
                 {"identity.marque", "porsche"},
                 {"identity.model", %{"code" => "911", "label" => nil}},
                 {"identity.model_year", 2005}
               ])
    end

    test "a nonzero ErrorCode yields no facts" do
      values = %{VpicFixtures.cgt_values() | "ErrorCode" => "5"}
      assert Vpic.facts(values) == []
    end

    test "blank or absent fields yield no facts for them" do
      values = Map.merge(VpicFixtures.cgt_values(), %{"Model" => "", "ModelYear" => nil})
      predicates = Vpic.facts(values) |> Enum.map(&elem(&1, 0))

      assert predicates == ["identity.marque"]
    end
  end

  describe "fetch/1" do
    test "returns the single Results entry as payload" do
      Req.Test.stub(SantoApi.Vpic, fn conn ->
        assert conn.request_path =~ "WP0CA298X5L001502"
        Req.Test.json(conn, VpicFixtures.cgt_response())
      end)

      assert {:ok, %{payload: payload, url: url}} = Vpic.fetch("WP0CA298X5L001502")
      assert payload["Model"] == "911"
      assert url =~ "DecodeVinValues/WP0CA298X5L001502"
    end

    test "transport errors and non-200s are errors" do
      Req.Test.stub(SantoApi.Vpic, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, _} = Vpic.fetch("WP0CA298X5L001502")

      Req.Test.stub(SantoApi.Vpic, fn conn ->
        Plug.Conn.send_resp(conn, 500, "boom")
      end)

      assert {:error, _} = Vpic.fetch("WP0CA298X5L001502")
    end
  end
end
