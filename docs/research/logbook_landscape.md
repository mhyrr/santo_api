# Car-Logbook / Vehicle-History Consumer Products — Landscape Survey

*Research memo, 31 July 2026. Input to the owner-surface design
(`docs/design/owner_surface.md` §0, which condenses this). Web survey; no
product was purchased or crawled.*

## 1. Fuelly (2008–present) — the canonical fuel log

- **Entry mechanism:** structured micro-form. Required fields per fill-up:
  **date, odometer, fuel volume** — everything else (price, time, partial/full
  flag, city-% slider, notes) is optional and hideable
  ([Fuelly FAQ](https://www.fuelly.com/index.php/faq/full),
  [Gas Cubby entry docs](https://www.fuelly.com/gascubby/support/2.5/gcgasentry.html)).
  This is the archetypal "10-second entry at the pump."
- **SMS entry:** text `miles price gallons` (e.g. `300 2.00 10`) to a phone
  number; extra text becomes the note; a `c75` token = 75% city driving;
  letter prefixes select among multiple vehicles
  ([SMS FAQ](https://www.fuelly.com/index.php/faq/22/fuelup-via-SMS),
  [SMS tip](https://www.fuelly.com/tips/458/Use-Fuellys-SMS-Service)).
  Entry-channel breadth (web, SMS, later iOS/Android) was a deliberate
  friction-reduction strategy from launch (2008, Matt Haughey and Paul
  Bausch — [Silicon Florist](https://siliconflorist.com/2008/08/11/fuelly-saving-fuel-through-social-networking/),
  [Quantified Self](https://quantifiedself.com/blog/matt-haughey-on-sharing-gas-mi/)).
- **What the log unlocks:** computed MPG trend, comparison against every other
  logged example of your model ("browse vehicles" pages), and an embeddable
  MPG badge widely used as a **forum signature** — every forum post an
  advertisement and a public commitment device. The Quantified Self framing:
  sharing and comparing mileage data is the payoff, not the log itself.
- **Current state:** still running; acquired by App Cubby/Contrast (Gas
  Cubby's developer) in 2012, merged with Gas Cubby (iOS) and acquired
  **aCar** (the leading Android log) in 2014
  ([Fuelly & aCar Unite](https://www.fuelly.com/acar/announcement/)).
  Development largely stalled — aCar effectively discontinued since ~2018
  ([AlternativeTo](https://alternativeto.net/software/acar/about)), the merge
  was rocky ([forum thread](https://www.fuelly.com/forums/f42/fuelly-acar-merge-went-haywire-19788.html)),
  and a later subscription move irritated legacy users. Yet people still log —
  10+ year continuous histories are common; the accumulated record itself is
  the lock-in.
- **Provenance role:** none. Self-reported, unverified; useful socially, not
  transactionally.

## 2. General maintenance-log apps

- **Drivvo** — structured forms for fuel/expense/service; strongest at
  reporting and cross-vehicle cost comparison; scales to small fleets;
  subscription ([comparison](https://obdeleven.com/car-maintenance-apps),
  [roundup](https://carmaintenance.app/best-car-maintenance-tracking-apps/)).
  Unlocks: budgets + reminders.
- **Simply Auto** — adds **automatic trip detection** (GPS) to reduce entry
  burden; imports from Fuelly/aCar/Fuelio/Drivvo — data portability is a real
  acquisition channel in this niche
  ([Google Play](https://play.google.com/store/apps/details?id=mrigapps.andriod.fuelcons)).
- **aCar** — the power-user Android app; killed slowly post-acquisition.
- **CARFAX Car Care / myCARFAX** — the inversion: **zero-entry logging**.
  Enter VIN/plate once; service history auto-populates from CARFAX's shop
  feed, reminders derive from it
  ([carfax.com/Service](https://www.carfax.com/Service/)). Crucially,
  **DIY records a user adds personally do NOT appear on the sellable CARFAX
  report** — only shop-reported, VIN-linked invoices do
  ([BobIsTheOilGuy thread](https://bobistheoilguy.com/forums/threads/does-the-my-carfax-diy-info-show-up-on-a-carfax-check.336758/)).
  CARFAX solved credibility by trusting the shop, not the owner — the owner's
  own log remains second-class.
- **AUTOsist** — receipt-photo-first entry ("snap the invoice"), pitched
  explicitly on resale: "show future buyers a report of your maintenance
  history and transfer it to the new owner with one click"
  ([autosist.com](https://autosist.com/)). Consumer side atrophied; pivoted to
  **fleet SaaS** ([Software Advice](https://www.softwareadvice.com/fleet-management/autosist-profile/)) —
  a recurring pattern: consumer logbooks that survive do so by becoming fleet
  tools (Zubie did the same).
- **Road Trip MPG** — long-lived paid iOS app, one-time purchase, local data,
  no social; survives as a lifestyle business precisely because it never
  needed scale.
- **EU digital service records** — manufacturers (VW/BMW/Mercedes/Audi)
  replaced stamped books with dealer-written **manufacturer databases**,
  mostly 2010–2015; owners often can't read their own record without a dealer
  request ([Motorpoint explainer](https://www.motorpoint.co.uk/car-care/digital-service-record-what-is-it));
  third parties like [OE Service](https://www.oeservice.eu/en/) broker access
  for independents. Credible-to-buyers, but owner-hostile — the owner is a
  spectator to their own car's record.
- **Collector-specific:** [The Classic Car Register](https://classicprovenance.com/)
  (chassis-number research, source-backed records — closest in spirit to a
  registry), MCCL ([App Store](https://apps.apple.com/us/app/mccl-car-history-logbook/id1495806681))
  and [MyCollection](https://www.mycollection.world/) (document vaults pitched
  as value preservation), [GlobalWorkshop](https://www.globalworkshop.com/features/collectors_edition)
  (restoration shops push progress reports into the owner's master record via
  a code — **third-party-written entries as provenance**),
  [Loggy.com](https://www.loggy.com/), Hagerty's My Garage inside Marketplace
  (store title/service docs, show off cars — feeds their auction funnel:
  [hagerty.com/marketplace](https://www.hagerty.com/marketplace/my-garage)).
  All small; none has become a standard.
- **Forum build threads (LotusTalk, Rennlist, etc.)** — free text + photos,
  chronological, publicly witnessed for years, community replies timestamping
  the history. The highest-credibility *self-reported* logs in existence: BaT
  listings routinely link build threads, and documented history is explicitly
  cited by buyers as a reason to pay more
  ([ReserveLane on BaT selling](https://www.reservelane.com/post/what-it-really-takes-to-sell-a-car-on-bring-a-trailer)).
  Credibility comes from contemporaneity + witnesses + unforgeable posting
  dates, not from structure.

## 3. Strava — the reference model

Logging is near-zero-friction (automatic capture; entry = pressing start), and
the payoff is immediate and social: kudos (14B+/yr), segment leaderboards,
streaks, clubs. Social streaks average 5.69 days vs 4.25 without social
visibility; club members are >2x as likely to log weekly; group-activity
loggers retain better at 12 months
([Trophy case study](https://trophy.so/blog/strava-gamification-case-study),
[StriveCloud](https://www.strivecloud.io/blog/app-engagement-strava)). The
cultural artifact — "if it's not on Strava it didn't happen"
([case study](https://medium.com/@fordavid22/if-its-not-on-strava-it-didn-t-happen-a-strava-case-study-on-how-fitness-meets-community-aac54ae92aae)) —
is the endgame: the record *is* the product, and abandoning the app means
abandoning your own history.

## 4. The dead

- **Automatic Labs** — OBD dongle, auto-logged every trip/fill-up. Acquired by
  SiriusXM for ~$100M (2017), shut down May 2020; hardware bricked, data
  export deadline ([SlashGear](https://www.slashgear.com/automatic-labs-connected-car-dongle-shutdown-iot-siriusxm-01618989/),
  [MacRumors](https://www.macrumors.com/2020/05/01/automatic-shutting-down-may-28/)).
  Automatic capture solved friction but never found a payoff worth the
  subscription; hardware COGS + platform dependence killed it. Dash Labs,
  Mojio, Vinli followed similar arcs
  ([Nanalyze](https://www.nanalyze.com/2017/04/10-connected-car-technology-startups/));
  Zubie retreated to fleet.
- **Wheelwell** — car social network / mod-log by ex-Apple folks; died early
  2023, no funding after 2019
  ([opposite-lock thread](https://opposite-lock.com/topic/80847/anyone-know-what-happened-to-wheelwell),
  [Crunchbase](https://www.crunchbase.com/organization/tracktopia)).
  Build-profile logging without the forum's existing audience; parts-affiliate
  monetization didn't carry it. Users lost their build histories — reinforcing
  enthusiasts' trust in forums over startups.
- **Petrolicious** — content/community adjacency, folded; media economics, not
  logging.
- **aCar** — killed by acquisition-then-neglect, not by users leaving.

## Lessons

- **(a) Repeat logging needs a payoff computed *from* the log, visible
  immediately and ideally publicly.** Fuelly's MPG number + forum-signature
  badge, Strava's kudos/segments. A log that only pays off "someday at sale"
  doesn't sustain entry; reminders (CARFAX, Drivvo) sustain *passive*
  retention but not active contribution.
- **(a) The accumulated record itself becomes the retention moat.** Ten years
  of fill-ups makes Fuelly un-leavable even after the product stagnates;
  import tools (Simply Auto) exist precisely to attack this. Whoever holds the
  history holds the user — and must offer export or be distrusted.
- **(b) What killed the dead:** hardware cost + subscription for a payoff
  users didn't value (Automatic); building a social graph from scratch against
  entrenched forums (Wheelwell); acquisition-neglect (aCar); no revenue
  attached to the record. Nobody notably died of entry friction alone — they
  died of **no audience and no payoff**.
- **(c) No one has made pure self-reported logs credible to buyers.** CARFAX
  explicitly excludes owner-entered DIY records from the sellable report —
  credibility is delegated to shops via VIN-linked invoices. The EU digital
  service book delegates to franchised dealers. The only credible
  *self*-reported form is the forum build thread, whose trust derives from
  contemporaneous, witnessed, third-party-timestamped entries — exactly the
  structure a claims ledger can formalize (owner-proposed, artifact-attached,
  corroborated later). This is the open gap Vin Santo sits in.
- **(c) Third-party-written entries are the credibility unlock:**
  GlobalWorkshop's shop-pushed restoration reports and CARFAX's shop feed both
  show the pattern — let the party doing the work write the claim, let the
  owner curate.
- **(d) Entry friction patterns that work:** 3 required fields max with
  everything else optional/hideable (Fuelly); a text-message/one-line grammar
  for the common case; photo-of-receipt as the primary artifact with structure
  extracted later (AUTOsist); zero-entry auto-population from a feed where
  possible (CARFAX); capture-at-the-moment (at the pump, at the shop) rather
  than batch data-entry sessions.
- **(d) Anti-pattern:** making the owner re-type what a document already says.
  The receipt/invoice/photo is the natural unit of entry for maintenance;
  structured claims should be derived from it, not demanded up front.
