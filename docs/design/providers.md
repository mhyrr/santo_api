# Provider System

*Research and first architecture pass, 2026-07-30. Providers acquire evidence;
they do not decide vehicle facts.*

## 1. Decision

Build the provider system around **capabilities**, not vendors.

A provider answers one or more bounded questions:

- What identity can this identifier defend?
- What did the manufacturer build?
- What was observed at a particular time?
- What legal, safety, service, or market events have been reported?

The answer to a lookup is an immutable source snapshot with coverage diagnostics
and use rights. It is not a fact update. Provider-specific interpreters can later
turn that snapshot into proposed claims; ratification and the materialized facts
projection remain in `SantoApi.Registry`.

This boundary matters because source authority is capability-specific. Porsche is
authoritative about its production records, not the car's present condition.
An inspection can describe current engine numbers, not prove every prior engine.
A listing records what a seller asserted on a date, not what the registry should
believe forever.

## 2. The product benchmark

### Carfax

Carfax's advantage is its reporting network. It says it has more than 151,000
sources and 35 billion records, including government agencies, auctions, police
and fire departments, fleets, rental companies, and service shops. Its report can
include title, owner count, odometer, accident, service, usage, and recall data,
but Carfax also says unreported events will be absent.

Vin Santo will not match that event-feed coverage at launch. Claiming otherwise
would be brochure math. We can replace the *buyer's decision surface* before we
replace the network:

1. Preserve each source response and show where it came from.
2. Distinguish factory configuration from time-scoped observations.
3. Show disagreement and missing coverage instead of turning both into a green
   check.
4. Add the high-value collector evidence Carfax does not hold: PPS/CTC, build
   sheets, serial verification, inspections, receipts, prior listings, and
   current-condition photographs.
5. Keep the record alive after the transaction so each owner inherits a better
   history than the previous one received.

Carfax can remain an evidencing artifact while Vin Santo becomes the durable
record. It is actually replaced when a new Carfax pull adds little to the record,
not when we stop mentioning the fox.

Sources:

- [Carfax company and data-source overview](https://www.carfax.com/company/about)
- [What a Carfax report can contain and its reporting limitation](https://support.carfax.com/article/what-s-on-a-carfax-report-and-how-can-it-help-me)
- [Carfax Service Network participation gap](https://support.carfax.com/article/why-is-my-recent-service-not-showing-up/)
- [Carfax service-shop program](https://www.carfaxserviceshops.com/)

### Bring a Trailer

BaT's detail comes from editorial assembly: seller answers, a custom-written
listing, photos and video, maintenance records, a vehicle-history report, and a
public comment thread. BaT itself says it relies on sellers for vehicle and title
information and cannot independently verify every assertion.

Vin Santo should not imitate the page. It should make the page obsolete as the
only place where the detail exists:

- one chassis record across every sale;
- factory configuration beside current configuration;
- a cited event timeline, not a paragraph that must be re-read;
- prior photos and odometer observations aligned by date;
- modifications, reversals, repairs, and recurring defects carried forward;
- conflicts and open evidence requests visible before bidding;
- each source claim traceable to its artifact and asserting party.

Comments are valuable discovery material, but they are proposed claims until
evidenced. A knowledgeable commenter can find the problem; they do not become an
authority by having a good username.

BaT is not an ingest provider without a commercial agreement. Its current terms
prohibit building a business from, redistributing, or making commercial use of
its services or content. The near-term paths are licensed aggregators, direct
auction partnerships, and artifacts supplied by an owner for a dossier. Do not
build a BaT scraper and call the legal problem a backlog item.

Sources:

- [How BaT listings are assembled](https://bringatrailer.com/how-bat-works)
- [Representative Porsche listing with window sticker, CoA, records, Carfax, photos, and prior BaT history](https://bringatrailer.com/listing/2007-porsche-cayman-s-3/)
- [BaT Terms of Use](https://bringatrailer.com/terms-of-use/)

## 3. Capability vocabulary

Keep this list closed and small, as with claim predicates. Add a capability when
a genuinely different question or fulfillment path appears.

| Capability | Question answered | Typical scope |
|---|---|---|
| `vin_identity` | What can the identifier itself defend? | timeless |
| `generic_specifications` | What specifications apply to this VIN pattern or model? | reference |
| `factory_build` | What colors, options, packages, serials, and MSRP were recorded as built? | factory |
| `title_history` | What titles, brands, and title-state changes were reported? | event |
| `odometer_history` | What mileage readings were reported, when, and by whom? | observed |
| `total_loss_history` | Was a total loss, junk, or salvage event reported? | event |
| `theft_status` | Was a theft reported, and is it unresolved? | observed/event |
| `accident_history` | What damage or collision event was reported? | event |
| `service_history` | What maintenance or repair was documented? | event |
| `inspection` | What did a named inspector observe on a date? | observed |
| `recall_campaigns` | Which campaigns may apply to the model population? | reference |
| `open_recall_status` | Which unrepaired recalls did the manufacturer report for this VIN? | observed |
| `listing_history` | Where, when, at what mileage and asking price was this car listed? | observed/event |
| `auction_history` | What auction result, high bid, and sale evidence were published? | event |

`recall_campaigns` and `open_recall_status` must remain separate. NHTSA's public
API returns campaigns by year/make/model; its consumer VIN lookup asks
participating manufacturers for VIN-specific unrepaired recalls, omits repaired
recalls, and is not a bulk API.

## 4. Provider contract

The first code slice uses three operations:

```elixir
descriptor = provider.descriptor()
:ok | {:error, reason} = provider.supports?(request)
{:ok, acquisition} | {:pending, fulfillment} | {:error, reason} =
  provider.acquire(request)
```

### Descriptor

Static, inspectable metadata:

- stable provider id and display name;
- supported capabilities and identity kinds;
- fulfillment mode: `sync_api | async_order | human_upload`;
- billing mode: `free | metered | quoted`;
- broad market and model-year coverage;
- provider documentation URL.

Descriptors are routing hints, not a claim that every vehicle is covered.

### Request

A request contains:

- one capability;
- one normalized identity (`Santo.Identity.key/1` output);
- capability-specific options.

Paid providers are never selected merely because they advertise a capability.
The future orchestrator must require an explicit billing authorization for a
metered acquisition. A provider lookup is an external action with a real cost.

### Acquisition

An answered lookup contains:

- provider and capability;
- `coverage`: `complete | partial | none | unknown`;
- the original payload or file reference;
- source URL and media type;
- acquisition time;
- source diagnostics, including vendor error codes;
- the use-rights snapshot under which it was acquired.

`coverage: none` is a successful acquisition when the provider answered that it
has no data. The response is still evidence of what was checked and when. It is
never translated into "clean history."

`{:error, reason}` means the lookup itself failed: transport, authentication,
contract, billing, or invalid request. Failed attempts do not become evidence
artifacts, though they should eventually become provider-run telemetry.

`{:pending, fulfillment}` covers PPS orders, CTC inspections, and other manual or
asynchronous sources. Manual evidence is not a second-class exception in this
domain; much of the best evidence arrives in the mail or on a lift.

### Interpretation

Acquisition and interpretation are separate:

```text
request → provider → immutable snapshot → interpreter → proposed claims
```

The provider wrapper understands transport and source diagnostics. The
interpreter understands the provider's schema and the registry vocabulary. The
registry validates and persists claims. This keeps a payload available for
re-interpretation after the vocabulary improves and prevents vendor fields from
quietly becoming canonical facts.

## 5. Source landscape

| Source | Capabilities | Access and coverage | Treatment |
|---|---|---|---|
| Santo | `vin_identity` | Local deterministic library; includes pre-standard chassis identities and disputes | The only automatic admitted identity claims |
| NHTSA vPIC | `generic_specifications` | Public API; manufacturer 565 submissions; mainly 1981+ US-sale/import vehicles; rate controlled; downloadable PostgreSQL decoder database | Reference snapshot with error diagnostics, never factory build proof |
| Porsche PPS | `factory_build` | All Porsche street-vehicle model years; $150; mailed in an estimated 6–8 weeks in the US; excludes serials, owners, warranty history, dealer-installed/Sonderwunsch work | High-authority factory artifact, manual fulfillment |
| Porsche CTC | `factory_build`, `inspection` | Eligible classics; starts at $500; dealer inspection; verifies current engine/transmission numbers against original records and includes photographs | Factory claims plus dated current observations; do not collapse them together |
| Porsche Monroney | `factory_build` | Free through My Porsche for eligible MY2019+ owners | Owner-authorized factory artifact |
| DataOne | `generic_specifications`, `factory_build` | Commercial API advertises VIN-installed options, colors, packages, option pricing, and as-built MSRP; coverage and OEM license terms require qualification | Benchmark against known Porsche documents before integration |
| MonroneyLabels | `factory_build` | API exposes green/yellow/red availability; yellow explicitly lacks VIN-installed options; Porsche is listed | Use green for automated factory claims; yellow is a coverage diagnostic and evidence request |
| NMVTIS via approved provider | `title_history`, `odometer_history`, `total_loss_history` | Federal system fed by states, insurers, junk and salvage entities; deliberately concise; commercial single/batch access through approved providers | Legal/history backbone; no repair, recall, or routine accident inference |
| VINData | NMVTIS plus advertised theft, accident, inspection, condition, and build products | Approved NMVTIS provider with commercial API and JSON/PDF batch delivery | Best first startup-accessibility conversation; benchmark non-NMVTIS products separately |
| Experian Auto AccuSelect / AutoCheck | Broad title, ownership, odometer, accident, auction, service, recall, theft, and usage attributes | Commercial contract and configurable real-time API; Experian advertises extensive private accident and auction sources | Strongest single-vendor Carfax replacement candidate; do not confuse breadth with transparent provenance |
| NHTSA recalls | `recall_campaigns`; limited consumer `open_recall_status` | Public campaign API is year/make/model. VIN lookup is single-use, only supported manufacturers, generally unrepaired recalls within 15 years; NHTSA says it is not for bulk VIN lookup | Use public API for campaign reference; license a commercial VIN-status source for production |
| MarketCheck | `listing_history` | Commercial API; 17-character VIN; US/Canada; listings observed since 2015; price, mileage, dealer, dates, detail pages and some images/options | Strong mainstream/dealer chronology; each listing remains a dated seller claim |
| CLASSIC.COM | `listing_history`, `auction_history` | Licensed partner API; collector taxonomy; searches VIN or chassis/serial; up to five years of licensed sales history | Better collector and pre-1981 fit than MarketCheck; first auction-data outreach |
| BaT and other auction houses | `listing_history`, `auction_history` | Rich public pages but reuse rights vary; BaT commercial reuse requires agreement | Direct partnership target, not an unlicensed scraper |
| Owner/shop documents | `service_history`, `inspection`, `factory_build`, and more | Upload, forwarding address, shop integrations, dossier intake | The compounding proprietary corpus and correction channel |

Sources:

- [vPIC API purpose and rate control](https://vpic.nhtsa.dot.gov/api/)
- [vPIC standalone PostgreSQL database](https://vpic.nhtsa.dot.gov/downloads/)
- [Porsche PPS and CTC contents](https://vehicledocumentation.porsche.com/usa)
- [Porsche documentation pricing, coverage, and delivery FAQ](https://vehicledocumentation.porsche.com/usa/faqs)
- [Porsche API access is partner-only](https://developer.porsche.com/faq)
- [DataOne VIN Decoder API](https://www.dataonesoftware.com/web-services-vin-decoder-api)
- [MonroneyLabels availability API](https://monroneylabels.com/docs/light_color)
- [What NMVTIS includes and excludes](https://vehiclehistory.bja.ojp.gov/nmvtis_understandingvhr)
- [Approved NMVTIS providers](https://vehiclehistory.bja.ojp.gov/nmvtis_vehiclehistory)
- [VINData commercial APIs](https://www.vindata.com/apis)
- [Experian Auto AccuSelect data elements](https://www.experian.com/automotive/auto-accuselect)
- [NHTSA recall API and datasets](https://www.nhtsa.gov/nhtsa-datasets-and-apis)
- [NHTSA VIN-lookup limits](https://www.nhtsa.gov/recalls)
- [MarketCheck VIN history](https://docs.marketcheck.com/docs/get-started/api/mcp/tools/car-history)
- [CLASSIC.COM licensed API](https://support.classic.com/classic.com-api)

## 6. Rights are part of correctness

Every integration needs an explicit rights profile before production:

- may raw payloads be retained, and for how long?
- may source documents or photos be displayed?
- may normalized claims be stored and published?
- may derived comparisons or scores be published?
- what attribution or outbound link is required?
- must data be deleted when the contract ends?
- may the source be used for model training or extraction evaluation?

Put the contract/profile id and version into acquisition metadata. Do not copy
legal prose into every artifact. The code should enforce the small set of
operational permissions; the signed agreement remains the authority.

This is especially relevant for photographs and listing prose. A fact observed in
a licensed listing, the listing's copyrighted expression, and the right to
republish its photos are three different assets.

## 7. Vendor qualification

Brochures are candidate generators. A provider is not added to production routing
until it passes a ground-truth benchmark.

Build a permissioned Porsche corpus with stratified VINs/chassis numbers:

- pre-1981 chassis;
- 1981–1998 standardized VINs;
- 1999–2008;
- 2009–2018;
- MY2019+;
- US and rest-of-world delivery;
- common 911s and edge cases such as 959, Carrera GT, PTS, Exclusive
  Manufaktur/Sonderwunsch, and dealer-installed equipment.

For each car, obtain the strongest available reference artifact: original window
sticker/build sheet, PPS, CTC, or owner-held invoice. Measure:

- lookup eligibility and hit rate;
- exact color and option-code recall/precision;
- whether installed and merely available options are distinguishable;
- MSRP and currency accuracy;
- diagnostic quality when data is absent;
- pre-1981 and non-US behavior;
- latency and unit cost;
- retention, display, and derived-data rights;
- correction path and response time.

Report results per capability and era. A single "93% accurate" number would hide
the only misses collectors care about.

The first commercial outreach order:

1. **CLASSIC.COM** for collector auction/chassis history.
2. **VINData** for accessible NMVTIS and adjacent history products.
3. **Experian Auto AccuSelect** for the broadest Carfax-like event attributes.
4. **DataOne and MonroneyLabels** in the same build-data benchmark.
5. **MarketCheck** for mainstream dealer/listing chronology.

## 8. Build sequence

1. Introduce the provider behavior, request/acquisition structs, capability
   validation, and provider registry.
2. Move vPIC behind that contract while preserving its current public facade.
3. Persist acquisition diagnostics and rights metadata with snapshots.
4. Split vPIC interpretation from transport; retain current claim behavior until
   the facts work lands.
5. Add a manual-upload provider for PPS/CTC/window stickers before another HTTP
   vendor. This exercises the asynchronous path the product actually needs.
6. Build the Porsche qualification corpus and record benchmark results in
   `docs/research/`.
7. Add one history provider only after contract and redistribution rights are in
   hand.

## 9. Known mismatch in the current code

`Registry.persist_vpic_evidence/3` reuses an artifact when the response payload
has the same SHA-256. The evidence contract says a re-fetch is a new artifact,
because acquisition time and lookup coverage are part of the evidence. Claims
should remain content-deduplicated; acquisitions should not.

Do not bury this by changing the documentation. Fix it when provider acquisitions
are persisted, with separate tests for:

- two identical source responses acquired at different times;
- one proposed claim per identical assertion;
- diagnostics retained for both attempts.

