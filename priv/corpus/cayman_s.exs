# Corpus car 1 (TK-001): 2007 Porsche Cayman S — the staged-build-list car.
# Sources and hand-read claim rationale: docs/design/corpus.md.
# Run: mix run priv/corpus/cayman_s.exs

Code.require_file("runner.exs", __DIR__)

listing = "https://bringatrailer.com/listing/2007-porsche-cayman-s-3/"

SantoApi.Corpus.Runner.run(%{
  name: "2007 Porsche Cayman S",
  vin: "WP0AB29827U782968",
  dir: Path.join(__DIR__, "cayman_s"),
  artifacts: [
    %{
      file: "listing_page.html",
      kind: :listing,
      mime: "text/html",
      source_url: listing,
      note: "BaT result page snapshot; sold $33,000 on 2017-08-30, lot #5,638"
    },
    %{
      file: "porsche_coa.jpg",
      kind: :document,
      mime: "image/jpeg",
      source_url:
        "https://bringatrailer.com/wp-content/uploads/2017/08/599c9872086d5_Porsche-certificate.jpg",
      note: "Porsche Certificate of Authenticity, photographed in the listing gallery"
    },
    %{
      file: "window_sticker_1.jpg",
      kind: :document,
      mime: "image/jpeg",
      source_url:
        "https://bringatrailer.com/wp-content/uploads/2017/08/599c985420c92_Sales-sticker.jpg",
      note: "Original window sticker, lower panel: colors, assembly point, dealer"
    },
    %{
      file: "window_sticker_2.jpg",
      kind: :document,
      mime: "image/jpeg",
      source_url:
        "https://bringatrailer.com/wp-content/uploads/2017/08/599c98353a78c_Sales-sticker-2.jpg",
      note: "Original window sticker, options panel: prices, total $75,180"
    },
    %{
      file: "carfax_report.jpg",
      kind: :document,
      mime: "image/jpeg",
      source_url:
        "https://bringatrailer.com/wp-content/uploads/2017/08/599ca02a1a81d_1-42.jpg",
      note: "Carfax report p1 run 2017-08-17: two owners FL/PA, clean title history"
    }
  ],
  claims: [
    # CoA first: when two artifacts support the same predicate, facts break
    # ties to the earliest claim, and the CoA states the paint code.
    %{
      predicate: "build.paint_code",
      value: %{"code" => "59", "label" => "Slate Grey Metallic"},
      artifact: "porsche_coa.jpg"
    },
    %{
      predicate: "build.production_date",
      value: "2007-03-26",
      artifact: "porsche_coa.jpg"
    },
    %{
      predicate: "build.paint_code",
      value: %{"code" => nil, "label" => "Slate Grey Metallic"},
      artifact: "window_sticker_1.jpg"
    },
    %{
      predicate: "provenance.delivery_dealer",
      value: %{"name" => "Braman Motorcars", "location" => "West Palm Beach, FL"},
      artifact: "window_sticker_1.jpg"
    },
    %{
      predicate: "observation.mileage",
      value: 41_095,
      scope_date: ~D[2017-08-17],
      artifact: "carfax_report.jpg"
    },
    %{
      predicate: "observation.mileage",
      value: 41_660,
      scope_date: ~D[2017-08-30],
      artifact: "listing_page.html"
    },
    # The sticker states "Final Assembly Point: Uusikaupunki, Finland" —
    # corroborates santo's plant claim, though the strings differ (friction).
    %{
      predicate: "build.plant",
      value: "Uusikaupunki, Finland",
      artifact: "window_sticker_1.jpg"
    },
    %{
      predicate: "event.sale",
      value: %{"venue" => "Bring a Trailer", "price" => 33_000, "currency" => "USD"},
      scope_date: ~D[2017-08-30],
      artifact: "listing_page.html"
    }
  ]
})
