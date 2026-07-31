defmodule SantoApi.Registry.VocabularyTest do
  use ExUnit.Case, async: true

  alias SantoApi.Registry.Vocabulary

  describe "validate/2" do
    test "accepts every v1 predicate with a well-formed value" do
      assert :ok = Vocabulary.validate("identity.marque", "porsche")
      assert :ok = Vocabulary.validate("identity.model", %{"code" => "959", "label" => "959"})
      assert :ok = Vocabulary.validate("identity.model", %{"code" => "959", "label" => nil})
      assert :ok = Vocabulary.validate("identity.model_year", 1988)
      assert :ok = Vocabulary.validate("identity.market", "row")
      assert :ok = Vocabulary.validate("identity.market", "us")
      assert :ok = Vocabulary.validate("build.plant", "Stuttgart-Zuffenhausen")
      assert :ok = Vocabulary.validate("build.variant", "sport")
    end

    test "rejects malformed values" do
      assert {:error, _} = Vocabulary.validate("identity.model_year", "1988")
      assert {:error, _} = Vocabulary.validate("identity.market", "unknown")
      assert {:error, _} = Vocabulary.validate("identity.marque", :porsche)
      assert {:error, _} = Vocabulary.validate("identity.model", %{"code" => nil, "label" => "x"})
      assert {:error, _} = Vocabulary.validate("observation.mileage", -1)
      assert {:error, _} = Vocabulary.validate("observation.mileage", "43210")
    end

    test "the vocabulary is closed: unknown predicates are rejected" do
      assert {:error, :unknown_predicate} = Vocabulary.validate("legal.lien_holder", "a bank")
    end

    test "paint code carries code and/or label — documents differ on which they state" do
      # CoA states "Slate Grey Metallic/59"; the window sticker states only the label.
      assert :ok =
               Vocabulary.validate("build.paint_code", %{
                 "code" => "59",
                 "label" => "Slate Grey Metallic"
               })

      assert :ok = Vocabulary.validate("build.paint_code", %{"code" => "226", "label" => nil})
      assert :ok = Vocabulary.validate("build.paint_code", %{"code" => nil, "label" => "Fayence Yellow"})
      assert {:error, _} = Vocabulary.validate("build.paint_code", %{"code" => nil, "label" => nil})
      assert {:error, _} = Vocabulary.validate("build.paint_code", "L041")
    end

    test "production and delivery dates are ISO dates" do
      assert :ok = Vocabulary.validate("build.production_date", "2007-03-26")
      assert :ok = Vocabulary.validate("provenance.delivery_date", "2005-04-29")
      assert {:error, _} = Vocabulary.validate("build.production_date", "3/26/2007")
      assert {:error, _} = Vocabulary.validate("provenance.delivery_date", "29APR05")
    end

    test "delivery dealer names the dealer, location optional" do
      assert :ok =
               Vocabulary.validate("provenance.delivery_dealer", %{
                 "name" => "Braman Motorcars",
                 "location" => "West Palm Beach, FL"
               })

      assert :ok =
               Vocabulary.validate("provenance.delivery_dealer", %{
                 "name" => "Sonnen Porsche",
                 "location" => nil
               })

      assert {:error, _} =
               Vocabulary.validate("provenance.delivery_dealer", %{"name" => nil, "location" => "x"})
    end

    test "service events carry a summary, performer optional" do
      assert :ok =
               Vocabulary.validate("event.service", %{
                 "summary" => "Suspension recall campaign; new tires",
                 "performer" => "Porsche of Colorado Springs"
               })

      assert :ok = Vocabulary.validate("event.service", %{"summary" => "Oil change", "performer" => nil})
      assert {:error, _} = Vocabulary.validate("event.service", %{"summary" => nil, "performer" => "x"})
    end
  end

  describe "scope_kind/1" do
    test "identity and build predicates are factory-scoped, observations are observed" do
      assert Vocabulary.scope_kind("identity.marque") == :factory
      assert Vocabulary.scope_kind("build.variant") == :factory
      assert Vocabulary.scope_kind("observation.mileage") == :observed
    end

    test "provenance is factory-tense; service events are event-scoped" do
      assert Vocabulary.scope_kind("build.paint_code") == :factory
      assert Vocabulary.scope_kind("build.production_date") == :factory
      assert Vocabulary.scope_kind("provenance.delivery_dealer") == :factory
      assert Vocabulary.scope_kind("provenance.delivery_date") == :factory
      assert Vocabulary.scope_kind("event.service") == :event
    end

    test "unknown predicate has no scope" do
      assert Vocabulary.scope_kind("legal.lien_holder") == :error
    end
  end

  describe "equivalent?/3" do
    test "paint codes agree on code when both state one, else on label" do
      slate_coa = %{"code" => "59", "label" => "Slate Grey Metallic"}
      slate_sticker = %{"code" => nil, "label" => "Slate Grey Metallic"}
      linden = %{"code" => "226", "label" => "Linden Green"}
      linden_bare = %{"code" => "226", "label" => nil}

      assert Vocabulary.equivalent?("build.paint_code", linden, linden_bare)
      assert Vocabulary.equivalent?("build.paint_code", slate_coa, slate_sticker)
      refute Vocabulary.equivalent?("build.paint_code", slate_coa, linden)
    end
  end
end
