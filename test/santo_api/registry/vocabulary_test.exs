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
    end

    test "the vocabulary is closed: unknown predicates are rejected" do
      assert {:error, :unknown_predicate} = Vocabulary.validate("build.paint_code", "L041")
    end
  end

  describe "scope_kind/1" do
    test "every v1 predicate is factory-scoped" do
      for predicate <- Vocabulary.predicates() do
        assert Vocabulary.scope_kind(predicate) == :factory
      end
    end

    test "unknown predicate has no scope" do
      assert Vocabulary.scope_kind("observation.mileage") == :error
    end
  end
end
