defmodule SantoApi.DistributionTest do
  use ExUnit.Case, async: true

  alias SantoApi.Distribution

  setup do
    payload = %{
      title: "2007 Porsche Cayman S",
      date: "Aug 9, 2026",
      headline: "Back from alignment, finally sitting right.",
      details: [
        %{label: "Shop", value: "Flat Six Works"},
        %{label: "Odometer", value: "48,291 mi"}
      ],
      url: "https://example.test/v/cayman/updates/one",
      car_url: "https://example.test/v/cayman",
      photo: nil,
      photo_url: "https://example.test/photo.jpg",
      badge_url: "https://example.test/v/cayman/badge.svg",
      badge_detail: "Öhlins Road & Track · RE-71RS"
    }

    %{payload: payload}
  end

  test "forum snippets carry the owner copy, lead photo, details, and canonical link", %{
    payload: payload
  } do
    markdown = Distribution.forum_snippet(payload, :markdown)
    bbcode = Distribution.forum_snippet(payload, :bbcode)

    assert markdown =~ "## 2007 Porsche Cayman S"
    assert markdown =~ "![2007 Porsche Cayman S](https://example.test/photo.jpg)"
    assert markdown =~ "**Shop:** Flat Six Works"
    assert markdown =~ "[View this update on Vin Santo](#{payload.url})"

    assert bbcode =~ "[img]https://example.test/photo.jpg[/img]"
    assert bbcode =~ "[b]Odometer:[/b] 48,291 mi"
    assert bbcode =~ "[url=#{payload.url}]View this update on Vin Santo[/url]"
  end

  test "the named share-card transform returns a 4:5 metadata-free JPEG", %{payload: payload} do
    assert {:ok, <<0xFF, 0xD8, _rest::binary>> = bytes} = Distribution.share_card(payload)
    assert {:ok, image} = Image.open(bytes)
    assert Image.shape(image) == {1080, 1350, 3}
  end

  test "the badge is valid escaped SVG and both embed formats link to the car", %{
    payload: payload
  } do
    svg = Distribution.badge_svg(%{payload | title: "Porsche & Cayman"})

    assert svg =~ "Porsche &amp; Cayman"
    refute svg =~ "Porsche & Cayman</text>"

    assert Distribution.badge_embed(payload, :html) =~ ~s(href="#{payload.car_url}")
    assert Distribution.badge_embed(payload, :bbcode) =~ "[url=#{payload.car_url}]"
  end
end
