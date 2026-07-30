defmodule SantoApi.ProvidersTest do
  use ExUnit.Case, async: true

  alias SantoApi.Providers
  alias SantoApi.Providers.{Acquisition, Request, Vpic}
  alias SantoApi.VpicFixtures

  @vin "WP0CA298X5L001502"

  describe "provider registry" do
    test "routes by capability and normalized identity" do
      assert {:ok, [Vpic]} =
               Providers.for_capability(:generic_specifications, {:vin, @vin})

      assert {:ok, []} = Providers.for_capability(:factory_build, {:vin, @vin})

      assert {:ok, []} =
               Providers.for_capability(
                 :generic_specifications,
                 {:chassis, :porsche, :pre_vin, "81192"}
               )
    end

    test "rejects unknown capabilities and providers without creating atoms" do
      assert {:error, {:unknown_capability, "factory_build"}} =
               Providers.for_capability("factory_build", {:vin, @vin})

      assert {:error, {:unknown_provider, "nhtsa_vpic"}} =
               Providers.provider("nhtsa_vpic")
    end
  end

  describe "vPIC acquisition" do
    test "preserves the source payload, diagnostics, and acquisition metadata" do
      Req.Test.stub(SantoApi.Vpic, fn conn ->
        Req.Test.json(conn, VpicFixtures.cgt_response())
      end)

      assert {:ok, request} =
               Request.new(:generic_specifications, {:vin, @vin})

      assert {:ok, %Acquisition{} = acquisition} =
               Providers.acquire(:nhtsa_vpic, request)

      assert acquisition.provider == :nhtsa_vpic
      assert acquisition.capability == :generic_specifications
      assert acquisition.coverage == :complete
      assert acquisition.payload["VIN"] == @vin
      assert acquisition.source_url =~ "DecodeVinValues/#{@vin}"
      assert acquisition.media_type == "application/json"
      assert %DateTime{} = acquisition.acquired_at
      assert acquisition.rights_profile == "nhtsa-vpic-open-data-v1"
      assert acquisition.diagnostics["error_code"] == "0"
      assert acquisition.diagnostics["error_text"] =~ "VIN decoded clean"
    end

    test "retains a provider diagnostic as partial coverage" do
      values = %{VpicFixtures.cgt_values() | "ErrorCode" => "5", "ErrorText" => "bad VIN"}

      Req.Test.stub(SantoApi.Vpic, fn conn ->
        Req.Test.json(conn, VpicFixtures.response(values))
      end)

      assert {:ok, request} =
               Request.new(:generic_specifications, {:vin, @vin})

      assert {:ok, acquisition} = Providers.acquire(:nhtsa_vpic, request)

      assert acquisition.coverage == :partial
      assert acquisition.diagnostics == %{"error_code" => "5", "error_text" => "bad VIN"}
    end

    test "rejects capabilities and identity kinds outside vPIC's scope" do
      assert {:ok, factory_request} = Request.new(:factory_build, {:vin, @vin})

      assert {:error, {:unsupported_capability, :factory_build}} =
               Providers.acquire(:nhtsa_vpic, factory_request)

      assert {:ok, chassis_request} =
               Request.new(
                 :generic_specifications,
                 {:chassis, :porsche, :pre_vin, "81192"}
               )

      assert {:error, {:unsupported_identity, :chassis}} =
               Providers.acquire(:nhtsa_vpic, chassis_request)
    end
  end
end
