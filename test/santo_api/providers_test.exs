defmodule SantoApi.ProvidersTest do
  use ExUnit.Case, async: true

  alias SantoApi.Providers
  alias SantoApi.Providers.{Acquisition, Nhtsa, Request, Selector, Vpic}
  alias SantoApi.VpicFixtures

  @vin "WP0CA298X5L001502"

  describe "provider registry" do
    test "routes by capability and normalized identity" do
      assert {:ok, [Vpic]} =
               Providers.for_capability(:generic_specifications, {:vin, @vin})

      assert {:ok, [Nhtsa]} =
               Providers.for_capability(:recall_campaigns, {:vin, @vin})

      assert {:ok, [Nhtsa]} =
               Providers.for_capability(:technical_bulletins, {:vin, @vin})

      assert {:ok, []} = Providers.for_capability(:factory_build, {:vin, @vin})

      assert {:ok, []} =
               Providers.for_capability(
                 :generic_specifications,
                 {:chassis, :porsche, :pre_vin, "81192"}
               )
    end

    test "descriptors expose reviewed access and fulfillment semantics" do
      assert Vpic.descriptor().access_class == :open_data
      assert Vpic.descriptor().required_selectors == []

      assert %{
               fulfillment: :bulk_dataset,
               access_class: :open_data,
               required_selectors: [:marque, :model, :model_year]
             } = Nhtsa.descriptor()
    end

    test "rejects unknown capabilities and providers without creating atoms" do
      assert {:error, {:unknown_capability, "factory_build"}} =
               Providers.for_capability("factory_build", {:vin, @vin})

      assert {:error, {:unknown_provider, "nhtsa_vpic"}} =
               Providers.provider("nhtsa_vpic")
    end
  end

  describe "provider-neutral selectors" do
    test "validates model-population selectors without using request options" do
      assert {:ok, %Selector{} = selectors} =
               Selector.new(%{
                 marque: "porsche",
                 model: %{"code" => "cayman", "label" => nil},
                 model_year: 2007
               })

      assert {:ok, %Request{selectors: ^selectors, options: %{}}} =
               Request.new(:recall_campaigns, {:vin, @vin}, selectors)

      assert {:ok, ^selectors} = Selector.new(Selector.to_map(selectors))

      assert {:error, {:unknown_selectors, [:vendor_model_id]}} =
               Selector.new(%{vendor_model_id: "42"})

      assert {:error, {:invalid_selector, :model_year}} =
               Selector.new(%{model_year: "2007"})
    end

    test "a configured provider without selectors requests input instead of becoming unsupported" do
      assert {:ok, request} = Request.new(:recall_campaigns, {:vin, @vin})
      assert :ok = Nhtsa.supports?(request)

      assert {:pending, %{missing_selectors: [:marque, :model, :model_year]}} =
               Nhtsa.acquire(request)
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
      assert {:ok, _uuid} = Ecto.UUID.cast(acquisition.acquisition_id)
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
