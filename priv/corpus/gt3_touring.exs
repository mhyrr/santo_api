# Corpus car 2 (TK-001): 2018 Porsche 911 GT3 Touring — the paint-to-sample car.
# Sources and hand-read claim rationale: docs/design/corpus.md.
# Run: mix run priv/corpus/gt3_touring.exs

Code.require_file("runner.exs", __DIR__)

listing = "https://bringatrailer.com/listing/2018-porsche-911-gt3-touring-63/"
avd_base = "https://bringatrailer.com/wp-content/uploads/2025/09/2018_porsche_911-gt3-touring_WP0AC2A97JS176473-avd-"

avd = fn n, note ->
  %{
    file: "gt3_avd_#{n}.jpg",
    kind: :document,
    mime: "image/jpeg",
    source_url: "#{avd_base}#{n}-#{Enum.at(["29439", "29445", "29451", "29457"], n - 1)}-scaled.jpg",
    note: note
  }
end

SantoApi.Corpus.Runner.run(%{
  name: "2018 Porsche 911 GT3 Touring",
  vin: "WP0AC2A97JS176473",
  dir: Path.join(__DIR__, "gt3_touring"),
  artifacts: [
    %{
      file: "listing_page.html",
      kind: :listing,
      mime: "text/html",
      source_url: listing,
      note: "BaT result page snapshot; sold $315,000 on 2025-09-24, lot #211,540"
    },
    avd.(1, "VIN Analytics build report p1: model 991-810, production 2018-09-03 Stuttgart, engine DGGA/011148, gearbox G9190/5006293, color code 998 custom"),
    avd.(2, "VIN Analytics build report p2: Z-option 24931 '226/lindgruen, Preparation for Exterior in Custom Color'"),
    avd.(3, "VIN Analytics build report p3: additional equipment"),
    avd.(4, "VIN Analytics build report p4: additional equipment"),
    %{
      file: "factory_data_sticker.jpg",
      kind: :document,
      mime: "image/jpeg",
      source_url:
        "https://bringatrailer.com/wp-content/uploads/2025/09/2018_porsche_911-gt3-touring_IMG_1962-92326-scaled.jpeg",
      note: "Factory vehicle-data sticker in the maintenance booklet: FARBCODE 226, interior 39, DGG/G9190, prod 2085932"
    }
  ],
  claims: [
    # The AVD names the PTS color outright (Z-option 24931: 226/lindgruen);
    # the factory sticker corroborates with FARBCODE 226 alone.
    %{
      predicate: "build.paint_code",
      value: %{"code" => "226", "label" => "Linden Green (lindgruen), paint to sample"},
      artifact: "gt3_avd_2.jpg"
    },
    %{
      predicate: "build.paint_code",
      value: %{"code" => "226", "label" => nil},
      artifact: "factory_data_sticker.jpg"
    },
    %{
      predicate: "build.production_date",
      value: "2018-09-03",
      artifact: "gt3_avd_1.jpg"
    },
    %{
      predicate: "build.plant",
      value: "Stuttgart",
      artifact: "gt3_avd_1.jpg"
    },
    %{
      predicate: "observation.mileage",
      value: 3_600,
      scope_date: ~D[2025-09-24],
      artifact: "listing_page.html"
    },
    %{
      predicate: "event.sale",
      value: %{"venue" => "Bring a Trailer", "price" => 315_000, "currency" => "USD"},
      scope_date: ~D[2025-09-24],
      artifact: "listing_page.html"
    }
  ]
})
