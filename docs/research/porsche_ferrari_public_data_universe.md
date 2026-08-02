# Porsche and Ferrari: the public provenance universe

*Research memo, 31 July 2026. This was a source survey, not a collection run. No
site was bulk-fetched, no access control was bypassed, and publicly visible pages
are treated as pointers unless their terms affirm reuse.*

*Implementation update, 1 August 2026: the first free qualification cohort is
specified in [`../design/free_acquisition_corpus.md`](../design/free_acquisition_corpus.md).
It checks in 30 transaction-selected identities and bare sale facts, retains
marketplace pages as pointer-only artifacts, and enriches applicable VINs through
NHTSA vPIC. External records remain outside application seeds.*

## Executive answer

The thesis holds for auction-grade *history*, with one hard exception: public and
owner-contributed evidence cannot recreate a manufacturer's private build ledger
or make a physical matching-numbers determination against it. That exception is
material for early, high-value Ferraris and a narrower band of early Porsches. It
does not prevent a registry from assembling the ownership, service, sale, race,
configuration, and documentary history that buyers actually inspect.

The opportunity is therefore a permissioned evidence network, not a public-web
index. Government records provide jurisdictional observations; auction and race
archives provide dated public events; marque registries provide chassis-level
continuity; owners and shops provide the documents that close the record. The
registry earns the right to combine those layers by returning attribution,
corrections, and a durable dossier to contributors.

Three acquisitions should come first:

1. **A licensed US vehicles-in-operation extract from Experian or S&P Global,
   by make/model/model year.** Both vendors advertise current registration/VIO
   data; this is the missing denominator and should replace the population ranges
   in this memo with counts ([Experian VIO](https://www.experian.com/automotive/vehicles-in-operation-vio-data),
   [S&P Global VIO](https://prod.azure.ihsmarkit.com/mobility/en/products/automotive-market-data-analysis.html)).
2. **A collector-auction history licence, starting with CLASSIC.COM or direct
   auction-house feeds.** Sale events and prior listing pointers are the broadest
   cross-marque history layer, but major auction sites prohibit commercial reuse
   or automated collection without permission ([CLASSIC.COM API](https://support.classic.com/classic.com-api),
   [Sotheby's terms](https://www.sothebys.com/en/terms-conditions),
   [Bonhams catalogue terms](https://catalogues.bonhams.com/policies/terms-of-service)).
3. **Reciprocal owner/club pilots: 356 Registry plus one PCA region; Ferrari Club
   of America plus one serial historian.** The clubs already have the people and
   chassis records: PCA reports more than 145,000 members, FCA more than 11,500,
   and the 356 Registry nearly 6,500 ([PCA](https://newsroom.porsche.com/en_US/2025/company/porsche-club-of-america-70-years-parade-40557.html),
   [FCA](https://ferrariclubofamerica.org/default.aspx),
   [356 Registry](https://www.porsche356registry.org/content.aspx?club_id=579966&module_id=478258&page_id=22)).
   The offer should be private-by-default owner vaults, source attribution,
   contributor-controlled publication, and export—not a request to copy their
   database.

NMVTIS remains the baseline US title-event acquisition already identified in the
provider strategy. It is necessary, but it does not answer the new questions in
this survey.

## Definitions and confidence

- **Built** means worldwide completed road and GT vehicles, grouped by completion
  year. Factory-numbered competition chassis are included only where the surviving
  production reconstruction cannot separate them; the Ferrari pre-1974 estimate
  identifies its roughly 500 pure racers.
- **Survives** means the vehicle probably still exists, whether registered,
  stored, under restoration, or static. **Roadworthy** is narrower.
- **US-registered** means active US vehicles in operation, not cumulative US
  deliveries. No free national make/model/year VIO table was found. Those figures
  below are therefore estimates pending a licensed Experian/S&P extract.
- **Plausibly cover** means a living vehicle for which a VIN/chassis identity and
  at least one independent evidence event can reasonably be acquired without a
  factory certificate. It does not mean a complete ownership chain.

The population arithmetic deliberately uses ranges. Ferrari says it has produced
approximately 330,000 vehicles and that more than 90% remain on the road; Porsche
says more than 70% of the first million 911s were still ready to drive in 2017
([Ferrari 2030 plan](https://www.ferrari.com/content/dam/ferrari-fcom/news/corporate/2025/10/pdf/PR_CMD_2025_ENG.pdf),
[Porsche millionth 911](https://newsroom.porsche.com/en/products/porsche-one-millionth-911-milestone-13733.html)).
Those are useful marque-level anchors, not survival studies by cohort.

## Population

*Population table to be read with the methodology notes below. All non-factory
survival and US-registration figures are estimates.*

### Porsche

| Era | Built worldwide | Estimated survivors worldwide | Estimated US-registered | Headline families |
|---|---:|---:|---:|---|
| **Pre-1974** | **~283,000** | **140,000–180,000** | **85,000–110,000** | 356 77,361; original 911 81,100; 912 ~30,500; 914 through 1973 ~94,000 |
| **1974–1998** | **~780,000** | **470,000–550,000** | **270,000–330,000** | 911 G/964/993 ~329,000; 924/944/968/928 ~388,000; late 914 and early Boxster ~65,000 |
| **1999–2024** | **~4.3–4.4m** | **3.8–4.1m** | **900,000–1.02m** | 911 ~0.75–0.80m; Cayenne ~1.4m; Macan ~0.93m; Boxster/Cayman ~0.55m; Panamera ~0.45–0.50m; Taycan ~0.19m |

**Estimated Porsche production through 2024: about 5.4 million vehicles.**

The build figures reconcile model totals to cumulative factory milestones.
Porsche reports 77,361 356s, 81,100 first-generation 911s, one million total
Porsches by July 1996, one million Cayennes by 2020, one million Macans by 2025,
and 100,000 Taycans by 2022
([Porsche historical background](https://newsroom.porsche.com/en_US/company/porsche-cars-north-america-historical-background-18072.html),
[911 production history](https://newsroom.porsche.com/dam/jcr%3A5b57016c-4bd7-48f0-8815-8e00e93a6327/PAG_1Mio911_PM_EN_06.pdf),
[Cayenne](https://newsroom.porsche.com/en_US/2022/products/porsche-cayenne-anniversary-20-years-success-story-28517.html),
[Macan](https://newsroom.porsche.com/en_SG/2025/company/porsche-leipzig-one-millionth-macan-40068.html),
[Taycan](https://newsroom.porsche.com/en/2022/products/porsche-taycan-production-anniversary-100000-models-kilometre-kings-30291.html)).
The 912 estimate is approximately 30,500; Porsche reports 115,631 four-cylinder
914s overall and the factory-derived community table supplies the annual split
used to cut 1973
([912 production memorandum](https://www.sec.gov/Archives/edgar/data/1688804/000168880419000023/rse1apos.htm),
[Porsche 914](https://www.porsche.com/stories/mobility/8-things-porsche-914/),
[914 annual table](https://www.914world.com/specs/productionnumbers.php)).
Published family totals include 150,684 924s, 163,302 944s, and 196,397 G-series,
63,762 964, and 68,881 993 911s
([Porsche heritage](https://investorrelations.porsche.com/en/about-porsche/heritage),
[transaxle release](https://newsroom.porsche.com/dam/jcr%3Ae3067edf-6435-4610-bc9b-144680f6d499/PM%2029e%20-%2026.04.2016%20-%20Porsche%20Museum%20pays%20tribute%20to%2040%20years%20of%20the%20transaxle.pdf),
[911 history](https://www.porsche.com/stories/innovation/a-brief-history-of-the-porsche-911/)).

Survival is an estimate using 50–65% for pre-1974, 60–70% for 1974–98, and
88–94% for modern cars. Porsche's broader claim that roughly 70% of its cars—and
more than 70% of 911s—remain roadworthy is a boundary check, not a cohort audit
([Porsche Classic](https://newsroom.porsche.com/en/christophorus/porsche-classic-tires-tests-10063.html),
[millionth 911](https://newsroom.porsche.com/en/products/porsche-one-millionth-911-milestone-13733.html)).
US estimates use cumulative deliveries, age-dependent attrition, and a small
collector-import allowance; the public source publishes annual deliveries, not
current fleet counts ([PCNA 2024 sales](https://newsroom.porsche.com/pdf/d93255e0-5772-4725-9230-8b10e1357579?print=)).

**Plausibly coverable Porsche population: about 1.25 million US cars.** That is
roughly 92% of the midpoint estimated active fleet; the discount removes dormant
registrations, unresolved early identities, and cars with no obtainable owner or
institutional evidence. The estimated worldwide surviving fleet is about 4.5
million, but the acquisition surface is not broad enough to call all of it
plausibly coverable.

### Ferrari

| Era | Reconstructed worldwide road-car output | Estimated survivors worldwide | Estimated US-registered | Headline families |
|---|---:|---:|---:|---|
| **Pre-1974** | **~12,700** | **9,500–11,500** | **5,000–6,000** | 166/195/212/250 and related road/GT cars ~8,500; Dino ~3,700; pure racers ~500 |
| **1974–1998** | **~72,100** | **61,000–68,000** | **17,000–19,000** | 308/328/Mondial/GT4 ~30k; BB/Testarossa/512 ~14k; 348/F355 ~20k; 456/550/F40/F50/other ~8k |
| **1999–2024** | **~195,600** | **186,000–193,000** | **48,000–52,000** | 360-through-296 mid-engine family ~85–95k; V12/four-seat GT ~40–50k; California/Portofino/Roma ~40–45k; halo, track, and Purosangue balance |

The reconstructed table sums to about 280,400 road and GT cars through 2024.
Ferrari's 2025 strategic plan gives a broader, rounded corporate figure of
approximately 330,000 vehicles since founding and says more than 90% survive.
Public production/model data do not reconcile that 50,000-vehicle difference;
the memo therefore uses the auditable annual road-car series for era arithmetic
and preserves the corporate number as a separate all-in upper bound rather than
forcing false precision
([Ferrari 2030 plan](https://www.ferrari.com/content/dam/ferrari-fcom/news/corporate/2025/10/pdf/PR_CMD_2025_ENG.pdf),
[Ferrari Club España annual series](https://www2.ferrariclubespana.com/produccion.html),
[Ferrari key metrics](https://www.ferrari.com/en-EN/corporate/key-metrics),
[2024 annual report](https://cdn.ferrari.com/download/Ferrari_Annual_Report_2024.pdf),
[model-production index](https://www.f-register.com/about-the-cars/production-numbers)).
The table's high-volume family allocations are rounded estimates because Ferrari
does not publish a comprehensive current model-total series.

The early estimate comes from serial-sequence reconstruction: roughly 8,500 road
and GT racers, 3,700 Dinos, and 500 pure racers. That analysis found about 43% of
the Enzo-era sample in the US; it also estimated roughly 25% of later Fiat-era
cars and 28% of post-1991 production went to the US
([Ferraris Online](https://ferraris-online.com/how-many-ferraris/)).
Ferrari's filings report that the US received 3,452 of 13,752 shipments in 2024,
almost exactly 25%, which anchors the modern range
([Ferrari geographic shipments](https://ferrari.scene7.com/is/content/ferrari/Ferrari_Annual_Report_2025_20F%20Form)).

Survival uses 75–90% for pre-1974, 85–95% for 1974–98, and 95–99% for modern
cars. Ferrari's “over 90%” statement is consistent with those ranges but does not
define its denominator, geography, or treatment of race cars and static
collections.

**Plausibly coverable Ferrari population: about 68,000 US cars.** The estimated
active fleet is 72,000–77,000; the discount covers dormant collections,
gray-market identity seams, and vehicles where the owner is the only evidence
gateway. The worldwide survivor estimate is about 260,000–270,000 on the
reconstructed road-car denominator, not the corporate all-in count.

## Ranked source inventory

### Tier 1 — acquire or partner now

| Rank | Source layer | Per-car yield | Coverage and rights conclusion |
|---:|---|---|---|
| 1 | **Owner/shop artifact contribution** | Window sticker/order sheet, service book and invoices, titles/registrations, import forms, inspection photographs, restoration files, prior certificates | Highest precision and cleanest chain of authority when the owner supplies the artifact and publication choices are explicit. VINwiki demonstrates that owners will contribute photos, mileage, dates, and service records to improve a car's future history ([VINwiki FAQ](https://vinwiki.com/faq/)). |
| 2 | **Owner/buyer official reports** | Registration/holder changes, odometer and inspection events, liens/brands, accident or controlled-repair events, and sometimes workshop service | Belgium, Spain, France, Italy, Ontario, Finland, Romania, and New Zealand provide unusually rich single-vehicle records. Their normal rights model is individual order or owner-shared report, not database reuse; build a contribution kit before an adapter. Sources are detailed below. |
| 3 | **Club and model registries** | Chassis continuity, former/current owner relationships, serial/component data, restoration history, photographs, corrections | Strongest pre-standard-VIN layer. The 356 Registry exposes about 19,000 historical VIN records plus 3,000 member cars; Ferrari's 330 GT registry reports 18,300 detail records for 1,137 cars ([356 CNH](https://porsche356registry.org/content.aspx?club_id=579966&module_id=478277&page_id=22), [330 GT Registry](https://www.330gt.com/)). Partnership-only. |
| 4 | **Licensed auction and specialist-sale history** | Chassis/VIN, sale date/result, mileage, asserted specification, provenance narrative, and document inventory | Broadest cross-marque event layer and a repeat-sale spine. Major-house terms bar unlicensed commercial collection; acquire factual feeds and source links, not copied prose/photos ([RM terms](https://rmsothebys.com/privacy-terms), [Gooding terms](https://bid.goodingco.com/terms-of-use), [Bonhams terms](https://catalogues.bonhams.com/policies/terms-of-service)). |
| 5 | **Professional historians and serial literature** | Factory build-sheet copies, delivery, owners, races/shows, classifieds, component swaps, restoration, and prices | Essential for early Ferrari. Ferrari Market Letter has been serial-based since its card-file origins; Massini reports are copyrighted per-car research products. Buy queries or a claim feed—do not reproduce the underlying archive ([FML history](https://www.ferrarimarketletter.com/about), [sample Massini report](https://listings.worldwideauctioneers.com/docs/sale/public/116/89/1965%20Ferrari%20330%20GT%20Massini%20Report%206549%20History.pdf)). |
| 6 | **Race-history partnerships** | Entry, date, entrant, driver, result, configuration/livery, and images by chassis | Very high coverage for internationally raced cars and almost none for road cars. RacingSportsCars says it covers the major sports-car series and expressly prohibits commercial republication/storage without permission ([coverage](https://www.racingsportscars.com/about.html), [terms](https://www.racingsportscars.com/login.html?ReturnUrl=index.html)). |

### Tier 2 — high-value operator or owner-authorized records

Several national systems are substantially better than the fragmented US state
surface, but almost all are designed for a buyer, seller, or authenticated local
user rather than a commercial ingestion service.

| Rank | Source | Address and facts | Access and rights posture |
|---:|---|---|---|
| 1 | **Belgium Car-Pass** | Certificate carries the VIN; dated odometers, first Belgian registration, emissions, recall and accident-inspection flags, and—since 2024—standardized maintenance/repair work. Automotive businesses must report work and manufacturers report connected-car odometers quarterly. | Seller-provided on nearly every used-car sale. Individually requested; bulk/commercial reuse is excluded. Owner-contributed certificate or negotiated feed only ([FAQ](https://www.car-pass.be/en/faq), [mechanics](https://www.car-pass.be/en/about-car-pass/how-does-car-pass-work)). |
| 2 | **Spain DGT complete report** | VIN, plate, or NIVE; holder count and periods, ITV tests/defects/mileage, insurance, liens/embargoes/theft, technical data, and participating-workshop maintenance. | Available to any requester for €8.67, but detailed access requires Spanish identity/Cl@ve or phone/in-person request and a stated reason. Public-information status does not establish republication rights ([report](https://sede.dgt.gob.es/en/vehiculos/informacion-de-vehiculos/informe-de-un-vehiculo/), [field guide](https://sede.dgt.gob.es/es/vehiculos/informacion-de-vehiculos/informe-de-un-vehiculo/ayuda-para-interpretar-el-informe-del-vehiculo/)). |
| 3 | **France HistoVec** | Owner authenticates from registration particulars; report gives holder count/transfers, first French or foreign registration, import status, controlled-repair events, liens/opposition/theft, inspections, and mileage. | Free and explicitly owner-mediated: owner generates, buyer receives a share link. This is almost the desired contribution flow ([Service-Public](https://www.service-public.fr/particuliers/vosdroits/R52957?lang=en), [owner portal](https://histovec.interieur.gouv.fr/histovec/proprietaire)). |
| 4 | **Italy ACI/PRA chronological extract** | Plate input, output includes chassis/VIN; every registered owner/date, recorded sale prices, liens/encumbrances, and prior plates. | PRA is public and any interested person may order, but access is paid/authenticated and bulk supply is separate. Ingest a contributed report with personal-data controls or negotiate access ([ACI service](https://web.aci.it/servizi/visura-e-estratto-cronologico/), [certificate](https://www.aci.it/i-servizi/servizi-online/estratto-cronologico-pra.html)). |
| 5 | **Ontario UVIP** | VIN or plate; description, all present/previous Ontario owners with city and odometer, liens, wholesale value, and last wrecked/unfit status. | Buyer may order for C$20; seller normally must provide it. Retain as a controlled artifact and publish non-personal chronology unless consent covers names ([Ontario](https://www.ontario.ca/page/used-vehicle-information-package)). |
| 6 | **New Zealand Motor Vehicle Register (MR32)** | VIN/chassis; make/model, engine number, NZ registration, historic odometers, and dates registered person changed. Corporate registrants may be named; individuals are withheld. | Free record request, not an API. Owner/operator artifact. The register says registered person is not legal owner ([MR32](https://nzta.govt.nz/vehicles/how-the-motor-vehicle-register-affects-you/requesting-register-information/request-motor-vehicle-details), [register](https://www.nzta.govt.nz/vehicles/how-the-motor-vehicle-register-affects-you)). |
| 7 | **Argentina DNRPA historical report** | Registration/domain key; engine and chassis, first registration and use, theft, pledges/embargoes, and every registered holder since initial registration. | Any interested adult, including a foreigner with passport, may order/pay. Personal-data-bearing legal artifact; extract a redacted chain ([domain report](https://www.argentina.gob.ar/servicio/solicitar-un-informe-de-dominio-del-automotor), [history](https://www.argentina.gob.ar/node/35378)). |
| 8 | **Finland Traficom** | VIN or plate; free technical, inspection, and tax data; paid owner/history data, roughly from 1989. | Authenticated private-customer service with query limits and disclosure restrictions. Owner/buyer artifact or licensed access ([Traficom](https://www.traficom.fi/en/drivers-and-vehicles/buying-and-selling-vehicle/check-vehicle-information)). |
| 9 | **Romania RAR Auto-Pass** | VIN; dated inspection odometers, authorized-workshop interventions, specified serious-accident repairs, inspections, and recalls. | Buyer/seller may order online for 42 lei; result persists 60 days and a negative certificate is free. Individual contribution, not an open feed ([RAR](https://www.rarom.ro/?p=298531)). |
| 10 | **Australia PPSR/NEVDIS** | VIN or older chassis; security interests, make/model/colour, registration where available, police theft, and written-off status. No owners or odometers. | A$2 official search certificate, subject to PPSR and third-party NEVDIS conditions ([search](https://www.ppsr.gov.au/carcheck), [terms](https://www.ppsr.gov.au/about-us/technical-information/conditions-and-terms-use)). |
| 11 | **Norway vehicle information** | VIN/plate; registration dates, technical data and roadworthiness; authenticated view adds owner and odometers. | The agency expressly says mechanically retrieved/API/scraped and logged-in information cannot be freely disseminated. Owner report or licence only ([NPRA](https://www.vegvesen.no/en/vehicles/buy-and-sell/vehicle-information/check-vehicle-information/about-the-vehicle-information-facility-and-odometer-readings/)). |
| 12 | **UAE/Abu Dhabi Police accident inquiry** | Chassis/VIN; police-recorded accident report, emirate, date, and accident type. | CAPTCHA-protected single lookup. Never automate; accept owner result/link. Accident-only and not complete for private/unreported repairs ([Abu Dhabi Police](https://es.adpolice.gov.ae/trafficservices/publicservices/AccidentsInquiry.aspx?Culture=en)). |

### Tier 3 — narrow institutional corroboration

| Source | What it can prove | Limit |
|---|---|---|
| **FIA Historic Technical Passport list** | Public list of valid passports by FIA number, make/model, period, and class; useful evidence that a particular competition specification was accepted. | The FIA form says it does not certify the correctness of the chassis number. An HTP is eligibility evidence, not provenance or authenticity ([HTP list](https://htp.fia.com/), [FIA form](https://www.fia.com/file/12339/download)). |
| **FIVA Identity Card** | A chassis-level identity, specification, history summary, physical inspection, and permanent FIVA Registration Number. | Owner-applied, expires after at most ten years or on ownership change, and the underlying system is not a public corpus. Acquire the card from its owner or partner with the national authority ([FIVA Technical Code](https://www.fiva.org/storage/Documents/Technical%20Commission/FIVA.Ref_.TC03.2020.Tech_.Code_.Fin_.Copy_.V2.pdf?v20240611083638=)). |
| **US National Historic Vehicle Register** | Archival photographs and measured historical documentation for nationally significant vehicles, preserved with the Library of Congress. | A curated heritage register, not a fleet source; useful when a named chassis is included ([Congress.gov](https://www.congress.gov/bill/115th-congress/senate-bill/966/text)). |

### Customs, import/export, and court/lien records

- A US import produces CBP Form 7501 plus DOT HS-7 and EPA 3520-1; CBP directs
  the importer to retain them for state registration. They can prove importer,
  entry, declared vehicle identity, and compliance path, but are owner/importer
  artifacts rather than a public VIN lookup
  ([CBP vehicle import process](https://www.help.cbp.gov/s/article/Article1176?language=en_US)).
- US used-vehicle exports are filed through AES with VIN and title information,
  but Census treats AES export records as confidential. There is no public
  per-VIN export history
  ([AES guide](https://www.census.gov/foreign-trade/aes/aesdirect/AESDirect-User-Guide.pdf)).
- Canada's RIV/CBSA import process records VIN, title/import status, and permanent
  salvage/non-repairable branding, but customs records are available only to the
  importer, exporter, or authorized agent. Ask the owner for Form 1/e-Form 1
  ([CBSA vehicle rules](https://www.cbsa-asfc.gc.ca/publications/dm-md/d19/d19-12-1-eng.html),
  [access rule](https://www.cbsa-asfc.gc.ca/publications/dm-md/d1/d1-3-1-eng.html)).
- Vehicle liens are useful where a vehicle register exposes them—Ontario UVIP,
  Italy PRA, Spain DGT, Australia/NZ PPSR—not through general court search.
  PACER's national index searches parties and cases rather than VINs, so federal
  court records are occasional discovery evidence, not a provider
  ([PACER](https://www.uscourts.gov/court-records/find-a-case-pacer)).

### Enthusiast and market sources

Coverage estimates here mean “share of the source's natural target population
with at least a chassis trace,” not a complete dossier.

| Rank | Source | Estimated coverage and chassis key | Licensing and contribution posture |
|---:|---|---|---|
| 1 | **Porsche 356 Registry Chassis Number History** | About 19,000 volunteer-collected VIN records plus 3,000 member-car records. Against ~77,000 built, that is 29% gross before overlap; **estimated surviving-car trace coverage 25–40%**. Search is by chassis and records can include restoration, prior-owner text, and engine issues ([CNH](https://porsche356registry.org/content.aspx?club_id=579966&module_id=478277&page_id=22)). | Members-only, no public reuse licence. The club explicitly calls for truthful restoration and ownership-change documentation. **Very likely to contribute under club governance; very likely to oppose copying** ([guidance](https://porsche356registry.org/content.aspx?club_id=579966&module_id=506611&page_id=22)). |
| 2 | **Ferrari single-model registries** | 330 GT reports 18,300 detail records over 1,137 cars and photos for ~865; 308 GTB lists ~2,000 chassis, about 69% of Ferrari's 2,897-car production. Dino GT4 records chassis, engine, transmission, specification, history, and location ([330 GT](https://www.330gt.com/), [308 register](https://308gtb.de/serial-numbers/), [Ferrari 308 production](https://www.ferrari.com/en-EN/magazine/articles/50-years-of-the-Ferrari-308-GTB), [Dino GT4](https://www.dino-gt4-registry.com/)). | Contributor-built private projects. The 308 site bars commercial copying; Dino protects owner names and solicits owner submissions. **Excellent reciprocal partners; hostile to harvest by design.** |
| 3 | **PCA model registers** | PCA has 145,000+ members; model registers explicitly collect VINs. The 993 register accepts former VINs and can connect later owners with consent; RS America seeks all 701 cars and records VIN/build date/colour/options ([PCA](https://newsroom.porsche.com/en_US/2025/company/porsche-club-of-america-70-years-parade-40557.html), [993](https://993registry.pca.org/register), [RS America](https://rsamerica.pca.org/pca-rs-america-registry/)). **Potential addressable relationships: low hundreds of thousands, with duplication; public usable coverage: zero.** | Private, consent-gated member data. **High contribution likelihood through PCA governance and owner privacy; no implied product licence.** |
| 4 | **Ferrari Market Letter, Massini, and by-serial books** | **Estimated trace coverage 70–95% for auction-grade pre-1974 Ferraris**, but no public corpus count. FML has been serial-based since its card-file origins; Massini reports include owners, races/shows, component and colour changes, prices, photos, and build sheets. Pourret/Raab/modern 275 books add chassis-by-chassis skeletons ([FML](https://www.ferrarimarketletter.com/about), [Massini interview](https://edgarmotorsport.wordpress.com/wp-content/uploads/2012/07/marcel-massini-forza-edgar.pdf), [Pourret](https://www.gilena.it/en/book/ferrari-250-gt-competition), [Raab history](https://f-register.com/About-Us/The-Book/Hilary-Raab)). | Professional IP or copyrighted literature. **Medium contribution likelihood as paid query/referral or licensed claims; extreme resentment if the private database/books are transcribed.** |
| 5 | **Early 911S Registry, FerrariChat, Rennlist, Pelican** | Early 911S reports 36,489 members, 894,940 posts and 5,530 early-car sale threads; **estimated 10–25% of surviving 1965–73 911s** has a VIN-bearing trace. FerrariChat has 16.3m posts; **estimated trace coverage 50–80% for blue-chip 250/275 cars, 10–30% for older series cars, under 10% ordinary modern cars**. Rennlist/Pelican estimate 5–15% enthusiast air-cooled Porsche trace, VINs sporadic ([Early 911S](https://www.early911sregistry.org/forums/forum.php), [FerrariChat](https://www.ferrarichat.com/forum/), [Pelican](https://forums.pelicanparts.com/)). | Public posts are proposed claims, not licensed content. FerrariChat users retain copyright; its rules protect personal data. Rennlist returned HTTP 403 on direct open and was not retried. **Good owner-link/opt-in funnel; poor backfill source.** ([FerrariChat terms](https://www.ferrarichat.com/forum/help/terms)). |
| 6 | **Major auction archives** | Usually directly keyed to VIN/chassis, often component numbers; **estimated 80–100% of each house's own retained lots, 20–40% of surviving pre-1974 Ferraris and 5–15% of collectible Porsches across houses**, with duplicate cars. Sale result, mileage, documents, provenance claims, and photographs ([representative RM lot](https://rmsothebys.com/auctions/lf22/lots/r0043-1985-ferrari-288-gto/)). | RM, Gooding, and Bonhams bar automated extraction/database reuse; Mecum gates complete results. **Licence target, not community corpus** ([RM](https://rmsothebys.com/privacy-terms), [Gooding](https://bid.goodingco.com/terms-of-use), [Bonhams](https://catalogues.bonhams.com/policies/terms-of-service), [Mecum](https://www.mecum.com/tags/results/)). |
| 7 | **RacingSportsCars and specialist race-chassis sites** | Chassis-keyed entries/results/drivers/liveries/photos; **estimated 70–95% of internationally raced works/privateer sports-racing chassis in covered series**, near zero road-car coverage. Type 550 separately claims histories for every known 550/550A ([917 example](https://www.racingsportscars.com/chassis/archive/917-008.html), [Type 550](https://type550.com/history/chassis-number/)). | RSC expressly bars commercial use, republication, or retrieval-system storage while soliciting contributions. **Culturally aligned partnership candidate; extraction is prohibited** ([RSC terms](https://www.racingsportscars.com/login.html?ReturnUrl=index.html)). |
| 8 | **Barchetta.cc** | Model/serial index and chassis pages; **estimated 70–90% serial skeleton for pre-1990 Ferrari**, with uneven event depth. A Ferrari judging guide uses it for colour, engine swap, restoration and race leads but warns every fact needs corroboration ([index](https://www.barchetta.cc/all.ferraris/by-serial-number/ferrari-by-serial-number/model-index-by-date/index.html), [guide](https://iacpfa.org/wp-content/uploads/2020/01/judging_older_ferraris__leyd.pdf)). | No current reusable licence found and the site's operational state is unreliable. **Pointer or negotiated archive acquisition only.** |
| 9 | **YouTube, Instagram, and creator media** | Rich testimony/restoration footage but generally creator/model/plate-keyed; **estimated VIN-keyed rate below 1% and target-fleet trace below 5%, except famous cars**. | Both platforms restrict automated collection/reuse. Use a link and proposed claim, or ask the creator to attach the original artifact. **Medium-high voluntary contribution with credit/traffic; hostile rights posture for scraping** ([YouTube](https://uk.youtube.com/t/terms), [Instagram](https://www.facebook.com/help/instagram/581066165581870)). |

The contribution signal is concrete: small Ferrari registries and the 356
Registry already ask owners to correct and extend a shared chassis record. The
privacy signal is equally concrete: PCA uses consent to connect owners, Dino
normally withholds names, and professional historians sell per-car expertise.
A collective-ownership model can work, but only if source attribution, owner
publication controls, correction authority, reciprocal access, and export are
product features rather than promises in a partnership deck.

## What the certification programs add

### Ferrari Classiche

Ferrari says certification begins by establishing that the chassis is original
and examines the engine, gearbox/transmission, suspension, brakes, wheels,
bodywork, and interior against the vehicle's original specification
([Ferrari certification](https://www.ferrari.com/en-EN/auto/classiche-certification),
[Ferrari process](https://www.ferrari.com/en-EN/magazine/articles/officina-ferrari-classiche-certificate-of-authenticiy-vintage-cars)).
That product contains two different things:

1. **Private archive comparison.** Original build specification and the factory's
   component records. Owner documents, serial literature, period photographs,
   and marque historians can often reconstruct the answer, but they cannot prove
   that their reconstruction equals Ferrari's unreleased ledger.
2. **A current physical examination.** Inspectors determine what chassis and
   components are actually present. No database can substitute for looking at
   stampings, construction, repairs, and component identity on the car.

The first is an access monopoly; the second is irreducible inspection work. A
registry can reproduce most of the evidence trail and can commission an equally
careful independent inspection. It cannot honestly label either result “Ferrari
Classiche” or remove the auction market's preference for the factory's opinion.

There is some comparable-sale evidence, but it is small and confounded. A 2020
Classic Car Trust survey compared five Daytonas (three certified), two similar
512 TRs, and seven 250 GTEs. It reported certified premiums of 19%, 28%, and 22%
respectively. The author also acknowledged that no two cars are identical and
that colour, venue, condition, restoration, and documentation could explain part
of the difference ([survey and underlying observations](https://tcct.com/news/2020/07/certification-pays/)).
The defensible conclusion is **Classiche moves saleability and sometimes price in
six- and seven-figure vintage Ferraris, but “20%” is not a causal market rule**.
Auction houses consistently headline the Red Book, which confirms that bidders
are expected to value it; a Classiche F40, for example, was explicitly presented
as retaining original factory-equipped matching-numbers equipment
([RM Sotheby's F40](https://rmsothebys.com/auctions/am20/lots/r0121-1992-ferrari-f40/)).
Counterexamples show why the caveat matters. A certified 1976 308 GTB
Vetroresina brought $184,800 in 2018 while an uncertified example brought
$192,500 in 2017; in another pair, a certified concours-restored car brought
$313,000 in 2023 and a concours-awarded uncertified car brought $257,600 in
2024. Certification did not erase specification, restoration, venue, colour,
and timing
([2018 certified](https://rmsothebys.com/auctions/mo18/lots/r0020-1976-ferrari-308-gtb-vetroresina-by-scaglietti/),
[2017 uncertified](https://rmsothebys.com/auctions/mo17/lots/r147-1976-ferrari-308-gtb-vetroresina-by-scaglietti/),
[2023 certified](https://rmsothebys.com/auctions/am23/lots/r0068-1976-ferrari-308-gtb-vetroresina-by-scaglietti/),
[2024 uncertified](https://rmsothebys.com/auctions/mo24/lots/r0105-1977-ferrari-308-gtb-vetroresina-by-scaglietti/)).

### Porsche Kardex, PPS, CoA, and CTC

Porsche's current documentation page draws the boundary cleanly. PPS transcribes
production-card items such as options, colours, engine/transmission *types*,
completion date, and MSRP when available, but omits serial numbers, original
dealer, owners, and warranty history. CTC adds a 63-point inspection, photographs,
the serial numbers currently installed, and Porsche's comparison of those
numbers with original records ([Porsche documentation](https://vehicledocumentation.porsche.com/usa)).
Porsche's FAQ says the original Kardex is not released and that the former CoA
program became PPS; it also excludes dealer-installed/Sonderwunsch work and
withholds ownership and warranty history ([Porsche FAQ](https://vehicledocumentation.porsche.com/usa/faqs)).

No credible controlled comparable-sale study was found for a Porsche certificate
premium. Auction catalogues use Kardex/CoA to substantiate build colour,
delivery, and matching-number claims—a 1957 356 Speedster documented by both
sold for $335,000—but that result also reflects model, condition, restoration,
and specification ([RM Sotheby's](https://rmsothebys.com/auctions/am20/lots/r0088-1957-porsche-356-a-1600-speedster-by-reutter/)).
The price-bearing fact is usually originality or matching numbers; the paper is
evidence for it. On newer mass-production Porsches, a certificate by itself has
no demonstrated premium.

One same-market pair illustrates the limit without proving a general rule: a
37,000-mile 1996 993 Carrera 4S with CoA sold for $159,000 and a 42,000-mile
1997 Carrera 4S without one sold for $158,000. The 0.6% spread is noise and the
cars differed in colour, options, and history
([CoA car](https://bringatrailer.com/listing/1996-porsche-911-carrera-4s-115/),
[non-CoA car](https://bringatrailer.com/listing/1997-porsche-911-carrera-4s-90/)).
These were individually indexed pages; Bring a Trailer blocks automated
fetchers and was not crawled or bulk-queried.

The irreducible Porsche gap is consequently narrower than Ferrari's: current
engine/transmission inspection *plus* comparison to the withheld factory serial
record. Build colours and options are often reconstructible from an original
sticker, service book, invoices, period photographs, or multiple independent
records. A PPS is convenient authority, not magic dust.

| Certification content | Can public + owner evidence reconstruct it? | Residual gap |
|---|---|---|
| Original colours, options, completion/delivery configuration | **Mostly**, when stickers, invoices, service books, photos, prior certificates, and period records survive | The factory ledger remains final authority when artifacts disagree. |
| Factory allocation of engine, gearbox, body, or other numbered parts | **Sometimes, not completely** | Ferrari's per-chassis archive and Porsche's unreleased Kardex/serial record contain exact pairings the public may not possess ([Ferrari archive](https://www.ferrari.com/magazine/articles/true-to-the-last-bolt), [Porsche FAQ](https://vehicledocumentation.porsche.com/usa/faqs?action=contactModal)). |
| Whether those components are physically present and unaltered today | **No** | Requires inspection of stampings, castings, hidden structure, repair evidence, and current parts. This is the irreducible work in Classiche and CTC. |
| Ownership, service, race, and sale chronology | **Often yes—and often beyond certification scope** | Private transfers and undocumented work remain gaps. Porsche withholds ownership/warranty history; auction catalogues pair Classiche with separate historian reports ([Porsche FAQ](https://vehicledocumentation.porsche.com/usa/faqs?action=contactModal), [Gooding F40](https://www.goodingco.com/lot/1991-ferrari-f40-1a/)). |

## Coverage model

These estimates assume a cooperative current owner supplies every document they
possess; the registry may use rights-clean government records and licensed factual
feeds, but no factory certification, unlicensed bulk scraping, or unsupported
inference. “Complete” is scored across four equal buckets: build data, ownership
chain, service events, and sale events. Event buckets measure material events,
not every oil change or private conversation. An ownership event counts when a
dated transfer/jurisdiction is defensible; publishing a natural person's name is
not required.

| Archetype | Build | Ownership | Service | Sale | Overall estimate | Auction use |
|---|---:|---:|---:|---:|---:|---|
| **1990s 911** | 75–90% | 40–60% | 45–70% | 50–75% | **53–76%** | Enough for an auction-grade dossier when the option sticker/service book, title artifacts, history report, and current inspection survive. The missing names and early independent-shop work remain explicit gaps. |
| **1960s Ferrari** | 70–90% | 65–90% | 25–55% | 65–90% | **56–81%** | Often excellent for a well-known competition or coachbuilt chassis because literature and catalogues follow the serial. It still cannot make the factory-backed matching-numbers/authenticity determination. Lesser-known road cars sit near the bottom of every range. |
| **Modern limited GT car** | 85–98% | 45–70% | 70–95% | 70–95% | **68–90%** | Usually auction-credible: window sticker/order sheet, digital and dealer invoices, inspection, photos, and online sale history cover most material facts. Privacy, off-market transfers, and work withheld by an owner cause the residual gap. |

The figures are estimates, not measured hit rates. They are grounded in the
source mechanics: owner-contributed systems can hold photos, dates, mileage and
service records ([VINwiki](https://vinwiki.com/faq/)); auction archives expose
serial/VIN-linked results but require licences for systematic commercial use;
government histories contribute registration/inspection events but commonly
withhold individuals or require owner/buyer authorization. A 100% claim would be
fraudulent precision.

## Verdict

Build the registry. The reachable evidence universe is large enough to make a
better auction dossier than any single marketplace page, especially for 1980s+
cars. Do not position it as a replacement certificate for early Ferraris. The
product claim should be narrower and stronger: **the most complete inspectable
record of what independent sources and successive owners can prove about this
chassis, with the remaining factory-only and physical-inspection gaps named**.

The model works only if contribution is governance rather than extraction.
The 356 Registry already says members may store cars and photographs while
administrators preserve historical records, and explicitly asks restorers to
document work and ownership changes truthfully
([356 chassis history](https://porsche356registry.org/content.aspx?club_id=579966&module_id=506611&page_id=22)).
VINwiki likewise demonstrates that owners will add photos, mileage, dates, and
service records when the resulting timeline helps the next owner
([VINwiki](https://vinwiki.com/)). The registry should give clubs and historians
attribution, correction authority, reciprocal access, and an exit path. Copying
their work into a commercial database would turn the strongest potential allies
into the first people warning owners away.

## Dead ends and negative findings

- **No public US make/model/year VIO table.** Experian and S&P sell the exact
  registration aggregate needed; public new-delivery tables are not a survival
  count ([Experian](https://www.experian.com/automotive/vehicles-in-operation-vio-data),
  [S&P](https://prod.azure.ihsmarkit.com/mobility/en/products/automotive-market-data-analysis.html)).
- **FIA HTP is not provenance.** It establishes historic-racing eligibility;
  the FIA disclaims chassis-number correctness ([FIA form](https://www.fia.com/file/12339/download)).
- **FIVA is owner-document infrastructure, not an open registry.** Its identity
  card is useful when contributed, but the back-end chassis search is for
  authorized processors ([FIVA code](https://www.fiva.org/storage/Documents/Technical%20Commission/FIVA.Ref_.TC03.2020.Tech_.Code_.Fin_.Copy_.V2.pdf?v20240611083638=)).
- **Germany's KBA/ZFZR is not a buyer-history service.** VIN-addressed holder
  information requires a substantiated accident, theft, damage, or legal claim
  ([official state service](https://www.service-bw.de/zufi/leistungen/6022739)).
- **Brazil RENAVAM is owner-credentialed, not public-by-VIN.** Query requires
  RENAVAM, plate, owner CPF/CNPJ and login; institutional access requires a
  contract and demonstrated need
  ([citizen service](https://www.gov.br/pt-br/servicos/consultar-dados-de-veiculo-na-base-renavam),
  [institutional access](https://www.gov.br/transportes/pt-br/assuntos/transito/senatran/catalogos-de-acessos-on-line-dos-sistemas-informatizados-da-secretaria-nacional-de-transito-senatran)).
- **INTERPOL's stolen-vehicle database is for law enforcement.** It is not a
  public VIN provider ([INTERPOL factsheet](https://www.interpol.int/content/download/15012/file/GI-04-Database-2023-04-EN.pdf)).
- **EU cross-border register exchange is authority-to-authority.** Prüm II
  supports VIN/historical queries between agencies but creates no consumer feed
  ([EU 2026/1066](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32026D1066)).
- **The FIA Historic Database is model-level.** Its thousands of homologation
  forms establish period specification, not chassis ownership, service, or race
  history ([FIA database](https://historicdb.fia.com/cars/list/)).
- **Major auction archives are not rights-clean feeds.** Sotheby's bars commercial
  use and automated extraction without permission; Bonhams bars scraping and
  exploitation. Public result pages remain pointers until licensed
  ([Sotheby's](https://www.sothebys.com/en/terms-conditions),
  [Bonhams](https://catalogues.bonhams.com/policies/terms-of-service)).
- **BaT and Rennlist blocks were respected.** Prior project research found that
  Bring a Trailer blocks automated fetchers; this survey used only individually
  indexed result pages. Rennlist returned HTTP 403 on direct open and was not
  retried or circumvented.
- **Barchetta is neither operationally reliable nor rights-clean.** Cached/indexed
  chassis pages are useful pointers, but no reusable licence was found and even
  Ferrari judging guidance says its claims require corroboration
  ([index](https://www.barchetta.cc/all.ferraris/by-serial-number/ferrari-by-serial-number/model-index-by-date/index.html),
  [judging guide](https://iacpfa.org/wp-content/uploads/2020/01/judging_older_ferraris__leyd.pdf)).
- **“Registry” often means forum or private membership database.** Early 911S
  has deep VIN-bearing threads but no disclosed structured export; PCA forms prove
  VIN data exists but consent rules prevent treating it as public data
  ([Early 911S](https://www.early911sregistry.org/forums/forum.php),
  [PCA 993 register](https://993registry.pca.org/register)).
- **Social video is discovery, not structured provenance.** A YouTube or Instagram
  post may reveal a chassis, date, condition, or owner-held document, but platform
  and creator rights attach to the media and captions. Store a link and a narrowly
  transcribed proposed claim unless the creator contributes the artifact.
- **No defensible Porsche certificate premium study was found.** Individual sales
  prove that cataloguers value Kardex/CoA as evidence, not the amount of a causal
  premium.
- **The Ferrari “~20% Classiche premium” is a hypothesis from a tiny observational
  sample.** It is useful evidence that certification affects bidding, not a
  valuation adjustment suitable for code ([Classic Car Trust](https://tcct.com/news/2020/07/certification-pays/)).
