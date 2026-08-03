# Owner Surface — design

*Tranche design for the 2026-08-01 reframe (TK-002): the day-one product is the
entry surface — a Fuelly-equivalent logbook — not the rendered page. The page is
the output of use; verification tiers are the sale-time payoff. This doc amends
the evidence contract's §11 roadmap: owner surface before document extraction
(TK-004 moves downstream).*

*Status: draft for Greg's section-by-section walk. Nothing here is ratified;
decisions flagged `GREG'S CALL` are his, not pre-resolved. No implementation
until the walk completes.*

*Revised 2026-08-01 after walk feedback, round 1: audience is the payoff, not
a badge (§0, §6); the agent entry surface — voice through the owner's own
LLM via MCP — replaces the embedded-parser plan (§1, §8); distribution kit
for crossposting to existing audiences (§6); `event.outing` added (§2).
Round 2: supporting infrastructure itemized (§9 — accounts, operator admin,
per-platform integrations, plumbing); roadmap section renumbered to §10;
tickets extended to A–L.
Round 3 (2026-08-01): build starts with infra (§9: tickets J, A, B first);
`current_state` added as a second projection that replays the logbook into
"the car now" (§2b), with a seed trait vocabulary sized for swapped/raced
cars, not just originality; page hierarchy inverted — the living car leads,
provenance is the foundation layer, not the headline (§6).*

## The product shape

One loop, stated once so every section below serves it:

**Speak → ledger → audience.** The owner talks to the assistant they already
have — at the pump, in the paddock, under the car — and their words become
attributed, timestamped, append-only claims they confirm with a word. The page
assembles itself from the accumulating log: timeline, stats, photos, links.
Every entry is one tap from the audiences the owner already narrates to —
forum thread, Instagram, YouTube — as a post that points back at the canonical
record. Verification tiers ride silently underneath the whole time: entries
are born tier-1, receipts and corroboration upgrade them, and at sale the log
the owner kept for the audience turns out to be the dossier.

Entry costs a sentence. The payoff is an audience. The moat is the record.

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

1. **Entry friction is necessary; an audience is what sustains.** Three
   required fields max, capture at the moment, one-line grammars for the
   common case (§1). But people keep logging when they know someone is
   watching — the same reason social media works. Strava's numbers are
   explicit (social streaks 5.7 vs 4.3 days; club members >2x weekly logging),
   and build threads run for a decade because replies keep coming. The
   corollary from Wheelwell's grave: don't build the audience — **pipe entries
   to the audiences owners already have** (their forum thread, their IG),
   with the page as the canonical record those posts point back to (§6).
2. **Don't make the owner re-type what a document says.** The receipt photo is
   the natural unit of maintenance entry; structure is derived later, not
   demanded up front (§1, §8).
3. **Nobody has made pure self-reported logs credible to buyers** — CARFAX and
   the EU service books both solve it by delegating authorship to shops. The
   one credible self-reported form, the build thread, earns trust through
   contemporaneity + immutability + attribution — exactly what an append-only,
   content-hashed, party-attributed claims ledger formalizes (§3). This is the
   open gap Vin Santo sits in, and shop-authored entries are the eventual
   credibility unlock (§10 seam).
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

**Recommendation: two entry surfaces, neither of which embeds an LLM.**

1. **The owner's own assistant, via MCP (§8) — the differentiated path.** The
   owner opens Claude or ChatGPT and *talks*: "fill-up Friday, 13.1 gallons at
   $5.15" — or a voice memo from the autocross paddock: "best run 2nd place,
   tried 3 degrees camber and 32 psi instead of 34, car felt more balanced."
   Their assistant transcribes, structures, and calls Vin Santo's MCP tools;
   we supply typed tools and the ledger, they supply voice and dialogue. This
   is Fuelly's SMS grammar reborn with the parser on the owner's side of the
   wire — zero entry UI of ours in the loop.
2. **A phone-first web composer — the floor.** For owners without an
   assistant wired up, and as the home of the confirm queue (§8). One tap
   from the vehicle page: a segmented composer with
   **Fill-up | Service | Mod | Note** modes.

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

Voice and free-text structuring are supplied by the owner's assistant through
the §8 MCP surface **in v1** — no hosted parser, no voice UI of ours. A hosted
parser behind the web composer's text box is a later nicety, and deferring it
is safe: notes are claims, so a parser can retroactively propose structure
from entries logged before it existed.

**Delivery: responsive LiveView, installable as a PWA.** No native app. The
entry moment is "standing at the gas pump / in the garage with greasy hands" —
mobile web must be genuinely first-class, not a shrunk bench. `GREG'S CALL` if
he disagrees that mobile-web-only clears the bar for v1.

**Caveat.** The reframe says entry friction decides whether anyone logs; the
landscape says something sharper — friction is necessary but *payoff* is what
sustains (Automatic Labs had zero friction and died anyway). So the entry UX
is only half the make-or-break; the other half is that every save visibly
improves something the owner can show off — the timeline grows, a stat
updates, the page gets richer, and the entry is one tap from their build
thread or IG (§6). And *session zero* needs designing: the
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
| `event.modification` | event | `summary` (req), `area` (opt string — suspension, engine, wheels…), `detail` (opt string), `sets` (opt — trait deltas, §2b) | `area` stays a free string in v1; an enum invites vocabulary bikeshed before we've seen real data. `sets` entries validate against the trait vocabulary. |
| `event.note` | event | `text` (req) | The escape hatch. Never conflicts, never comparison-relevant, tier-1 forever. |
| `event.outing` | event | `kind` (req — `autocross\|track\|show\|drive\|other`), `venue` (opt), `result` (opt), `summary` (opt), `sets` (opt — trait deltas, §2b) | Serious owners' logs are full of these; the autocross voice memo is the canonical compound utterance (outing + modification + note in one breath). "Tried 3 degrees camber" is a `sets` delta. |
| `state.engine`, `state.transmission`, `state.wheels_tires`, `state.suspension`, `state.brakes`, `state.exterior` | observed | `summary` (req), `code` (opt), `detail` (opt) | The current-state seed traits (§2b). Free-text-first values; exact-equality equivalence, no cross-source comparison in v1. Grow the set from real entries, per fork B discipline. |
| `observation.mileage` | observed | *(exists)* integer | Reused; fill-ups and service entries emit it alongside. |
| `event.service`, `event.sale` | event | *(exist)* | `event.service` gains nothing in v1; its `summary`+`performer` shape already fits. |

Equivalence for all new predicates is exact equality — none of them
participate in cross-source comparison in v1.

**Doesn't `event.note` gut the closed vocabulary?** No — the discipline exists
to protect *comparison and facts*: predicates whose values get compared across
sources need pinned semantics. A free-text event predicate never enters facts
(§8), never conflicts (events accumulate, §4), and never compares. The risk is
different: everything lands in `event.note` and structured data never
accumulates. Mitigations: the MCP path (§8) structures at
the source — the assistant emits typed claims, not prose; the composer
defaults to the structured modes; and structure can later be proposed
retroactively from existing notes (§8) — notes are feedstock, not a dead end.

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

**Not built.** Ticket F shipped the composer without links — the table does not
exist and Note mode takes text and photos only. Nothing in the ledger wants it,
so it moved to ticket G rather than riding along.

---

## 2b. Current state — the second projection

*Decided with Greg, 2026-08-01 round 3. The logbook works as a replayable
log: events and observations fold into "the car now," separate from the
factory record.*

**The gap it fills.** `vehicle.facts` answers "what did the factory build."
The timeline answers "what happened." Nothing answers *what is the car now* —
current mileage, current engine, current wheels after ten years of building.
For the owners §0 says we're courting (the modified car, the vintage racer —
the 1985 Datsun Z with an LS1 and 18x11s), current state *is* the page.

**Not factory-plus-perturbations.** `current_state` is a second derived map
on the vehicle, sibling to `facts`, computed **independently** of it — it
never reads factory facts. For a swapped car, factory is a thin-or-empty
column and current state is nearly the whole record; the projection can't
assume factory as a baseline. Where both columns exist, divergence
(originality vs. build story) is computed at render time — derived, never
stored, same doctrine as conflicts.

**The fold.** Recomputed inside every claim-writing transaction, same hook as
`refresh_facts/1`. Replayable by construction: drop the column, re-fold from
the ledger, identical result. Inputs, per trait predicate:

- **Observed-scope trait claims** — "as of this date, the car has X."
  `observation.mileage` is the existing proof of the pattern; the `state.*`
  seed traits (§2 table) extend it.
- **Event deltas** — the optional `sets: [{predicate, value}]` field on
  `event.modification` and `event.outing`, validated against the trait
  vocabulary. Free-text entries without `sets` stay timeline-only; the MCP
  assistant (§8) proposes deltas from the utterance ("swapped in an LS1" →
  sets `state.engine`), confirmed like everything else.

Rules: **admitted claims only** — a proposed, unconfirmed MCP entry never
mutates public state, or the §8 confirm gate stops meaning anything. Latest
scope date wins; ties to latest insertion. This deliberately inverts facts
precedence (ties to earliest): facts asks what was true at birth, current
state asks what's true now — recency winning is the semantics, not an
inconsistency.

**Cold start — the current-spec panel.** A built car's first session must not
be archaeology. The owner's page gets a spec panel: the seed traits as
editable fields, each save one observed claim through the normal
propose-and-self-ratify path (§3). Ten minutes and the fold has a full
baseline; events refine it from there. Lands in ticket F with the composer.

**Why it's load-bearing.** The fold is arithmetic in the CLAUDE.md sense —
same class as facts materialization. Wrong fold and the page lies about the
car. Main-thread work, test-first, its own ticket (M in §10).

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
  latency collapses. For agent-mediated entries (§8) the two
  steps genuinely separate: the assistant's tool call lands `:proposed`; the
  owner's confirmation — a word in the chat, a tap in the queue — *is* the
  ratification. Same machinery, same audit trail, and a model mishearing
  "13.1" as "31" never enters the record silently.
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

**What shipped (ticket E, 2026-08-03).** Steps 1–3 and 5 as written. Step 4 is
the operator queue at `/bench/claims` **without** the vision pre-check: its
output was always a proposal an operator approves, auto-approve was always a
later flip, and at a few claims a week the operator reads the photograph either
way — so the model call would buy nothing today, and TK-004 is where extraction
gets designed properly. The high-value flag came out with it: a mandatory look
is what every claim already gets. Proof photos render at `/bench` only, through
an operator-gated artifact route; serving artifact images publicly is still
blocked on a rights call.

**What ticket E settled that this section did not.**

- **The handle is chosen when the code is issued and minted when the photo
  arrives** — not at the grant. The §9.1 rule was "no party exists until there
  is something to attribute," and a proof photo is something to attribute:
  `create_upload_artifact/1` stamps a source party, and stamping Vin Santo on an
  owner's photograph would say the registry supplied it. Validating the handle
  at issue also keeps an operator from finding out at approval that the name is
  taken.
- **Expiry governs the window between the code and the photograph only.** Once
  proof is in, a slow operator cannot cost the claimant their claim. A code that
  lapses before a photo is retired and replaced.
- **A counter-claim issues a code and refuses at approval.** Refusing the second
  claimant up front leaves them nothing to escalate; refusing at approval leaves
  the claim in the queue with the incumbent intact — which is the escalation
  this section asks for. The incumbent is emailed when the claim is *made*, not
  when it is decided: they hold the evidence that settles it. Resolving the
  dispute is still ticket K's queue; today the operator revokes the incumbent by
  hand and then approves.

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

**Hierarchy (Greg, round 3): the living car leads; provenance is the
foundation, not the headline.** The page is the owner's love for the car —
what it is now, what they're doing with it. Provenance and verification are
the resale foundation underneath, quiet until needed. Render order:

- **Hero**: photos and the current-build headline composed from
  `current_state` (§2b) — "1985 Datsun 280Z · LS1 swap · 18x11" — not from
  the decode. Marque/model/year and claimed-by badge; VIN present but small.
- **The timeline — the page's center of gravity**: event/observed claims
  grouped by `entry_ref` into entries, newest first — the logbook. Registry-
  sourced events (BaT sale, dealer service invoices) and owner entries
  interleave, visually distinguished by tier and asserting party.
- **Current spec** (§2b): the trait fold, with modified-from-stock traits
  marked — the build story at a glance.
- **Photo gallery** (owner artifacts marked public), link list (§2).
- **The record** (foundation layer, below the fold or collapsed): factory/
  provenance facts with tier display — verified / unverified / conflicted
  rendered honestly, each fact expandable to its claims and evidence;
  conflicts show as conflicts, absence as a gap; copy never asserts more
  than the ledger supports. Tier composition strip ("62% of build facts
  document-backed") lives here — the sale-time pitch as a stat, not the
  page's opening move. A stock, documented car (the corpus Carrera GT) still
  shines: its record section is dense and its "current = factory" reads as
  originality — but the section order doesn't change per car.
**The distribution kit — entries travel to the audience.** The audience is
the payoff (§0 lesson 1), and the audience already exists on forums, IG, and
YouTube — so every public entry ships with one-tap distribution *outward*:

- **Share card**: a rendered image (car, entry text, headline stat, page
  link) sized for IG stories/posts — the visual unit of "look what I did to
  the car today."
- **Forum snippet**: the entry as ready-to-paste BBcode/markdown — photos,
  text, and a link back to the page — for the owner's existing build thread.
  Honest mechanics: true API crossposting only exists where forums have APIs
  (Discourse-based boards do; the legacy phpBB and vBulletin boards where most
  build threads live don't, and driving a user's forum account by automation
  is TOS-hostile — §9.3 has the per-platform table). Copy-paste-into-your-thread is the v1 mechanic; direct
  crosspost is added per-platform where an API makes it clean.
- **Embeddable badge**: small SVG with car + stat + link for forum
  signatures — Fuelly's decade-long growth loop, still cheap (one
  controller).

The direction of trade matters: entries flow *out* to platforms as the
owner's own content (rights-clean by construction); platform content flows
*in* only as pointers (§2 links). The page is the canonical record every
crosspost points back to — the build thread keeps the audience, Vin Santo
keeps the ledger.

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

## 8. The agent entry surface — MCP, and where the LLM lives

**The reframe (Greg, 2026-08-01 walk):** we don't embed an LLM; we expose an
interface for the LLMs owners already have. Voice entry is the killer entry
mode — "fill-up Friday, 13.1 gallons," the autocross voice memo — and the
voice side is entirely supplied by Claude/ChatGPT/whatever the owner talks to.
Vin Santo's job is a typed tool surface and the ledger behind it. This is the
agent-readable-business-interface bet applied to our own front door: the
registry becomes something any authorized agent can write to — which is also,
later, exactly how a shop's agent logs the service it just performed (§10
tranche 7, the credibility unlock).

**Tool surface (v1, deliberately small):**

- `my_vehicles` — the caller's stewarded vehicles (id, identity, headline).
- `log_entry(vehicle, date, claims[], note?, links[]?)` — claims validated
  strictly against the closed vocabulary (`event.fuel`, `event.modification`,
  `event.outing`, `event.service`, `observation.mileage`); anything that
  doesn't fit falls into the note residual, never rejected. Creates the
  claims `:proposed` under one `entry_ref` and returns a human-readable echo
  for the assistant to read back.
- `amend_entry(vehicle, entry_ref, claims[])` / `delete_entry(vehicle,
  entry_ref)` — correction, which replaced the confirm step (decided
  2026-08-03). Retract-and-relog under the same `entry_ref`; the withdrawn
  values stay in the ledger.
- `attach_link(vehicle, url, label?)` — link curation (§2). *Not built in
  ticket H:* it needs `vehicle_links`, which is TK-016's table.
- `get_timeline(vehicle)` — read-back, so the assistant can answer "when did
  I last change the oil?" — retrieval is half the reason to keep a log, and
  it makes the assistant a *reader* of the record, not just a scribe.

**Doctrine mapping.** Asserting party: the owner (the token is theirs).
Method: `:llm_extract`, with the calling surface in `method_meta` — the ledger
records that a model mediated. State: **admitted on arrival**. The tool call is
the owner's assertive act (Greg, 2026-08-03), so `log_entry` runs the same
propose-and-self-ratify transaction the composer does, and the §3 scope split
still applies — a factory-scope claim from an agent waits at the operator gate
like any other.

The confirm step this section originally argued for was cut. Its guarantee was
weaker than it read: nothing in the protocol makes an assistant stop and ask,
so `log_entry` followed immediately by `confirm_entry` was always available to
a badly-behaved client. What replaces it is cheaper and does more — the tool
description tells the assistant to read the entry back, which catches a
mishearing in the same breath, and `amend_entry`/`delete_entry` make anything
that slips through correctable for as long as the car exists.

**Auth:** a per-user token minted in account settings, scoped to the user's
stewardships *read at call time* — so a revoked stewardship stops a live token
mid-flight, not at the next mint. Revocable, shown once, last-used stamped.
No OAuth in v1: the spec makes authorization OPTIONAL, and a static bearer
token is a deliberate deviation from its SHOULD. The 401 still carries
`WWW-Authenticate` so a client is told what to present.

**Transport (settled in ticket H):** hand-rolled, `SantoApiWeb.MCP.Plug`, no
new dependency. `POST /mcp` returns `application/json`; `GET /mcp` returns 405,
declining to open an SSE stream, which the spec explicitly permits and which
costs nothing because every tool here answers off a Postgres query. Stateless:
MCP 2026-07-28 removed sessions and the initialize handshake outright, and
`Mcp-Session-Id` was only ever a server MAY before that, so storing nothing is
correct for both that revision and the 2025-06-18 clients shipping today.
Tidewave, vendored in this project's own `deps/`, serves MCP from Phoenix in
exactly these two routes.

**Corrections as signal (revrec lesson, unchanged):** when an owner edits a
proposed entry before confirming, the delta is captured in `method_meta` —
that's the corpus for improving tool descriptions later, and deterministic
post-parse fixes beat prompt tinkering.

**What this displaces:** the previous plan's hosted free-text parser behind
the web composer. It's now a later nicety, not a tranche — the high-intent
users get structuring through their assistant on day one, and because notes
are claims, a hosted parser can still retroactively upgrade old entries
whenever it ships.

**Caveat.** Setup friction is real: connecting an MCP server to a consumer
assistant is a settings dance today, and the population comfortable with it —
though it overlaps suspiciously well with people who log camber changes — is a
minority of even serious owners. The composer floor (§1) exists for everyone
else, and the entry-mix metric (share of entries arriving via MCP vs composer,
reviewed at 30 days) tells us where to invest next. The bet is that
assistant-side MCP support gets easier every quarter and we're early to a
surface everyone else will retrofit.

---

## 9. Supporting infrastructure — the price of the first non-operator surface

§11's original ordering deferred owners precisely because of this bill. Here
it is, itemized, so the walk approves the real scope and not the romantic
subset. Much of it is boring generator output and configuration; the
genuinely new machines are the operator queues, object storage, and the
integration seams.

### 9.1 Accounts, beyond login

§5 settles credentials (magic link) and the User↔Party split. The rest of an
account:

- **Handle.** The public identity — "maintained by @handle" on the page,
  attribution on every entry. Recommendation: **party name = the handle,
  chosen at the first assertive act, immutable thereafter**; a separate
  mutable display name is presentation-only. The immutability isn't
  aesthetics: the party name is baked into every claim's `content_hash`, so a
  renamed party would orphan its own history's hashes. Pseudonymous handles
  are also the privacy posture (below). `GREG'S CALL` — immutable handles are
  a real UX constraint and users will ask.
- **MCP tokens.** Mint/revoke in account settings (§8): scoped to the user's
  stewardships, shown once, revocable individually. Token last-used display
  so a leaked token is noticeable.
- **Notifications: email-only in v1.** Magic links, claiming decision,
  counter-claim alert (§4 — time-sensitive, the one that must not be missed),
  pending-entry nudge ("your assistant logged 2 entries — confirm"). Swoosh
  ships with Phoenix; no web push, no digest engine in v1.
- **Account deletion, stated honestly.** Credentials and profile delete;
  **the party and its claims persist** — the ledger is append-only and
  attribution is historical fact, the same reason a superseded claim stays
  visible. Deletion flow offers bulk-set-entries-private first, then
  disassociates the user from the party. Pseudonymous handles make this
  defensible; the ToS says it plainly. `GREG'S CALL` — this is the
  ledger-integrity vs right-to-erasure line, and it should be his sentence.

### 9.2 Operator admin — the other side of every flow

Every owner flow in this doc has an operator end, and it lands in /bench —
one app, behind the §5 operator flag, not a second surface. /bench grows from
a per-vehicle workbench into workbench + queues:

- **Claiming queue** (§4): proof photo, vision pre-check verdict, vehicle
  context, approve/deny. High-value flags surface here.
- **Ratification queue**: owner-proposed factory/provenance claims waiting on
  the gate (§3) — the operator half of the scope split.
- **Dispute queue**: counter-claims on stewarded vehicles (§4); resolution
  uses the existing adjudication machinery, never a side door.
- **Report queue**: the public page gets a report affordance (abuse, doxxing,
  fraud); reports land here. Remedy is a visibility flip plus a note — the
  ledger is never edited, even for moderation.
- **User admin**: suspend account, revoke stewardship — both status flips
  with reasons, nothing deleted.
- **Metrics strip**: active stewards, entry mix (MCP vs composer — the §8
  30-day check), confirm rates, claims/day. Read-only, computed, no new
  tables.

Doctrine: admin actions that touch the ledger go through `ratify_claim` /
`adjudicate_claims` / status flips exclusively. The admin UI is a caller of
the same machinery the corpus scripts use.

### 9.3 Platform integrations — per-platform honesty

The principle from §6, restated as the integration contract: **outbound
carries the owner's own content; inbound stores pointers and official-embed
metadata only.** No scraping, no credential puppeteering, anywhere.

| Platform | Inbound (on the page) | Outbound (distribution) | v1? |
|---|---|---|---|
| YouTube | Link → oEmbed (open endpoint, no key): title, author, thumbnail; iframe embed on the page | Nothing needed — owners post there natively, link back | **Yes** |
| Instagram | Link → bare link card in v1. IG oEmbed requires a Meta developer app + "oEmbed Read" review — do that dance later if embed-rich pages earn it | Share card image via the phone share sheet (§6). No API posting: IG's Content Publishing API covers business/creator accounts only | **Yes (bare)** |
| phpBB / vBulletin forums (Rennlist et al.) | Thread URL stored per vehicle (§2 links) | **Snippet copy-paste is the integration** — no official REST API exists for either. "Post to my thread" = open thread URL + snippet on clipboard, one paste. Store the thread URL once so every entry knows where it goes | **Yes** |
| Discourse forums | Link + oEmbed/onebox both directions work naturally | Real REST API with per-user API keys — the one platform where true one-tap crosspost is clean. Add when a target community warrants | Later |

We store URLs and oEmbed metadata (title/author/thumbnail URL), never media
files from platforms. Owner-uploaded photos are the only media we host.

### 9.4 Platform plumbing

- **Transactional email** — launch blocker; magic links depend on it. Swoosh
  (in-box) + one adapter (Postmark or SES — pick at build time, it's config).
- **Object storage.** Uploads move from local `uploads_dir` to S3-compatible
  storage (Tigris on Fly). The existing convention — `storage_ref` is
  basename-only — was designed for exactly this: the move is configuration
  and a file sync, not a migration. Claiming photos and owner documents are
  user data; local disk stops being acceptable the day the first real owner
  uploads.
- **Image pipeline.** Share cards render from an SVG template, rasterized
  server-side (vips) because IG wants pixels; gallery thumbnails likewise.
  No general image service — two named transforms.
- **Rate limiting.** Unauthenticated lookup (§7), auth endpoints, MCP calls.
  Plug-level ETS bucket, hand-rolled or `hammer` — minimal-deps rule applies.
- **Legal pages.** ToS + privacy policy — first personal data in the system.
  The deletion posture (9.1) and moderation remedy (9.2) get written down
  there, in the same plain register as the product copy: the ledger keeps
  history; here's exactly what that means for you.
- **Backups.** Postgres is covered Fly-side; the artifact store gets
  versioning/replication turned on — owner documents are the one thing we
  cannot re-acquire.

## 10. Roadmap amendment and ticket decomposition

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
>    `event.modification`, `event.note`, `event.outing`, `state.*` traits) ·
>    **`current_state` projection** (the logbook as a replayable log folding
>    into "the car now"; page leads with the living car, provenance as
>    foundation) · phone-first
>    composer · **MCP agent entry surface** (voice via the owner's own LLM;
>    proposed-until-confirmed) · scope-split self-ratification ·
>    distribution kit (share card, forum snippet, badge) · privacy controls
>    + export · operator queues (claiming, ratification, disputes, reports)
>    · platform plumbing (email, object storage, rate limits, ToS/privacy).
> 4. **Document extraction** (TK-004) — the corpus friction log's stances;
>    now also fed by owner-uploaded receipts accumulating from tranche 3.
> 5. **Dossier rendering** — the sale-time output: facts, tier composition,
>    timeline, citations, owner-controlled full disclosure.
> 6. **More providers** — NMVTIS/auction-history/VIO per the public-data
>    census (docs/research/); club partnership pilots; PPS as async order.
> 7. **Shop-authored entries** (seam, unscheduled) — the landscape's
>    credibility unlock: the party doing the work writes the claim
>    (CARFAX's shop feed, GlobalWorkshop's pushed restoration reports).
>    Shops are already `parties`; a shop-scoped entry path turns tier-1
>    logbooks into third-party-attributed ones without any new ledger
>    machinery. The MCP surface (tranche 3) is the same door — a shop's
>    agent calling `log_entry` with the shop's party is the whole
>    integration.

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
| C | Logbook vocabulary: `event.fuel`, `event.modification`, `event.note`, `event.outing`, `state.*` seed traits, `sets` deltas + validators + tests | — | Small, test-first. |
| M | `current_state` fold (§2b): derived map, transaction-hook refresh, admitted-only latest-wins fold, replay test (drop + re-fold = identical) | B, C | Load-bearing (arithmetic, same class as facts) — main-thread work, not delegated. |
| D | Public vehicle page: `/v/:public_id`, VIN resolver, §6 hierarchy (hero from `current_state`, timeline-centered, record as foundation layer), lookup + create-on-first-lookup, rate limit | B, M | Read-only; ships before claiming exists (unclaimed pages are the bait). |
| E | Claiming: challenge codes, proof upload, vision pre-check, /bench approval queue, stewardships | A, B | |
| F | Entry composer: four modes, photos, links table, scope-split self-ratification path, current-spec panel (§2b cold start) | A, B, C, M | The make-or-break ticket; §1 is its spec. |
| G | Privacy controls + owner's own-view + full-record export | F | |
| H | MCP agent entry surface: token auth, tool set (`my_vehicles`, `log_entry`, `confirm_entry`, `attach_link`, `get_timeline`), proposed-until-confirmed path, pending queue in composer | A, B, C | §8's contract. v1 core, not fast-follow — the differentiated entry path. |
| I | Distribution kit: share card, forum snippet (BBcode/markdown), embeddable badge, per-vehicle thread URL + "post to my thread" flow | D, F | Entries travel to existing audiences; page is the canonical record. Needs J's image pipeline. |
| J | Platform plumbing: transactional email, S3-compatible artifact storage, image pipeline (share cards, thumbnails), rate limiting, ToS/privacy pages | — | Launch blocker; parallelizes with A–D. Email before A ships (magic links), storage before E ships (proof photos). |
| K | Operator admin: claiming/ratification/dispute/report queues in /bench, user suspend + stewardship revoke, metrics strip | A, E | Greg's daily surface; §9.2 is its spec. |
| L | Embeds: YouTube oEmbed + iframe, IG bare-link cards, oEmbed metadata storage; Discourse crosspost when a target community warrants | D, F | Phased per the §9.3 honesty table. |

**Build order (Greg, round 3): infra first.** J, A, B open the build — no
design dependencies, and they gate everything downstream (email gates A's
magic links, storage gates E's proof photos, B is the ledger seam every
other ticket touches). C and M follow immediately; then D ships value
(public pages, lookup) before any auth-gated surface exists — layered
commits, each green. A→E→F/H remains the critical path to the first owner
entry. F and H land together conceptually — the composer's pending queue is
where unconfirmed MCP entries surface — but commit separately. K, I, L trail
the critical path and can land incrementally after first owners exist. The
§9.1 walk decisions (handles, deletion posture) get taken as they block A/B,
not deferred to a second walk.

### Decided 2026-08-01, round 3 (Greg)

- Build starts with infra: J, A, B first.
- `current_state` as a second projection (§2b), independent of
  `vehicle.facts` — factory record untouched; usable by swapped/raced cars
  where factory is thin and current state is the record.
- Trait vocabulary: seed set + grow (six `state.*` predicates,
  free-text-first values).
- Page hierarchy: the living car leads — hero from `current_state`,
  timeline-centered; provenance/tier display is the foundation layer, not
  the headline (§6).
- §3 scope-split self-ratification: **ratified.** Owners self-ratify
  event/observed claims on stewarded cars; factory/provenance stays at the
  operator gate. `evidence_contract.md` gets the amended invariant wording
  when ticket B lands.
- §2 `entry_ref` in the event-claim content hash: **ratified.** Occurrence
  identity is entry identity for events; corpus re-run green is the
  acceptance test.

### Decided 2026-08-02 (Greg, during ticket F)

- §6 privacy default: **everything public.** Entries *and* uploaded photos
  default `visibility: :public`, with one toggle per entry covering both. The
  middle line this doc floated — entries public, documents private — was
  rejected as a rule to explain for a distinction the composer would have had
  to make the owner draw. The TK-008 migration had already defaulted both
  columns to public, so nothing migrated.
- §9.1 handles: **immutable, and chosen at the stewardship grant.** The party
  name joins every claim's `content_hash`, so `ensure_party/2` refuses a rename
  outright rather than ignoring the argument. Taking the handle at the grant
  means no party exists until there is something to attribute — no placeholder
  ever gets hashed. Case and surrounding space normalize once, on the way in,
  because the normalized form is what becomes permanent.

### Decided 2026-08-03, during ticket E

- §4 step 4: **no vision pre-check in v1**, and no value/notability threshold —
  every claim gets a person, which is what the threshold was for. The model's
  read becomes a proposal on the queue screen when volume argues for it.
- §9.1 handles, refined: **chosen at issue, minted at proof.** The grant is no
  longer the first thing there is to attribute; the possession photograph is.
- §6 the owner's own view: a private entry is visible to the steward of the car
  and marked *not on the public page*. `Registry.timeline/2` takes the option
  and `Owners.timeline/2` decides who may pass it — the ledger reads, the owner
  context authorizes. This was the hole ticket F opened and it is closed; the
  rest of ticket G (flipping visibility after the fact, links, export) is not.

### Decided 2026-08-03, during ticket H

- §8 confirm semantics: **no confirm step.** The tool call is the owner's
  assertive act, and `log_entry` proposes and self-ratifies in one transaction
  exactly as the composer does. This doc's recommendation (keep the confirm)
  was rejected on the ground that entry friction is what kills a logbook, and
  §0's landscape survey is a list of products that died of it. `confirm_entry`,
  `discard_entry`, and the composer's pending queue are all struck from the
  ticket; the assistant is instead told to read the entry back, which catches a
  mishearing while the owner is still talking and costs no round trip.
- §8 correction, the safety property that replaces it: **anything an owner put
  in, they can change later.** The line is the **asserting party, not the scope
  kind** — an owner-typed `build.paint_code` is as editable as a fill-up,
  because they typed it. Claims from santo, vPIC, Classiche, or any provider
  are not editable by an owner at all; a conflict there produces both sources.
  The VIN is not a claim and cannot change: a different VIN is a different car.
- Editing and ratification are **orthogonal**. This decides who may revise an
  assertion; §3's scope split still decides when one enters the record. A
  corrected factory claim is still proposed and still waits at the operator
  gate.
- The mechanism is retract-and-relog under the same `entry_ref`, not
  adjudication (`evidence_contract.md` §3 carries the amended wording).
  Greg: "We shouldn't do this adjudication nonsense... I don't know anything
  the user is actually entering themselves. They should be able to edit as they
  see fit." Owner-side only — the operator adjudication machinery TK-003 built
  is untouched.
- Edge cases in the fold — a corrected observation re-entering `current_state`
  with a fresh insertion order — are **deferred**: "we should just assume
  generally that whatever the owner puts in is right."
- §8 transport: **hand-rolled**, one Plug, no new dependency. MCP 2026-07-28
  deleted sessions and the initialize handshake, so the state management a
  library would have absorbed is the state the protocol just removed; Tidewave
  (vendored in this project's `deps/`) serves MCP from Phoenix the same way.
  Bearer token, no OAuth in v1 — authorization is OPTIONAL in the spec and
  §8 already deferred OAuth to "when a real client demands it."

### Decisions still queued for the walk, in order

5. §9.1 — the deletion posture: credentials delete, party + claims persist.
   The ledger-integrity vs right-to-erasure line, in Greg's words. Not yet
   blocking: nothing deletes an account today.
6. §1 — mobile-web-only v1 (no native app).
7. §10 — the §11 rewrite text and ticket cut A–L.
