defmodule SantoApi.TermsTest do
  use ExUnit.Case, async: true

  alias SantoApi.Terms

  test "structs become plain maps with sanitized fields" do
    assert %{"marque" => "porsche", "model" => ["959", "959"]} =
             Terms.sanitize(%Santo.Decoded{marque: :porsche, model: {:"959", "959"}})
  end

  test "tuples become lists, atoms become strings, nil and booleans survive" do
    assert Terms.sanitize({:bad_length, 8}) == ["bad_length", 8]

    assert Terms.sanitize(year_narrowed_by: :production_window) == [
             ["year_narrowed_by", "production_window"]
           ]

    assert Terms.sanitize(%{key: nil, other: true}) == %{"key" => nil, "other" => true}
  end
end
