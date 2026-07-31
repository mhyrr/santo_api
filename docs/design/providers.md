# Provider System

*Research and architecture pass, updated 2026-07-31. Providers acquire evidence;
they do not decide vehicle facts.*

## 1. Decision

Build the provider system around **capabilities**, not vendors.

Within that architecture, prefer public evidence before commercial aggregation.
Vin Santo should compile the largest defensible record available from government,
regulatory, manufacturer, inspection, and public market sources. Commercial feeds
fill measured gaps; they are not the default just because they are convenient.

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

"Publicly available" is not an access or rights category. A bulk federal dataset,
a CAPTCHA-protected state lookup, a record ordered by mail, and a publicly visible
auction page have different automation, retention, and republication rules. The
provider descriptor and acquisition rights profile must preserve those differences.

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
| `inspection_history` | What jurisdictional inspections, results, defects, and odometer readings were recorded? | observed/event |
| `registration_status` | What current registration or title status does a jurisdiction expose? | observed |
| `recall_campaigns` | Which campaigns may apply to the model population? | reference |
| `open_recall_status` | Which unrepaired recalls did the manufacturer report for this VIN? | observed |
| `technical_reference` | Which manufacturer manuals, specifications, parts, and model documents apply? | reference |
| `technical_bulletins` | Which manufacturer communications, warranty extensions, and service bulletins apply? | reference |
| `defect_reports` | What failures have owners or other reporters alleged for the model population? | reference |
| `safety_investigations` | What defects have regulators investigated, and with what disposition? | reference |
| `emissions_certification` | Under which EPA/CARB test group and emissions configuration was the variant certified? | reference |
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
- fulfillment mode: `sync_api | bulk_dataset | operator_lookup | async_order |
  human_upload`;
- billing mode: `free | metered | quoted`;
- access class: `open_data | public_lookup | public_record_order | public_web |
  owner_authorized | licensed`;
- broad market and model-year coverage;
- provider documentation URL.

Descriptors are routing hints, not a claim that every vehicle is covered.

### Request

A target request contains:

- one capability;
- one normalized identity (`Santo.Identity.key/1` output) anchoring the subject;
- zero or more source selectors such as plate and jurisdiction, title number,
  registration number, model/year, or proof of owner authorization;
- capability-specific options.

The current implementation accepts one normalized identity and an options map.
Before state and international adapters land, promote selectors into a validated
provider-neutral value. Do not hide plates and title numbers inside vendor options:
they are reusable locators that one acquisition may discover for another.

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

`bulk_dataset` providers refresh a source corpus independently of a dossier lookup;
the dossier query reads the preserved local snapshot. `operator_lookup` covers
public services designed for a human, including CAPTCHA-protected state portals.
It does not authorize browser automation: the access terms still decide that.

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

## 5. Public-first source landscape

Public-first means exhausting defensible public evidence before buying an
aggregated answer. It does not mean scraping everything a browser can render.

### Access classes

- `open_data`: an API or bulk dataset with affirmative reuse terms;
- `public_lookup`: a service open to individual searches, without an assumed
  right to automate or republish;
- `public_record_order`: a government record obtained through a form, fee, or
  mail process;
- `public_web`: a viewable listing, forum, or archive whose facts, expression,
  and photographs have separate rights;
- `owner_authorized`: records available because an owner proves control or
  uploads the artifact;
- `licensed`: a commercial feed governed by contract.

### Public and owner-accessible sources

| Source | Capabilities | Access and coverage | Treatment |
|---|---|---|---|
| Santo | `vin_identity` | Local deterministic library; includes pre-standard chassis identities and disputes | The only automatic admitted identity claims |
| NHTSA vPIC | `generic_specifications` | Public API and downloadable decoder database built from manufacturer Part 565 submissions; mainly standardized 1981+ US-sale/import VINs | Reference snapshot with error diagnostics, never factory-build proof |
| NHTSA recalls | `recall_campaigns`; limited `open_recall_status` | Campaign API is year/make/model; consumer VIN lookup is single-use, supported-manufacturer, unrepaired-recall status rather than a bulk API | Keep population applicability separate from VIN-specific completion status |
| NHTSA manufacturer communications | `technical_bulletins` | Downloadable index and public bulletins, warranty extensions, and product-improvement communications submitted by manufacturers | Porsche technical reference; applicability is normally model/build-range evidence, not proof a repair occurred |
| NHTSA complaints | `defect_reports` | Daily bulk file and API; includes incident date, mileage, crash/fire/tow flags, and narrative, but only an 11-character VIN field | Population and VIN-pattern signal only; never attach a complaint to an individual chassis |
| NHTSA investigations | `safety_investigations` | Public flat files and redacted investigation documents | Regulatory findings and scope, not vehicle-specific history |
| Porsche Newsroom, manuals, and Classic catalogs | `generic_specifications`, `technical_reference` | Public technical specifications, press kits, searchable manuals, model history, and genuine-parts catalogs | Establish what existed and applied to a model/market; do not infer installed options |
| Porsche PPS | `factory_build` | All Porsche street-vehicle model years; $150; mailed in an estimated 6–8 weeks in the US; excludes serials, owners, warranty history, dealer-installed/Sonderwunsch work | High-authority factory artifact, owner-authorized manual fulfillment |
| Porsche CTC | `factory_build`, `inspection` | Eligible classics; starts at $500; dealer inspection verifies current engine/transmission numbers against original records and includes photographs | Factory claims plus dated current observations; do not collapse them together |
| Porsche Monroney | `factory_build` | Free through My Porsche for eligible MY2019+ owners | Owner-authorized factory artifact |
| EPA certification corpus | `emissions_certification`, `generic_specifications` | Open current and archived light-duty certification/test data, applications, covered carlines, powertrains, and test groups | Regulatory configuration by model/test group, not individual build evidence |
| CARB executive orders and enforcement | `emissions_certification`, `recall_campaigns` | Public certification orders, recall/settlement documents, and affected model populations | California regulatory evidence and emissions-campaign reference |
| California BAR | `inspection_history` | Public VIN/plate Smog Check and safety-systems inspection history; browser lookup rather than a documented production API | Dated jurisdictional observations; retain only within confirmed use terms |
| Texas MyTxCar | `inspection_history`, `odometer_history` | Free VIN-based vehicle inspection report; state guidance says it exposes safety/emissions history and mileage | High-value operator lookup for odometer chronology |
| Virginia DEQ and DMV | `inspection_history`, `title_history` | Public VIN emissions history; $8 mail-order vehicle history shows titling transactions without prior-owner names and retains only ten years | Two adapters: operator lookup plus asynchronous public-record order |
| Florida FLHSMV | `registration_status`, `title_history`, `odometer_history` | Free CAPTCHA-protected VIN lookup; current record includes title issue, registration, lien, title-brand, and last-title odometer information | Operator lookup; current Florida evidence, not nationwide title history |
| Illinois Secretary of State | `registration_status` | Public VIN title-and-registration status inquiry | Narrow current-status evidence; absence does not mean no history |
| NICB VINCheck | `theft_status`, `total_loss_history` | Free public lookup limited to five searches per IP per day and participating insurers' unrecovered theft/salvage reports | Manual corroboration only, not a production API or complete negative check |
| UK DVSA MOT History API | `inspection_history`, `odometer_history`, `registration_status` | Authorized API and bulk download; VIN endpoint returns dated tests, mileage, failures, defects, and advisories | First international government integration; unusually strong imported-car history |
| Dutch RDW Open Data | `registration_status`, `recall_campaigns`, `generic_specifications` | CC0 registration, type-approval, environmental, and recall data keyed primarily by Dutch plate | Open reusable corpus; requires a plate/jurisdiction selector |
| Australian PPSR/NEVDIS | `registration_status`, `theft_status`, `total_loss_history` | Government $2 VIN/chassis search can return security interests, stolen/write-off status, make, model, and color | Metered official record with a search certificate; useful for RoW provenance |
| Auction, dealer, classified, and forum pages | `listing_history`, `auction_history` | Publicly visible pages may expose VIN/chassis, mileage, modifications, documents, comments, and photographs; history and reuse terms vary | Discovery and dated seller/community claims; snapshot only when permitted |
| Owner/shop documents | `service_history`, `inspection`, `factory_build`, and more | Upload, forwarding address, shop integrations, dossier intake | The compounding proprietary corpus and correction channel |

### Public-source boundaries

The public corpus leaves structural holes:

- US state title and owner data is not generally open. The Driver's Privacy
  Protection Act limits motor-vehicle personal records, and the normalized
  nationwide title path is NMVTIS through approved providers.
- There is no open federal per-vehicle crash feed. The public NHTSA complaint
  data truncates VINs to 11 characters, and NHTSA withholds full FARS VINs from
  public releases because they can identify individuals.
- Public Porsche specifications, manuals, and catalogs prove what was offered or
  applicable, not what a specific chassis was built with.
- Public inspection and status lookups are jurisdiction-specific. A `none`
  coverage result means that source returned no record under the supplied
  selectors; it never means the vehicle has a clean history.
- A fact visible on a listing page, the page's prose, and its photographs are
  different assets. Public visibility grants no blanket republication right.

### Commercial gap fillers

| Source | Gap filled | Treatment |
|---|---|---|
| NMVTIS via VINData or another approved provider | Nationwide title, brand, odometer, total-loss, junk, and salvage reporting | The paid exception that stays early because direct public sources cannot reproduce it |
| Experian Auto AccuSelect / AutoCheck | Private accident, auction, service, ownership, theft, usage, and recall-event networks | Broadest Carfax-like candidate; measure its incremental evidence over the public dossier |
| CLASSIC.COM | Normalized collector auction/listing history for VINs and pre-standard chassis | License after public-market recall and rights gaps are measured |
| MarketCheck | Mainstream US/Canada dealer listings since 2015 | Dated seller claims and chronology; benchmark photograph and detail rights |
| DataOne | VIN-installed options, colors, packages, option pricing, and as-built MSRP | Benchmark Porsche coverage against PPS, window stickers, and owner records |
| MonroneyLabels | VIN-specific build-data availability and labels | Green may supply installed options; yellow is a coverage diagnostic, not build evidence |

Sources:

- [vPIC API purpose and rate control](https://vpic.nhtsa.dot.gov/api/)
- [vPIC standalone database](https://vpic.nhtsa.dot.gov/downloads/)
- [NHTSA recalls, complaints, investigations, and manufacturer communications](https://www.nhtsa.gov/nhtsa-datasets-and-apis)
- [NHTSA complaint data dictionary](https://static.nhtsa.gov/odi/ffdd/cmpl/CMPL.txt)
- [NHTSA FARS release and privacy policy](https://crashstats.nhtsa.dot.gov/Api/Public/Publication/809703)
- [NHTSA VIN recall lookup](https://www.nhtsa.gov/recalls)
- [Porsche technical specifications](https://newsroom.porsche.com/en_US/media-resources/technical-specifications.html)
- [Porsche press kits](https://newsroom.porsche.com/en_US/media-resources/press-kits.html)
- [Porsche Classic genuine-parts catalog](https://www.porsche.com/australia/accessoriesandservice/classic/originalpartscatalogue/)
- [Porsche owner manuals](https://ask.porsche.com/us/en-US/owner-manual/)
- [Porsche PPS and CTC](https://vehicledocumentation.porsche.com/usa)
- [Porsche documentation FAQ](https://vehicledocumentation.porsche.com/usa/faqs)
- [EPA vehicle certification data](https://www.epa.gov/compliance-and-fuel-economy-data/annual-certification-data-vehicles-engines-and-equipment)
- [CARB Porsche enforcement example](https://ww2.arb.ca.gov/porsche-ag-porsche-cars-na-inc-settlement)
- [California BAR inspection history](https://www.bar.ca.gov/inspection)
- [Texas inspection-history and mileage guidance](https://www.txdmv.gov/sites/default/files/body-files/Odometer_Fraud_Press_Release_07_19_17.pdf)
- [Virginia emissions history](https://www.deq.virginia.gov/air-energy/vehicle-emissions-air-check/how-do-i-get-an-inspection)
- [Virginia mail-order vehicle history](https://www.dmv.virginia.gov/records/vehicle-history)
- [Florida vehicle information check](https://services.flhsmv.gov/mvcheckweb/Go)
- [Illinois title and registration inquiry](https://apps.ilsos.gov/regstatus/index.jsp)
- [Driver's Privacy Protection Act](https://www.justice.gov/osg/brief/reno-v-condon-merits)
- [NMVTIS commercial and consumer access](https://vehiclehistory.bja.ojp.gov/nmvtis-annual-reports-and-financial-audits/specific-services-provided-by-nmvtis-operator)
- [Approved NMVTIS providers](https://vehiclehistory.bja.ojp.gov/nmvtis_vehiclehistory)
- [NICB VINCheck limits and coverage](https://www.nicb.org/vincheck)
- [UK MOT History API](https://documentation.history.mot.api.gov.uk/mot-history-api/api-specification/)
- [Dutch RDW Open Data](https://opendata.rdw.nl/en/)
- [Australian PPSR vehicle search](https://www.ppsr.gov.au/searching/do-used-car-or-vehicle-search)
- [DataOne VIN Decoder API](https://www.dataonesoftware.com/web-services-vin-decoder-api)
- [MonroneyLabels availability API](https://monroneylabels.com/docs/light_color)
- [VINData commercial APIs](https://www.vindata.com/apis)
- [Experian Auto AccuSelect](https://www.experian.com/automotive/auto-accuselect)
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

## 7. Source qualification

Public availability does not waive qualification. A source is not added to
production routing until its coverage, diagnostics, selectors, stability, and use
rights are understood. Commercial brochures are candidate generators, not
evidence.

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

After the public-source gap report, the commercial outreach order is:

1. **VINData or another approved NMVTIS provider** for the nationwide title gap.
2. **Experian Auto AccuSelect** for private accident, service, auction, and usage
   evidence still absent from the public dossier.
3. **CLASSIC.COM** for normalized collector auction/chassis history that public
   market archaeology cannot recover or retain.
4. **DataOne and MonroneyLabels** in the same build-data benchmark.
5. **MarketCheck** for mainstream dealer/listing chronology.

## 8. Build sequence

The provider behavior, request/acquisition structs, capability registry, vPIC
adapter, Registry-side interpretation, and acquisition metadata persistence are
already in place.

Next:

1. Expand the contract with the public-source capabilities, access classes,
   `bulk_dataset`/`operator_lookup` fulfillment, and validated multi-selector
   requests.
2. Build one NHTSA bulk-corpus provider covering recalls, manufacturer
   communications, complaints, and investigations. Preserve each dataset release;
   query the local snapshot by Porsche model/year/VIN pattern.
3. Create a jurisdiction catalog recording each public source's capabilities,
   required selectors, access method, coverage semantics, rights, and refresh
   behavior.
4. Implement the first operator-assisted US adapters: California BAR, Texas
   MyTxCar, Virginia emissions and vehicle-history order, Florida FLHSMV, and
   Illinois title status. Do not automate a human lookup until its terms permit it.
5. Ingest the official Porsche public corpus: specifications, press kits, manuals,
   Classic parts catalogs, and model history. Keep model applicability separate
   from as-built configuration.
6. Add the UK MOT API as the first international provider; it has a supported VIN
   endpoint and returns the dated mileage and defect history US sources usually
   lack. Keep the target model global even if US coverage ships first.
7. Add manual artifact acquisition for PPS/CTC, window stickers, title documents,
   inspection reports, and owner/shop records.
8. Build the Porsche qualification corpus and a per-capability gap report in
   `docs/research/`. Add commercial providers only against named gaps.

## 9. Known mismatch in the current code

`Registry.persist_acquisition/2` reuses an artifact when the response payload has
the same SHA-256. The evidence contract says a re-fetch is a new artifact, because
acquisition time and lookup coverage are part of the evidence. Claims should
remain content-deduplicated; acquisitions should not.

Do not bury this by changing the documentation. Fix it when provider acquisitions
are persisted, with separate tests for:

- two identical source responses acquired at different times;
- one proposed claim per identical assertion;
- diagnostics retained for both attempts.
