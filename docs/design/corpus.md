# Dossier Corpus

*Tranche 2 (evidence_contract.md §11): real documented cars through the full
registry pipeline — ingest, vPIC, artifacts, hand-read claims through the
ratification gate. The friction log at the bottom is the primary output; it is
the input to the extraction design (tranche 3).*

All artifacts entered through `Registry.create_upload_artifact/1` with
`source_url` and a rights note (`manual corpus research, internal use`) in
metadata. All claims entered `proposed → admitted` through
`Registry.propose_claim/2` + `Registry.ratify_claim/1`. No hand-inserted rows.
Ingest scripts live in `priv/corpus/`, one per car, alongside the source files.
The two model corrections run through `Registry.adjudicate_claims/4` from the
re-runnable `priv/corpus/adjudications.exs`; the script never inserts a row
directly.

## Car selection

Criteria from TK-001: VIN visible, documentation artifacts visible in photos,
coverage across the set for PTS paint, a documented delivery story, and the
Cayman S window-sticker car from the original staged-build list
(Carrera GT / 959 / Cayman S).

### 1. 2007 Porsche Cayman S — WP0AB29827U782968

- Listing: https://bringatrailer.com/listing/2007-porsche-cayman-s-3/
  (sold $33,000, 2017-08-30, lot #5,638)
- Why: the exact car the staged-build list named. Window sticker (two pages)
  and Porsche CoA posted in the gallery, service records from new, one-family
  documentation story. The window sticker also carries two facts that stress
  the contract: final assembly point Uusikaupunki, Finland (Valmet-built 987 —
  a plant fact the VIN's identifier data may disagree with) and the sold-to /
  ship-to dealer (Braman Motorcars, W. Palm Beach FL — a delivery-provenance
  fact on a car nobody picked for its delivery story).
- Documents acquired: window sticker p1+p2, Porsche CoA
  (production completion 3/26/2007, Slate Grey Metallic/59, Special Leather
  Terracotta/MB, M97/21 + G87/21, MSRP $74,320), listing page snapshot.

### 2. 2018 Porsche 911 GT3 Touring — WP0AC2A97JS176473

- Listing: https://bringatrailer.com/listing/2018-porsche-911-gt3-touring-63/
  (sold $315,000, 2025-09-24, lot #211,540)
- Why: the paint-to-sample criterion. PTS Linden Green documented twice,
  independently: a VIN Analytics build report (four pages: model 991-810,
  production 2018-09-03 Stuttgart, engine DGGA/011148, gearbox G9190/5006293,
  full option list incl. Z-option 24931 "226/lindgrün, Preparation for
  Exterior in Custom Color") and the factory vehicle-data sticker in the
  maintenance booklet (FARBCODE 226, interior 39, DGG/G9190). Same predicate,
  two independent artifacts → a real agreement case for the comparison view.
- Documents acquired: AVD build report p1–p4, maintenance-booklet factory
  data sticker photo, listing page snapshot.

### 3. 2005 Porsche Carrera GT — WP0CA298X5L001256

- Listing: https://bringatrailer.com/listing/2005-porsche-carrera-gt-37/
  (sold $4,568,000, 2026-07-22, lot #252,931)
- Why: the delivery-story criterion, and an original staged-build-list marque
  (Carrera GT). Delivered new to Sonnen Porsche, Mill Valley CA (listing
  narrative + window sticker); a Porsche of Colorado Springs service invoice
  (2024-10-24) independently records `DEL. DATE 29APR05` in the dealer system
  plus the suspension-recall campaign completion and mileage in/out 8798/8803 —
  which gives the corpus a real `event`-scoped claim and a mileage history
  (8,803 @ 2024 vs ~9,200 @ 2026) to test "observations are history, not
  conflict" (contract §4).
- Documents acquired: window sticker (two photos), service invoice p3, second
  invoice page, two Porsche letterhead service invoices, listing page snapshot.

## Research friction (acquisition, not contract)

- bringatrailer.com blocks both Claude's WebFetch and the Anthropic search
  crawler at the domain level (`allowed_domains: [bringatrailer.com]` returns
  "not accessible to our user agent"). A headless Playwright browser fetches
  listing pages and gallery images without obstruction.
- BaT search indexes titles only: "kardex" — a word that appears in hundreds
  of listing bodies — returns 0 results, and the listings-filter JSON API has
  the same limit. Finding documentation-rich cars means knowing the car first;
  content search across listings is not available to us.
- BaT gallery photos carry no captions and mostly opaque filenames
  (`fullsizeoutput_1a7f.jpeg`). Premium listings sometimes label document
  scans (`..._WP0AC2A97JS176473-avd-1`), older listings sometimes
  (`Porsche-certificate.jpg`), but generally document photos are found by
  eyeballing thumbnails. An extraction pipeline will need a cheap
  "is this image a document?" classifier before any LLM reads.

## Per-car claim record

### 2007 Cayman S (`priv/corpus/cayman_s.exs`)

Artifacts: listing snapshot, CoA, window sticker p1+p2, Carfax p1 — all
`:listing`/`:document` with source URLs and rights notes.

| Claim | Value | Evidence |
|---|---|---|
| build.paint_code | 59 / Slate Grey Metallic | CoA |
| build.paint_code | (label only) Slate Grey Metallic | window sticker p1 |
| build.production_date | 2007-03-26 | CoA |
| provenance.delivery_dealer | Braman Motorcars, West Palm Beach FL | window sticker p1 (sold-to/ship-to dealer 935) |
| build.plant | Uusikaupunki, Finland | window sticker p1 (final assembly point) |
| observation.mileage | 41,095 @ 2017-08-17 | Carfax |
| observation.mileage | 41,660 @ 2017-08-30 | listing |
| event.sale | BaT, $33,000 @ 2017-08-30 | listing |

Unclaimed, deliberately: MSRP (see friction), option list (see friction),
title-brand absence (Carfax "no problems reported" is absence of evidence,
not evidence of absence — no honest value for `legal.title_brand` from it),
ownership chain (two owners FL→PA on the Carfax; no vocabulary and it is
design.md layer 1–2 territory).

Adjudicated in TK-003: santo decodes the 987 as model `boxster/987`
(auto-admitted); vPIC says Cayman (proposed). The CoA-backed adjudication admits
`cayman`, supersedes santo's claim without deleting it, and the fact now renders
`cayman / verified`. See friction #1.

### 2018 911 GT3 Touring (`priv/corpus/gt3_touring.exs`)

Artifacts: listing snapshot, VIN Analytics build report p1–p4, factory
vehicle-data sticker photographed in the maintenance booklet.

| Claim | Value | Evidence |
|---|---|---|
| build.paint_code | 226 / Linden Green (lindgrün), paint to sample | AVD p2 (Z-option 24931) |
| build.paint_code | 226 (code only) | factory data sticker (FARBCODE) |
| build.production_date | 2018-09-03 | AVD p1 |
| build.plant | Stuttgart | AVD p1 |
| observation.mileage | 3,600 @ 2025-09-24 | listing |
| event.sale | BaT, $315,000 @ 2025-09-24 | listing |

Unclaimed, deliberately: engine/gearbox serials (DGGA 011148, G9190 5006293
on the AVD — `build.engine_number` vocabulary headroom, not needed tonight),
the 117-line option list (friction #5), warranty start 2018-10-27 as a
delivery date (friction #7), the model itself (friction #6).

Notes: the sale listed a "window sticker" but no Monroney was found among
the 279 unlabeled gallery photos — the third-party AVD build report may be
what the seller meant. Santo has no model/variant claim for the 991 at all,
so this GT3's `identity.model` fact is vPIC's unverified "911" and nothing
in the registry says "GT3" — the same vendored-data thinness Greg hit with
his 981 Boxster probe, from a $315k car's seat.

### 2005 Carrera GT (`priv/corpus/carrera_gt.exs`)

Artifacts: listing snapshot, window sticker (`:document`), service invoice
p3+p4 (`:receipt`).

| Claim | Value | Evidence |
|---|---|---|
| build.paint_code | (label only) Fayence Yellow | window sticker |
| build.paint_code | 1C1 / Fayence Yellow | listing narrative |
| build.plant | Leipzig, Germany | window sticker (final assembly point) |
| provenance.delivery_dealer | Sonnen Porsche, Mill Valley CA | window sticker (sold-to/ship-to dealer 144) |
| provenance.delivery_date | 2005-04-29 | invoice p3 (`DEL. DATE 29APR05` in the dealer system) |
| observation.mileage | 8,803 @ 2024-10-24 | invoice p3 (mileage out) |
| event.service | recall campaign + goodwill tires, Porsche of Colorado Springs | invoice p3 |
| observation.mileage | ~9,200 @ 2026-07-22 | listing (seller-approximate) |
| event.sale | BaT, $4,568,000 @ 2026-07-22 | listing |

Unclaimed, deliberately: MSRP/total ($440,000 / $448,300 — friction #4
again), the N/C option list, gas-guzzler tax, the invoice's line-item
parts. The mileage pair (invoice 8,803 → listing ~9,200) sits as history,
not conflict — though only because both claims share the Vin Santo party
(friction #2); the scope-date-aware comparison §4 promises is untested by
machinery, only by accident.

The model conflict mirrors car 1, inverted: santo says `carrera_gt/980`
(admitted, **right**), vPIC says `911` (proposed — NHTSA files the Carrera
GT under 911). The window-sticker-backed adjudication keeps santo's claim and
supersedes vPIC's without deleting it. The paired cases prove neither source can
be blanket-trusted; each conflict is decided from vehicle-specific evidence.

## Friction log — where the contract bends

1. **Resolved in TK-003 — admitted claims can be corrected without erasure.** Santo's vendored
   987 data claims `identity.model = boxster` for a Cayman VIN and enters
   `:admitted` on santo's authority. The adjudication now admits the correct
   vPIC claim and flips santo's losing claim to `:superseded`; both remain in
   history. The upstream santo problem remains: the 987 platform can't
   distinguish Cayman from Boxster by pos-7 body code alone in its current
   table, so the defensible santo claim may be the *platform* (987), not the
   model. Greg's Boxster probe (WP0CA2A87FS120563 → "year and not much else")
   is the same vendored-data thinness from the other side.
   `Registry.adjudicate_claims/4` owns the transaction
   (`lib/santo_api/registry.ex:160`); the immutable record shape lives in
   `lib/santo_api/registry/adjudication.ex:18`, and the database rejects updates
   and deletes (`priv/repo/migrations/20260731163000_create_adjudications.exs:67`).

2. **Resolved at the comparison boundary; historical party attribution remains
   debt.** Before TK-003 every bench-path claim was asserted by the Vin Santo
   party, so the CoA and window sticker each stating Slate Grey rendered as
   `single_source (2 claims)`. For document-borne claims the useful independence
   lives in the artifacts. Re-attributing the live corpus would duplicate
   immutable, party-hashed claims or require roughly thirty provenance
   adjudications, so TK-003 took its explicit fallback: claims backed by distinct
   artifacts count as distinct sources (`lib/santo_api/registry.ex:519`). New
   writes can supply a real asserting party through `Registry.propose_claim/3`;
   the two-argument operator default remains for the existing bench. This makes
   the CoA + window-sticker paint pair an agreement now; observed claims at
   different dates remain `history`, preserving §4. A future tier-3
   surface must either migrate the historical attributions deliberately or
   continue composing independence from the artifact side of the basis.

3. **Plant naming has no equivalence rule.** Santo says
   `"Uusikaupunki (Valmet; Finland)"`, the window sticker says
   `"Uusikaupunki, Finland"` — same fact, unequal strings, and only exact
   equality is available for `build.plant`. Masked today by friction #2
   (same party → single_source), but the moment parties are real this
   becomes a false conflict. Plants likely want the code+label treatment
   paint codes got.

4. **"MSRP" is not one fact.** The window sticker totals $75,180; the CoA
   states $74,320. Same car, both documents right: base+options+destination
   vs. without destination. A naive `commercial.msrp` predicate would
   manufacture a conflict out of a definitional difference. Left unclaimed;
   extraction will need predicates whose definitions are pinned to the
   document type, not the word "MSRP".

5. **Option lists don't fit the claim shape yet.** The window sticker prices
   14 options; the CoA lists 15 including four "exclusive options" the
   sticker only groups under one dollar figure. Per-option claims would need
   an option vocabulary (codes appear only on modern documents — the GT3's
   AVD has them; 2007 documents have prose names); a single list-valued claim
   would make every partial disagreement one big conflict. Deferred to the
   extraction/logbook design, as the ticket anticipated.

6. **`identity.model` has three vocabularies and no mapping.** Santo's codes
   are its own atoms (`boxster`, `carrera_gt`), vPIC says `911`, the GT3's
   build report says `911 GT3` / model code `991-810`. A document-borne model
   claim would have to invent a code, so the GT3 carries none — and its model
   fact is an unverified vPIC `911`. The closed vocabulary (fork B) closed the
   *predicates* but left each predicate's *value space* open; for
   identity-adjacent predicates the value space needs vendoring too.

7. **Delivery is encoded obliquely on modern documents.** The GT3's AVD has
   no delivery line — only `Warranty Start: 2018-10-27`, which in practice is
   the retail delivery date. Claiming it as `provenance.delivery_date` would
   be interpretation, not transcription, so it stays unclaimed. Extraction
   (tranche 3) will face this constantly: the fact is on the page but under a
   different name, and the LLM will be tempted to normalize. The contract
   needs a stance on proxy facts — likely a claim carrying the document's own
   term in `method_meta` with the interpretation ratified explicitly.

8. **Resolved in TK-003 — contradictory external proposals have an adjudication
   path.** The Cayman decision admits vPIC and supersedes santo; the Carrera GT
   decision keeps santo and supersedes vPIC. Both go through the same Registry
   transaction and the re-runnable corpus script
   (`priv/corpus/adjudications.exs:14`), so source preference cannot leak into
   the mechanism.

9. **Resolved in TK-003 — equivalent values prefer the richest face.** The CGT has two
   admitted paint claims — label-only from the window sticker, code+label
   from the listing. The fact used to show the label-only value because it was
   ratified seconds earlier; claim arrival order is pipeline noise. Precedence
   now prefers the richest value among equivalent claims (most non-nil fields,
   then earliest), selecting `1C1 / Fayence Yellow` without changing
   disagreement semantics (`lib/santo_api/registry.ex:469`).

10. **Evidence requests never fired.** All three VINs ingested clean, so no
    evidence request exists anywhere in the corpus — the machinery only
    triggers on disputed identity. The window sticker and CoA evidence
    classes named in §6 have no path that ever *asks* for them: a car with an
    unverified paint fact doesn't open a request for the document class that
    would verify it. If the dossier workflow is to drive acquisition
    (§6's monetization seam), something must create requests from coverage
    gaps, not just identity disputes.

## What the corpus says, in one paragraph

The pipeline now carries correction as well as admission: three cars, fifteen
artifacts, thirty-odd claims, and two evidence-backed adjudications, all through
Registry functions and re-runnable scripts. The Cayman and Carrera GT mirror
cases resolve in opposite directions without deleting either losing claim; CoA
+ window-sticker paint renders agreement from distinct artifact basis; richer
equivalent values win the fact face. Historical human claims still name Vin
Santo because rewriting an immutable ledger is a separate provenance migration,
now documented rather than concealed. Extraction can ship proposals into a gate
that can correct them.
