# Owner Surface — design

*Tranche design for the 2026-08-01 reframe (TK-002): the day-one product is the
entry surface — a Fuelly-equivalent logbook — not the rendered page. The page is
the output of use; verification tiers are the sale-time payoff. This doc amends
the evidence contract's §11 roadmap: owner surface before document extraction
(TK-004 moves downstream).*

*Status: draft for Greg's section-by-section walk. Nothing here is ratified;
decisions flagged `GREG'S CALL` are his, not pre-resolved. No implementation
until the walk completes.*

Inputs: `docs/design/evidence_contract.md` (§8, §9, §11),
`docs/design/corpus.md` (friction log), TK-002 including the reframe note,
TK-004, `docs/research/porsche_ferrari_public_data_universe.md`, the registry
machinery (`lib/santo_api/registry.ex`, `registry/`), and a landscape survey of
car-logbook products (§0).

---

## 0. Landscape — what logbook products teach

Survey of consumer car-logging products, condensed; the full sourced survey
lives in `docs/research/logbook_landscape.md`.

**Fuelly (2008–present)** is the archetype the reframe named. Entry is a
micro-form with three required fields — date, odometer, volume — everything
else optional and hideable; an SMS grammar (`300 2.00 10`) served the
common case in one text. The payoff was computed from the log and displayed
publicly: an MPG trend, comparison against every other logged example of your
model, and an embeddable badge that lived in forum signatures — every post an
advertisement and a public commitment device. Development stagnated years ago;
people log anyway, because ten years of fill-ups is un-leavable. The
accumulated record is the retention moat.

**CARFAX Car Care** inverted entry entirely: VIN once, then shop-reported
service history auto-populates. The telling detail: owner-entered DIY records
are deliberately excluded from the sellable CARFAX report — CARFAX makes
history credible by trusting the *shop*, never the owner. The EU's digital
service records do the same via franchised dealers, to the point that owners
can't read their own record without a dealer request. **AUTOsist** pitched
receipt-photo-first entry ("snap the invoice") and resale transfer, then
pivoted to fleet SaaS — the recurring survival path for consumer logbooks
(Zubie likewise). Collector-specific tools (MCCL, MyCollection, Hagerty's My
Garage, GlobalWorkshop's shop-pushed restoration reports) are all small; none
became a standard.

**Forum build threads** (Rennlist, LotusTalk) are the highest-credibility
self-reported logs in existence: free text and photos, contemporaneous,
publicly witnessed, with post dates nobody can forge. BaT listings link them
and buyers pay for them. Their trust derives from structure — timestamped,
witnessed, append-only — not from any verifying institution.

**The dead.** Automatic Labs solved entry friction completely (OBD dongle,
zero-touch logging) and still died: the payoff never justified the hardware
plus subscription. Wheelwell built a mod-log social network and died fighting
entrenched forums for an audience; its users lost their build histories, which
taught enthusiasts to distrust startups with their records. aCar died of
acquisition-neglect. Nobody in this graveyard died of entry friction alone —
they died of **no payoff and no audience**.

**Lessons the design carries forward:**

1. **Entry friction is necessary, not sufficient.** Three required fields max,
   capture at the moment, one-line grammars for the common case (§1). But the
   thing that sustains logging is a payoff computed *from* the log, visible
   immediately and ideally publicly — Fuelly's badge, Strava's kudos. The
   public page and its stats are not downstream nice-to-haves; they are the
   retention mechanism (§6).
2. **Don't make the owner re-type what a document says.** The receipt photo is
   the natural unit of maintenance entry; structure is derived later, not
   demanded up front (§1, §8).
3. **Nobody has made pure self-reported logs credible to buyers** — CARFAX and
   the EU service books both solve it by delegating authorship to shops. The
   one credible self-reported form, the build thread, earns trust through
   contemporaneity + immutability + attribution — exactly what an append-only,
   content-hashed, party-attributed claims ledger formalizes (§3). This is the
   open gap Vin Santo sits in, and shop-authored entries are the eventual
   credibility unlock (§9 seam).
4. **The record is the moat, and export is the trust price.** Whoever holds
   ten years of history holds the owner — and must offer an exit path or be
   distrusted (the club-partnership memo reached the same conclusion
   independently).

---

## 1. Entry UX — the make-or-break

**The question.** What does logging a mod, a fill-up, a service visit, or a
photo take on a phone? Structured quick-forms per event type, free text parsed
by an LLM, or both?

**The shape of the problem.** The event types split by nature:

- **Fuel and mileage are arithmetic.** Odometer, volume, price — three numbers.
  A structured form is *faster* than typing a sentence, and the numbers feed
  deterministic computation (cost/mile, mileage history). An LLM adds nothing
  here except failure modes. Fuelly proved the 10-second structured fill-up
  entry two decades ago.
- **Mods and service are narrative.** "Changed the camber to 2.5 today" has no
  natural form — any modification form degenerates into a summary text field
  plus optional extras. The text *is* the value. Free text is not a fallback
  here; it is the native shape.
- **Photos and links are attachments,** not entries — they ride along on
  whatever entry they illustrate (or stand alone as a photo entry).

**Recommendation: both, split by nature — and ship v1 without the LLM.**

One entry surface, phone-first, one tap from the vehicle page: a segmented
composer with **Fill-up | Service | Mod | Note** modes.

- *Fill-up*: odometer, volume, total price (optional: grade, station, partial
  flag). Three fields, numeric keyboards, last-entry defaults. Produces an
  `event.fuel` claim + an `observation.mileage` claim, same date.
- *Service*: summary text, performer (optional), odometer (optional), photos.
  Produces `event.service` (+ mileage if given). **Receipt-photo-first is a
  supported path, not an afterthought** (landscape lesson 2): snap the
  invoice, type a five-word summary, done — the photo is an owner-supplied
  artifact attached to the claim, waiting for document extraction (TK-004) to
  upgrade the entry from tier-1 to receipt-backed later. The owner is never
  asked to re-type what the receipt already says.
- *Mod*: summary text, optional area/system, photos. Produces
  `event.modification`.
- *Note*: text + photos + a link. Produces `event.note`. The escape hatch —
  nothing the owner types is ever rejected for not fitting a form.

Date defaults to today, editable (owners back-fill history — the landscape says
back-filling a car's story is a first-session behavior worth designing for).
Every mode accepts photos. Total taps for a fill-up: open page → composer is
already on Fill-up → three numbers → save. That is the Fuelly bar and v1 must
hit it.

The LLM parse (free text → structured claims) is a **fast-follow behind the
same box**, not a v1 dependency — §8 makes the case, including the retroactive
upgrade path that makes deferral safe.

**Delivery: responsive LiveView, installable as a PWA.** No native app. The
entry moment is "standing at the gas pump / in the garage with greasy hands" —
mobile web must be genuinely first-class, not a shrunk bench. `GREG'S CALL` if
he disagrees that mobile-web-only clears the bar for v1.

**Caveat.** The reframe says entry friction decides whether anyone logs; the
landscape says something sharper — friction is necessary but *payoff* is what
sustains (Automatic Labs had zero friction and died anyway). So the entry UX
is only half the make-or-break; the other half is that every save visibly
improves something the owner can show off — the timeline grows, a stat
updates, the page gets richer (§6). And *session zero* needs designing: the
claim-flow handoff (§4) has to land a new steward in a back-fill moment ("add
your car's story — start with the last service"), or day-one retention dies
regardless of how good the forms are.

---

## 2. Vocabulary growth

The closed vocabulary (`registry/vocabulary.ex`) gains predicates test-first,
one code-reviewed change each, per fork B discipline. The logbook demands:

| Predicate | Scope | Value shape (jsonb) | Notes |
|---|---|---|---|
| `event.fuel` | event | `volume` (req, decimal-as-string), `unit` (req, `"gal"\|"l"`), `total_cents` (opt int), `currency` (opt), `grade` (opt), `station` (opt), `partial` (opt bool) | Money in integer cents, never floats. Cost/mile is computed, never stored. |
| `event.modification` | event | `summary` (req), `area` (opt string — suspension, engine, wheels…), `detail` (opt string) | `area` stays a free string in v1; an enum invites vocabulary bikeshed before we've seen real data. |
| `event.note` | event | `text` (req) | The escape hatch. Never conflicts, never comparison-relevant, tier-1 forever. |
| `observation.mileage` | observed | *(exists)* integer | Reused; fill-ups and service entries emit it alongside. |
| `event.service`, `event.sale` | event | *(exist)* | `event.service` gains nothing in v1; its `summary`+`performer` shape already fits. |

Equivalence for all new predicates is exact equality — none of them
participate in cross-source comparison in v1.

**Doesn't `event.note` gut the closed vocabulary?** No — the discipline exists
to protect *comparison and facts*: predicates whose values get compared across
sources need pinned semantics. A free-text event predicate never enters facts
(§8), never conflicts (events accumulate, §4), and never compares. The risk is
different: everything lands in `event.note` and structured data never
accumulates. Mitigations: the composer defaults to the structured modes, and
the §8 parser later proposes structured claims *from* existing notes — notes
are feedstock, not a dead end.

### Entry grouping — the §9 seam, made mechanical

Contract §9: a logbook entry is a *presentation* of claims sharing an event
scope — no separate entry store. But "sharing a scope" needs a grouping key:
a fill-up is two claims (`event.fuel` + `observation.mileage`); two entries on
the same date must not merge. And there's a latent collision: **event claims
dedupe by content hash** (`claims_vehicle_id_content_hash_index`), so two
legitimately identical events — same 10-gallon fill-up twice in one day — would
silently collapse into one claim. Real life has identical repeat events; the
current hash can't represent them.

**Recommendation:** a nullable `entry_ref` column on `claims` (UUIDv7, stamped
server-side at composition time, shared by all claims born of one entry), and
for **event-scoped claims only**, `entry_ref` joins the content-hash payload.
Presentation groups by `entry_ref`; identical repeat events get distinct
hashes; factory/observed claim hashing is untouched, so nothing in the corpus
or the attestation seam changes. This is a grouping tag, not an entry store —
no table, no entry lifecycle, entries have no state of their own. Artifacts
(photos) gain the same nullable `entry_ref` so a multi-photo entry hangs
together (a claim's single `artifact_id` can't carry three photos).

**Caveat:** putting `entry_ref` in the event hash means re-proposing "the same"
event from a different entry creates a second claim rather than deduping. For
events that is correct — occurrence identity *is* entry identity — but it's a
semantic narrowing of the hash worth stating out loud. `GREG'S CALL` to ratify
the hash change; it touches the attestation seam (load-bearing, per CLAUDE.md).

### Links are curation, not evidence

TK-002's owner-curated links (IG, YouTube, forum threads) are rights-clean
pointers. They are not artifacts — an artifact is an immutable acquired thing,
and we haven't acquired anything. **Recommendation:** a small `vehicle_links`
table owned by the stewardship (URL, label, position — mutable, presentation
layer, no ledger contact). "Artifacts-in-waiting" stays literal: a later
acquisition can snapshot a link target into a real artifact through the
provider machinery, with rights handled then.

---

## 3. The owner claim path — no operator in the loop

**The question.** Owner entries at scale can't queue behind an operator at
/bench. Do they auto-admit, or self-ratify through the existing gate? The
doctrine says "external evidence enters `:proposed`" — and owners are external.

**What admission actually means.** `:admitted` means "part of the record," not
"true." Truth-adjacent display is the verification tier, computed from basis:
an owner's claim with no independent artifact is tier-1 self-reported no matter
what state it's in. And event-scoped claims never enter `facts`, never
conflict, and never affect verified status of anything (§4, §8). Admission of
an owner's own logbook entry is *low-stakes by construction* — the ledger's
honesty lives in attribution and tier, which are already mechanical.

Meanwhile ratification is defined as "one state flip with who and when
attached" — the *who* is the point. For a mod entry, nobody on earth is better
positioned to vouch than the owner who did the mod. An operator rubber-stamp
adds latency and zero epistemics.

The landscape backs this from the other side: the only self-reported logs
buyers actually trust are forum build threads, whose credibility comes from
contemporaneous, immutable, attributed, publicly-witnessed entries — not from
anyone ratifying them. Owner-admitted claims in an append-only, content-hashed,
party-attributed ledger are that structure, formalized. Withholding admission
pending an operator wouldn't add the trust; the ledger's shape already
carries it.

**Recommendation: scope-split self-ratification.**

- **Event- and observed-scope claims** on a vehicle the user has an active
  stewardship for (§4): proposed and ratified by the owner **in one
  transaction** — `Registry.propose_claim/3` with the owner's party, then the
  flip, owner recorded as ratifier. The gate's *shape* is preserved (every
  claim passes through `:proposed`, every admission has a who/when); only the
  latency collapses. For §8's LLM-parsed entries the two steps genuinely
  separate: parse → `:proposed` → owner's confirmation tap *is* the
  ratification. Same machinery, same audit trail.
- **Factory- and provenance-scope claims from owners** ("my paint code is
  226") enter `:proposed` and wait for the operator gate or corroborating
  evidence — unchanged. These touch `facts` and the verified display; owner
  say-so must not flip a fact to verified. This line is bright and mechanical:
  `Vocabulary.scope_kind/1` already knows it.

This amends the doctrine sentence from "external evidence enters `:proposed`
(operator ratifies)" to: *external evidence enters `:proposed`; who may ratify
depends on scope — owners self-ratify event/observed claims on cars they
steward; factory/provenance claims ratify only at the operator gate or by
evidence.* `GREG'S CALL` — this is a contract invariant amendment, the doc's
most consequential ask.

**Machinery gap this exposes:** `ratify_claim/1` (`registry.ex:149`) records
no who or when — the contract's "who and when attached" was never built,
because the only ratifier was the bench. Owner self-ratification makes it
mandatory: add `ratified_by_party_id` + `ratified_at` to `claims`, stamped in
`flip_claim`, backfilled as Vin Santo/insertion-time for the corpus. Same for
`reject_claim`.

**Caveat.** Self-ratification means a malicious steward can pump self-reported
events into a page unsupervised (they can already say anything on Instagram;
here it's at least attributed, append-only, and tier-labeled). The real
exposure is *fraudulent history built in advance of a sale* — mitigated by
tier display (a wall of tier-1 entries with zero receipts reads as what it
is), by the §4 abuse posture, and at sale-time by the dossier's tier
composition. Accepted risk; flag if it isn't.

---

## 4. Claiming flow — proof of possession

**Ratified frame (TK-002):** possession proof gates claiming; title proof is
deferred to transfer (layer 5) where it's the product. Possession = photo of
the car's VIN plate with a challenge code in frame, domain-verification style.

**End-to-end flow:**

1. Authenticated user hits "This is my car" on a vehicle page (or lands there
   from lookup, §7).
2. Registry issues a short challenge code (8 chars, unambiguous alphabet),
   bound to (user, vehicle), 72-hour expiry, single active challenge per pair.
3. Owner photographs the VIN plate (windshield or door-jamb sticker) with the
   code handwritten in frame, uploads in the same flow. Upload becomes an
   owner-supplied artifact (kind `:photo`), source party = the owner's party —
   **which requires fixing `create_upload_artifact/1`, which today stamps
   every upload `source_party_id: vin_santo_party()`** (`registry.ex:117`).
4. **Verification: LLM vision pre-check, human decision.** A vision model
   reads the photo and reports (VIN legible? matches? code present and
   matching? plate looks in-situ vs. photographed-off-a-photo?). Its output is
   a *proposal*; an operator approves with one tap at /bench. LLMs extract,
   code computes, humans admit — same doctrine, new artifact type. At current
   scale (dozens/week at most) this costs minutes a day and buys eyes on every
   claim during exactly the period we're learning the abuse patterns.
   Auto-approve on high-confidence checks is a later flip, taken when volume
   forces it — not before.
5. Approval creates a **stewardship**: a `stewardships` row (user, vehicle,
   proof artifact, status `active`, decided_by/at). Revocation is a status
   flip plus a reason — rows never delete; entries made under a revoked
   stewardship stay in the ledger, attributed.

**Stewardship is authz, not registry truth.** Deliberately, claiming creates
*no* ownership claim in the ledger. Possession-proof proves access to the car,
not title; writing `ownership` into the record on that basis would assert more
than the evidence supports (the copy doctrine, applied to data). The ownership
*chain* is layer-5 territory with title-grade evidence. The public page says
"maintained by @handle", never "owned by".

**Abuse posture — the Carrera GT problem.** Someone photographs the corpus
Carrera GT's VIN plate at a show and claims a $4.5M car:

- The challenge code defeats *pre-existing* photos — the code didn't exist
  when they were at the show. The attacker needs to return to the physical car
  with their code, which for high-value cars means defeating physical access,
  not our flow.
- What claiming unlocks is bounded: curation and tier-1 self-reported entries
  under their own attributed identity. Not identity edits, not facts, not
  anything verified. The blast radius is graffiti, not forgery — and
  append-only graffiti under the vandal's own name.
- Counter-claim: a second user claiming an actively-stewarded vehicle
  triggers escalation — both parties notified, operator adjudicates, and the
  tiebreaker is stronger evidence (registration/title fragment, service
  records in their name), pulling forward a *narrow* slice of title-proof
  only for contested cases. Contested stewardship is rare and worth an
  operator's minutes.
- Flag list: vehicles above a value/notability threshold (all three corpus
  cars qualify) get a mandatory closer look at step 4 regardless of vision
  confidence.

**What an unclaimed page shows:** identity, facts with tier display, the
registry-sourced timeline (sale events, service events from documents), links
we hold, and the claim CTA — "Is this your car?". The seeded-but-incomplete
page is the bait (Google Maps mechanic, per TK-002).

**What claiming unlocks:** the composer (§1), link curation (§2), photo
uploads, privacy controls (§6), and a claimed badge on the page. The
post-approval handoff lands the owner in the back-fill moment (§1 caveat).

---

## 5. Auth

First non-operator surface, so auth arrives now (contract §11 anticipated
this). **Recommendation: `phx.gen.auth` in its Phoenix 1.8 magic-link-first
configuration.** Rationale: it's the boring, maintained, in-stack answer
(minimal-dependency preference); magic link fits a low-frequency utility app —
owners log in occasionally per week, password amortization never pays for the
reset-flow support burden; and the generated code is plain contexts + Ecto we
own outright, consistent with no-Ash. Passwords can be enabled later without
migration drama; don't ship them in v1.

**User ↔ Party.** Auth users and registry parties stay separate tables with a
link: on first assertive act (claiming, first entry), the user gets a `Party`
row (kind `:owner`) referencing their user id. Parties are the ledger-side
asserting identity (per-claim attribution, tier computation); users are
credentials. Keeping them separate means the ledger never depends on the auth
system's shape — a party can outlive its user account, which matters because
claims attributed to it are immutable.

**What the account model owes layer 5 (transfer):** durable party identity
(above), verified email, and the stewardship history (§4's status-flip
lifecycle gives transfer its spine: transfer is, mechanically, one stewardship
ending and another beginning with title-grade evidence attached). Nothing else
— no orgs, no teams, no roles beyond operator/owner. Resist building for
layer 5 beyond these three commitments.

Operator surface: /bench gets `require_authenticated_user` + an operator flag
on users, replacing the nothing it has today. Still not exposed publicly
beyond that.

---

## 6. The public page

**Canonical URL.** Contract §1: identity is an attribute and the URL must
survive identity correction. So the canonical URL keys the *row*, not the VIN:
`/v/:public_id` (short, stable, generated at row creation). VIN paths
(`/vin/WP0AB29827U782968`) are resolvers that 302 to canonical — good for
lookup, sharing, and search engines, but never the identity the page hangs on.
VINs are not secrets (windshield-visible, printed on every listing), so VIN
visibility on the page is fine. `GREG'S CALL` only if he wants vanity slugs
(`/v/linden-green-touring`) in v1; recommendation is no — vanity is ornament,
add it when owners ask.

**What renders:**

- Identity block: marque/model/year, VIN, claimed-by badge.
- Facts with tier display — verified / unverified / conflicted rendered
  honestly (the §8 statuses), each fact expandable to its claims and evidence.
  Conflicts show as conflicts; absence shows as a gap. Copy never asserts more
  than the ledger supports.
- Tier composition strip ("62% of build facts document-backed") — the §7
  aggregate, the sale-time pitch rendered as a stat.
- The timeline: event/observed claims grouped by `entry_ref` into entries,
  newest first — the logbook. Registry-sourced events (BaT sale, dealer
  service invoices) and owner entries interleave, visually distinguished by
  tier and asserting party.
- Photo gallery (owner artifacts marked public), link list (§2).
- **An embeddable badge** — small image/snippet with the car, headline stat,
  and page link, built for forum signatures and IG bios. Fuelly's badge was
  its growth loop and public-commitment device for a decade; this is cheap
  (one controller rendering an SVG) and it aims the product straight at the
  people who already narrate their cars on forums. In v1 scope.

**Export from day one.** The owner can download their complete record —
claims, entries, artifacts — in a documented format, no gatekeeping. The
landscape's trust price (lesson 4): Wheelwell's death losing users' build
histories taught this community to distrust startups with their records, and
the club-partnership memo demands an exit path. Export costs little and is
the standing answer to "why would I pour ten years of history into you."

**Privacy controls.** The split that keeps this coherent: **registry facts are
public; owner contributions are the owner's.**

- Factory/provenance facts, and events sourced from public documents (the BaT
  sale, the auction history) are the registry's record — owners cannot hide
  them. A registry where owners can suppress the public record isn't a
  registry.
- Owner-contributed entries, photos, and owner-logged mileage: per-entry
  visibility toggle (`public` / `private`), default **public** — the product
  thesis is show-off-your-car; private-by-default would strangle the network
  effect at birth. One tap to make any entry private at composition or later.
  `GREG'S CALL` — this default is a product-values call and reasonable people
  land both ways; the research memo's club-partnership posture
  ("private-by-default owner vaults") argues the other side for *contributed
  documents*, which suggests a middle line: entries default public, uploaded
  *documents* (titles, invoices with addresses) default private.
- Visibility is presentation state, not ledger state: a mutable `visibility`
  column on claims/artifacts, excluded from `content_hash`, no effect on
  admission or tier. A private entry still exists in the ledger and appears in
  the owner's own view and in any full dossier the owner chooses to share at
  sale time (the HistoVec pattern: owner-generated report, owner-controlled
  disclosure). Public tier-composition stats compute over public entries only,
  so the stat never leaks the existence of hidden history — the public page
  shows a *floor*, and sale-time disclosure can only improve on it.

**Integrity caveat, stated honestly:** a buyer reading the public page sees
what the owner chose to show plus what the registry independently holds.
That is exactly what the copy must say — self-reported entries were never a
guarantee, gaps are gaps, and the buyer-grade product is the sale-time dossier
with disclosure the seller commits to, not the public page.

---

## 7. Seeding

**Recommendation: create-on-first-lookup, corpus cars as showcase.**

- Public lookup box: enter a VIN → `Registry.ingest/1` (idempotent, keyed on
  identity) → santo decode (admitted) + vPIC (proposed) fire → page exists,
  populated with rights-clean facts. The visitor lands on a real page with
  real facts and a claim CTA. Lookup is free without an account;
  unauthenticated lookup is rate-limited (mass VIN enumeration creates junk
  rows and burns vPIC quota; a modest per-IP ceiling is proportionate defense).
- The three corpus cars are the showcase: fully-documented pages
  demonstrating what the product looks like at maturity — the Carrera GT's
  page shows sale history, service events, mileage history, adjudicated
  conflicts, tier display, all real. Landing/marketing links point there.
- **No pre-seeding at scale in v1.** Bulk-creating 1.25M thin Porsche pages
  (the research memo's plausibly-coverable US population) buys SEO thin-content
  risk and no claiming bait beyond what lookup provides, before there's an
  audience to bait.
- **The seam, left open deliberately:** the research memo's tier-1
  acquisitions (licensed VIO extract, CLASSIC.COM/auction-history licence,
  club partnerships) arrive through the existing provider machinery as
  capability mappers — batch acquisition creating vehicles + proposed claims
  is `persist_acquisition/2` in a loop, no new architecture. When a licensed
  feed lands, pre-seeding specific high-value cohorts (e.g., every US 356)
  becomes a provider run, gated on the rights profile, targeted where a
  community exists to claim them.

---

## 8. Free-text extraction — v1 or fast-follow?

**Recommendation: fast-follow, with the seam designed into v1.** Three
reasons:

1. **No v1 event type needs it.** Fuel is a 3-field form that beats a sentence
   on speed (§1). Mods and notes are text whose text *is* the value — they
   save instantly as `event.modification`/`event.note` with zero parsing. v1
   entry friction is already at the Fuelly bar without a model in the loop.
2. **The retroactive upgrade makes deferral free.** Because notes land in the
   ledger as claims with text values, the parser can later propose structured
   claims *from existing notes* ("this note mentions 41,200 miles — log it?").
   Nothing entered before the parser ships is wasted; owners' old entries get
   *better*. A v1 dependency would delay shipping for capability we can
   deliver to already-captured data later.
3. **Same UI contract either way.** The composer's text box doesn't change
   when the parser arrives — the box gets smarter behind the same surface.
   No rework.

**The contract, specified now so the seam is real:** utterance + vehicle
context → model (a small, fast one — this is Haiku-class work) emits claim
candidates strictly within the closed vocabulary: `[{predicate, value,
scope_date}]` + a residual note. UI renders candidates as chips —
"⛽ 13.2 gal · $67.98" / "📏 41,200 mi" — owner taps to confirm (that tap is
the §3 ratification), edits, or dismisses to plain note. Anything not
confidently parsed falls through to `event.note` untouched; the model
abstains rather than guesses; nothing auto-admits. `method: :llm_extract`,
prompt+model in `method_meta`, per corpus-friction lesson: capture the owner's
corrections as signal, prefer deterministic post-parse fixes over prompt
tinkering.

**Trigger to build it:** if post-launch entry data shows note-mode dominating
structured modes (owners telling us forms are friction), the parser jumps the
queue. Define the check now: ratio of structured claims to `event.note`
claims per active steward, reviewed at 30 days.

`GREG'S CALL` — the reframe note leaned "first extraction is likely owner free
text," so v1-inclusion is a defensible read of intent; this recommendation
trades a smaller v1 for an earlier one.

---

## 9. Roadmap amendment and ticket decomposition

### Proposed §11 rewrite (drafted for ratification, not applied)

> ## 11. Roadmap (amended 2026-08-XX with Greg — owner surface before
> document extraction)
>
> The 2026-08-01 reframe: the day-one product is the owner entry surface — a
> logbook whose entries are event/observed-scope claims — not the rendered
> dossier. The page is the output of use; verification is the sale-time
> payoff. Auth arrives with this, the first non-operator surface.
>
> Done: registry schemas + ingest · vPIC evidence · facts projection ·
> provider abstraction · operator bench · dossier corpus (three cars,
> adjudication casebook) — original tranches 1–2.
>
> 3. **Owner surface** (docs/design/owner_surface.md): auth (magic link) ·
>    public vehicle pages with create-on-first-lookup · claiming via
>    possession proof · logbook vocabulary (`event.fuel`,
>    `event.modification`, `event.note`) · phone-first entry composer ·
>    scope-split self-ratification · privacy controls.
> 4. **Owner free-text extraction** — utterance → proposed claims → owner
>    confirms; the smallest extraction that kills entry friction. Triggered
>    early if entry data demands it.
> 5. **Document extraction** (TK-004) — the corpus friction log's stances;
>    now also fed by owner-uploaded receipts accumulating from tranche 3.
> 6. **Dossier rendering** — the sale-time output: facts, tier composition,
>    timeline, citations, owner-controlled full disclosure.
> 7. **More providers** — NMVTIS/auction-history/VIO per the public-data
>    census (docs/research/); club partnership pilots; PPS as async order.
> 8. **Shop-authored entries** (seam, unscheduled) — the landscape's
>    credibility unlock: the party doing the work writes the claim
>    (CARFAX's shop feed, GlobalWorkshop's pushed restoration reports).
>    Shops are already `parties`; a shop-scoped entry path turns tier-1
>    logbooks into third-party-attributed ones without any new ledger
>    machinery.

Note what moving document extraction *after* the owner surface buys it: by the
time TK-004 builds, there's a stream of owner-uploaded receipts attached to
real logbook entries — extraction gets a live corpus and a motivated
ratifier (the owner upgrading their own tier-1 entries to receipt-backed),
instead of only operator-fed auction documents.

### Proposed build tickets (drafted for approval — not filed)

| # | Ticket | Depends on | Notes |
|---|---|---|---|
| A | Auth + accounts: `phx.gen.auth` magic link, User↔Party link, operator flag, /bench behind auth | — | |
| B | Ledger prerequisites: `ratified_by_party_id`/`ratified_at`, `entry_ref` column + event-hash amendment, artifact `source_party_id` fix, `visibility` columns | — | Load-bearing (claim ledger) — main-thread work, not delegated. Test-first; corpus re-run green is the acceptance test. |
| C | Logbook vocabulary: `event.fuel`, `event.modification`, `event.note` + validators + tests | — | Small, test-first. |
| D | Public vehicle page: `/v/:public_id`, VIN resolver, facts + tier display, timeline grouped by `entry_ref`, lookup + create-on-first-lookup, rate limit, embeddable badge | B | Read-only; ships before claiming exists (unclaimed pages are the bait). |
| E | Claiming: challenge codes, proof upload, vision pre-check, /bench approval queue, stewardships | A, B | |
| F | Entry composer: four modes, photos, links table, scope-split self-ratification path | A, B, C | The make-or-break ticket; §1 is its spec. |
| G | Privacy controls + owner's own-view + full-record export | F | |
| H | Free-text parse fast-follow | F | §8's contract; triggered by the 30-day entry-mix check. |

A→E→F is the critical path; B, C, D parallelize ahead of it. D ships value
(public pages, lookup) before any auth exists — layered commits, each green.

### Decisions queued for the walk, in order

1. §3 — scope-split self-ratification (contract invariant amendment). The big
   one.
2. §2 — `entry_ref` in the event-claim content hash (attestation seam).
3. §6 — privacy default (entries public, documents private?).
4. §8 — LLM parse as fast-follow vs v1.
5. §1 — mobile-web-only v1.
6. §9 — the §11 rewrite text and ticket cut.
