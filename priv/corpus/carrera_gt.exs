# Corpus car 3 (TK-001): 2005 Porsche Carrera GT — the delivery-story car.
# Sources and hand-read claim rationale: docs/design/corpus.md.
# Run: mix run priv/corpus/carrera_gt.exs

Code.require_file("runner.exs", __DIR__)

listing = "https://bringatrailer.com/listing/2005-porsche-carrera-gt-37/"

SantoApi.Corpus.Runner.run(%{
  name: "2005 Porsche Carrera GT",
  vin: "WP0CA298X5L001256",
  dir: Path.join(__DIR__, "carrera_gt"),
  artifacts: [
    %{
      file: "listing_page.html",
      kind: :listing,
      mime: "text/html",
      source_url: listing,
      note: "BaT result page snapshot; sold $4,568,000 on 2026-07-22, lot #252,931"
    },
    %{
      file: "window_sticker.jpg",
      kind: :document,
      mime: "image/jpeg",
      source_url:
        "https://bringatrailer.com/wp-content/uploads/2026/06/2005_porsche_carrera-gt_IMG_2960-27817-scaled.jpeg",
      note:
        "Original window sticker (laminated): Fayence Yellow, Leipzig final assembly, " <>
          "sold-to/ship-to dealer 144 Sonnen Porsche Mill Valley CA, total $448,300"
    },
    %{
      file: "service_invoice_p3.jpg",
      kind: :receipt,
      mime: "image/jpeg",
      source_url:
        "https://bringatrailer.com/wp-content/uploads/2026/06/2005_porsche_carrera-gt_IMG_2961-27822-scaled.jpeg",
      note:
        "Porsche of Colorado Springs invoice #529144 p3 (2024-10-24): DEL. DATE 29APR05, " <>
          "mileage in/out 8798/8803, suspension recall campaign, goodwill tire program"
    },
    %{
      file: "service_invoice_p4.jpg",
      kind: :receipt,
      mime: "image/jpeg",
      source_url:
        "https://bringatrailer.com/wp-content/uploads/2026/06/2005_porsche_carrera-gt_IMG_2962-27828-scaled.jpeg",
      note: "Invoice #529144 p4: totals $4,838.72, RO opened 2024-08-19, ready 2024-10-24"
    }
  ],
  claims: [
    %{
      predicate: "build.paint_code",
      value: %{"code" => nil, "label" => "Fayence Yellow"},
      artifact: "window_sticker.jpg"
    },
    # The listing narrative states the code: "finished in Fayence Yellow (1C1)".
    %{
      predicate: "build.paint_code",
      value: %{"code" => "1C1", "label" => "Fayence Yellow"},
      artifact: "listing_page.html"
    },
    %{
      predicate: "build.plant",
      value: "Leipzig, Germany",
      artifact: "window_sticker.jpg"
    },
    %{
      predicate: "provenance.delivery_dealer",
      value: %{"name" => "Sonnen Porsche", "location" => "Mill Valley, CA"},
      artifact: "window_sticker.jpg"
    },
    %{
      predicate: "provenance.delivery_date",
      value: "2005-04-29",
      artifact: "service_invoice_p3.jpg"
    },
    %{
      predicate: "observation.mileage",
      value: 8_803,
      scope_date: ~D[2024-10-24],
      artifact: "service_invoice_p3.jpg"
    },
    %{
      predicate: "event.service",
      value: %{
        "summary" =>
          "Suspension recall campaign (front/rear wishbones, trailing arms) and " <>
            "new Michelin Pilot Sport Cup 2 tires under the Carrera GT goodwill tire program",
        "performer" => "Porsche of Colorado Springs"
      },
      scope_date: ~D[2024-10-24],
      artifact: "service_invoice_p3.jpg"
    },
    %{
      predicate: "observation.mileage",
      value: 9_200,
      scope_date: ~D[2026-07-22],
      artifact: "listing_page.html"
    },
    %{
      predicate: "event.sale",
      value: %{"venue" => "Bring a Trailer", "price" => 4_568_000, "currency" => "USD"},
      scope_date: ~D[2026-07-22],
      artifact: "listing_page.html"
    }
  ]
})
