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
provenance is the foundation layer, not the headline (§6).
Round 4 (2026-08-04): origination added as §7b — the front door for an owner
whose car is in no registry at all, which every section above had assumed away.
Brings a fourth identity kind (`:asserted`), the project's first hosted LLM
call, and a handle prompt at registration. §1 amended (the parser deferral is
now cheaper to reverse), §7 amended (two creation paths, one box), §6b opened
(comments and likes).
Round 5 (2026-08-04): reviewed against the build-thread use case. A build
thread is story + plan + photos + replies, and the ledger had formalized only
the events — §6c opens the narrative layer (story block, `event.plan`,
photos-after-setup). §6b's doctrine calls taken (owners don't moderate, no
promote-to-claim in v1, likes cosmetic, comments after distribution). Handle
timing unified at registration (§9.1). §10 brought current with the decisions
that had superseded its text, shipped statuses recorded, tickets N and O cut
(TK-024, TK-025).*

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
   assistant wired up. (It was also to be the home of §8's confirm queue,
   until the confirm step was struck — ticket H decisions.) One tap
   from the vehicle page: a segmented composer with
   **Fill-up | Service | Mod | Plan | Note** modes (Plan added round 5 — §6c;
   lands with ticket O).

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
- *Plan*: text + photos. Produces `event.plan` (§6c) — dated intent, rendered
  as *planned* on the timeline. "These are the wheels I'm looking at" is an
  entry, recorded the day it was thought.
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

**Amendment, 2026-08-04 (§7b changes the arithmetic here).** This section
deferred a hosted free-text parser on the reasoning that the high-intent users
get structuring through their own assistant and we'd be building a parser from
nothing. §7b builds one anyway — origination needs extraction to turn "2024
Lexus GX 550 in green, 35,000 miles" into claims. So the marginal cost of a
text-or-voice box inside the composer drops from *a new subsystem* to *a second
caller of an endpoint that already exists*, and the deferral should be re-argued
on its merits rather than inherited.

Greg's framing of the open question (2026-08-04): "If they do a fill-up they go
to the app and do what exactly? I assume it's click a button and start talking."
That is a different entry model from the segmented composer above — mic-first
rather than form-first — and §1's own analysis cuts against it for exactly the
fill-up case: fuel is three numbers, and a structured form is *faster* than
speaking a sentence. The interesting version is not "voice instead of the
composer" but voice as the **Note and Service** path, where the text is the
value and there is no form to be faster than. Undesigned, and it needs its own
pass. `GREG'S CALL` before any of it gets built.

---

## 2. Vocabulary growth

The closed vocabulary (`registry/vocabulary.ex`) gains predicates test-first,
one code-reviewed change each, per fork B discipline. The logbook demands:

| Predicate | Scope | Value shape (jsonb) | Notes |
|---|---|---|---|
| `event.fuel` | event | `volume` (req, decimal-as-string), `unit` (req, `"gal"\|"l"`), `total_cents` (opt int), `currency` (opt), `grade` (opt), `station` (opt), `partial` (opt bool) | Money in integer cents, never floats. Cost/mile is computed, never stored. |
| `event.modification` | event | `summary` (req), `area` (opt string — suspension, engine, wheels…), `detail` (opt string), `sets` (opt — trait deltas, §2b) | `area` stays a free string in v1; an enum invites vocabulary bikeshed before we've seen real data. `sets` entries validate against the trait vocabulary. |
| `event.note` | event | `text` (opt as of round 5 — was req) | The escape hatch. Never conflicts, never comparison-relevant, tier-1 forever. Text went optional for the photo-first entry (§6c); composition, not the vocabulary validator, enforces that an entry carries text or a photo. |
| `event.plan` | event | `text` (req), `area` (opt string) | Aspirational — dated intent, not occurrence (§6c). Renders as *planned* on the timeline; never conflicts, never enters `facts` or `current_state`, tier-1 forever. The completion link (a later entry pointing at the plan it fulfilled) is a named seam, not v1. |
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
so it moved to ticket G rather than riding along — and then moved again in
round 5: §7b makes links the last step of onboarding (screen 5), so the table
lands with the origination ticket (N, TK-024) rather than trailing on
privacy and export.

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
  taken. *Superseded, round 5: the handle is chosen at registration for every
  account (§9.1); the claim flow reads the user's reserved handle rather than
  asking. Minting stays where ticket E put it — at the proof photo, the first
  thing there is to attribute.*
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
- **Story** (§6c, round 5): the owner's own words about the car, when they've
  written any — a paragraph, not a form. Curation, not a claim; absent
  silently otherwise.
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

**First distribution slice shipped 2026-08-10 (TK-018).** Every public update
permalink now exposes one coherent kit:

- a server-rendered 1080×1350 JPEG card, using the update's first-party lead
  photo when present and a typographic asphalt field otherwise;
- ready-to-copy Markdown and BBCode containing the owner text, details, photo,
  and canonical update URL;
- a 560×120 SVG car badge plus HTML and BBCode embed copy;
- one optional `vehicle_links.kind = :build_thread` destination. “Copy and open
  thread” copies BBCode and opens that owner-supplied URL; Vin Santo never holds
  forum credentials or pretends a legacy forum has a posting API.

The share card and badge are the two named image transforms promised in §9.4.
They are public only when the car and update are public. Distribution produces
no ledger writes and imports no platform content.

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

## 6b. Response — comments and likes

*Opened 2026-08-04 (Greg): "Things we'll need to think about in the future are
comments and likes on the log or on the public page." Stated, not designed —
the point of writing it down now is that the doctrinal edge is easy to get
wrong later. Round 5, same day: the doctrine calls below were taken; the
surface itself stays undesigned and sequenced behind the distribution kit.*

**The reason this matters more here than on a normal social product.** §0's
finding is that build threads are the highest-credibility self-reported logs in
existence, and part of why is that they are *publicly witnessed* — replies are
contemporaneous, attributed, and impossible to backdate. The Rennlist GT2 thread
is half owner narration and half community correction: *"is it safe to assume
the buckets are original to the car?"*, answered by *"no Pentosin/chf11s in a
GT2 except for the steering."* The comments are where the owner's gaps get
filled by people who know the marque. That is not decoration around the record;
for a thin car it may be the densest evidence on the page.

**The line to hold: a comment is not a claim.** Claims are assertions about the
car, they carry scope and predicate and party, and they join a `content_hash`.
A comment is discourse *about the record* — its own table, outside the ledger,
never folded into `facts` or `current_state`, never a timeline tick.

**The seam that makes it interesting.** A comment that corrects a fact wants to
become a proposed claim. "That's not the original gearbox, the casting number is
wrong" is exactly the material §3 exists for, arriving in the one form the
vocabulary can't take. Whether there is a promote-to-claim path — owner-invoked,
operator-invoked, or neither — is the real question in this section, and it
should be decided before comments ship rather than retrofitted.

**Decided 2026-08-04, round 5 — the doctrine calls, taken ahead of the design
pass:**

- **Owners do not moderate their own comments.** The §0 credibility argument
  rests on build threads being *publicly witnessed* — on a forum the OP cannot
  delete skeptical replies, and that is precisely what makes the thread
  evidence. If the owner can purge criticism, the witness value dies.
  Report-to-operator (§9.2's queue, extended to speech) is the only removal
  path. This is the kind of power that is painful to take away later, which is
  why it's decided before a single comment exists.
- **No promote-to-claim in v1.** The informal path already exists — an
  operator can propose a claim citing a comment, the same way the bench
  proposes claims off invoices. Build the formal path when a real correction
  arrives in comment form, not before.
- **Likes are cosmetic.** Retention signal only; never an input to tier or
  verification. §0's Strava numbers argue the social loop drives logging
  frequency; nothing argues a like should influence what the record asserts.
- **Handles, not anonymity.** A witnessed record needs attributed witnesses;
  §9.1's registration-time handle (round 5 unification) covers every commenter.
- **Comments land after the distribution kit (ticket I).** Comments pay off
  only where an audience exists, and the audience arrives by crossposting
  out. Response mechanics before distribution is a stage before there's
  anyone in the seats.

**Still open for the design pass:** notification and email volume (where
§9.4's transactional bill stops being one magic link per session), the report
queue's remedy for speech (§9.2 was written for claims), and the abuse posture
for the first user-to-user content in the product.

---

## 6c. The narrative layer — story, plans, photos

*Opened 2026-08-04, round 5; first complete slice shipped 2026-08-10. The
review's finding: a build thread is story +
plan + photos + replies, and the ledger had formalized only the events.
Rennlist 1451795 opens with prose — "Last week I found a slightly neglected
996 GT2 Clubsport in Germany" — and §7b stores that sentence as an artifact
without ever rendering it as what it is: the opening post. Replies are §6b;
this section is the other three. Ticket O (TK-025).*

**The story block — curation, not a claim.** An owner-authored text about the
car, rendered near the hero (§6 order). Mutable, presentation layer, no ledger
contact — the same class as `vehicle_links` — because owners rewrite their
story as the build unfolds, and forcing retract-and-relog on prose turns
editing a paragraph into a ledger event. The bar is deliberately low: sometimes
what's special about the car is just *it's mine, it's my baby, I want to
handle it* (Greg, round 5) — one sentence clears it, and the block is
optional. The empty-state prompt ("what's the story with this car?") shows
only on the owner's own view; the public page renders nothing rather than a
nudge.

**Plans — dated intent, not a checklist.** Greg's framing: *"almost like a
blog post — I'm thinking about doing this. Let me record this on Monday and I
can review it. These are the wheels I'm looking at now."* That is a dated
entry, not a mutable todo list — the recording of intent is itself an event
that happened on that day, which is exactly what the append-only ledger is
shaped for and exactly how a forum thread carries a plan: the plan changes by
posting again, and the old post stays. So plans are `event.plan` claims (§2
table), entered through the composer's Plan mode or `log_entry`, rendered as
*planned* on the timeline.

Two boundaries, both answering the forum-nervousness Greg named:

- **Plans are the owner talking to their own record, not a discussion
  starter.** No threading, no replies-to-plans — every response mechanic
  lives in §6b, and §6b is sequenced after distribution. Nothing here builds
  toward hosting a forum.
- **A plan asserts intent, never history.** It never enters `facts` or
  `current_state`, never conflicts, tier-1 forever. When the coilovers
  actually go on, that's an `event.modification` like any other; the
  completion link back to the plan it fulfilled is a named seam, not v1.

On a page with no history yet — the freshly originated car — the newest plan
entry doubles as the "what's coming" line under the hero. For a car we know
nothing about, the plan is the only interesting thing the page *can* show on
day one, and it's the reason an audience subscribes to a thread: to watch the
plan get executed.

**Photos — after setup, not during it.** Decided round 5: no photo screen in
the §7b origination flow. Adding photos is a post-setup act, and the paths
already exist or ride existing machinery:

- **Composer entries** — every mode accepts photos (ticket F, shipped).
- **The photo-first entry** — snap now, caption never: `event.note` text goes
  optional, and composition (`compose_entry`), not the vocabulary validator,
  enforces that an entry carries text or a photo.
- **External galleries and platforms** — a Flickr/Google Photos gallery, an
  Instagram profile, a YouTube channel are all `vehicle_links` rows (§2),
  rendered per the §9.3 honesty table. Pointers in, media never harvested.
- **The nudge** — the hero's empty state on the owner's own view says "add a
  photo" and lands in the composer. A photoless page can't be shared, and the
  nudge lives on the page, not in the onboarding flow.

**Implemented shape, 2026-08-10.** The immutable artifact owns retained bytes
and generated derivative metadata. A separate mutable `vehicle_photos`
placement owns entry membership, alt text, gallery order, hero selection, and
visibility. Composition accepts zero claims only when a photo is present, so a
photo-first post does not mint an empty note to satisfy the ledger. Public
delivery exposes metadata-stripped responsive derivatives, never the original;
private placements are available only to the steward through the existing
optional-auth browser session. Event attachments reuse the same car-update
photo and its derivatives.

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

**Amended 2026-08-04:** create-on-first-lookup is now one of *two* creation
paths, and they share a single input. See §7b — the box accepts a VIN or a
sentence, and which kind of car gets created is an outcome of what was typed
rather than a mode the visitor had to choose.

---

## 7b. Origination — the front door

**The gap this closes.** Every section above assumes the car already exists:
§4 claims a row, §3 writes against it, §6 renders it, §7 creates it from a VIN.
That is the **claiming** model, and it is the wrong shape for the first-run
case. An owner arriving with a car nobody has ever recorded is not claiming
anything from anyone — they are the origin of the record. The 2026-08-04 walk
used Greg's own daily driver as the probe (2024 Lexus GX 550, green, 35,000
miles, no VIN typed), deliberately choosing a car with no PTS code, no
Classiche, no auction history and no collector corpus behind it: if onboarding
only feels good for a 993 with provenance, it fails for everyone else.

Two hard stops, both found in code rather than reasoned about:

- **There is no such thing as a car without an identity.**
  `vehicles.identity_kind` is `Ecto.Enum, values: [:vin, :chassis, :disputed]`
  (`registry/vehicle.ex:26`), and `register_chassis/3` is atom-gated to
  `:ferrari` and `:porsche` (`registry.ex:57`). A VIN-less Lexus has no door.
- **The car's own name would sit unratified.** "2024 Lexus GX 550 in green,
  35,000 miles" maps cleanly onto the closed vocabulary — `identity.marque`,
  `identity.model`, `identity.model_year`, `state.exterior`,
  `observation.mileage` — but the first three are **factory** scope, so §3
  holds them at the operator gate. The page would render its own name as
  unverified, waiting for an operator to confirm that the owner knows what they
  drive.

### 7b.1 Decisions

**1. A fourth identity kind: `:asserted`.** Keyed on a minted opaque id
(`asserted:<id>`), alongside `:vin`, `:chassis`, `:disputed`. The car is a real
vehicle row from minute one and logs entries like any other. `Registry.ingest/1`
stays VIN-shaped — `Santo.Identity.key/1` never returns `:asserted`, so
origination is a separate entry point rather than a branch inside ingest.

Rejected: *VIN required at creation* (doctrine-clean, but the VIN is exactly
what an owner doesn't have in their pocket) and *a draft object outside the
registry* (entries logged against a draft are either not claims — a second
store of truth — or claims pointing at a non-vehicle; the lifecycle cost lands
on every read path).

**2. Owner identity claims self-ratify on an `:asserted` car.** A deliberate,
scoped deviation from §3. The scope split was written for *contested* factory
facts; self-declared identity on an originated car has no counterparty and no
decode to disagree with, and a vehicle whose own name is `:proposed` has no
name.

The shortcut costs nothing because **resolution audits it automatically**: when
the VIN lands, santo's decode arrives `:admitted` and `claim_comparison/1`
either agrees with what the owner typed or surfaces the disagreement with both
sources shown. Say "GX 460" when the VIN says GX 550 and the page shows both.
The existing machinery is the check on the shortcut, which is why the shortcut
is affordable. §3's gate still governs every other factory claim and every
claim on a `:vin` car.

**3. One box, and the identity kind is an outcome.** The §7 lookup box and the
add-your-car box are the same component. A VIN — pasted bare or embedded in a
sentence — originates a `:vin` car and fires decode. A sentence without one
originates an `:asserted` car. Nobody has to know which door they walked
through.

**4. Extraction, not a form.** The box takes free text and an LLM extracts the
claims, with an inline read-back the owner can edit line by line. This is the
project's first hosted LLM call: `method: :llm_extract`, **the typed sentence
stored as the artifact**, so a better extractor can re-run against the same
bytes later. Doctrine holds — the LLM extracts, the ledger computes. Parse
failure renders the same screen with empty lines; there is no separate error
state and no dead end.

Rationale over a plain form: this is the utterance a build thread actually
opens with (*"Last week I found a slightly neglected 996 GT2 Clubsport in
Germany with some track history"* — Rennlist 1451795), and the read-back is a
cheaper confirm than the one ticket H cut from MCP, because here it is already
the screen.

**5. Persistence splits by path, on principle.** A VIN lookup persists
immediately, as §7 always said — its decoded facts are real and exist
independent of who typed them. A sentence persists only once there is an
account behind it, because its entire content is one unidentified person's
word. Same box, different rule, and the asymmetry is principled rather than
arbitrary. It also disposes of the junk-row problem: no account, no row.

**6. The user exists before the email is sent, so there is nothing to hold.**
`build_email_token/2` takes a `%User{}` (`accounts/user_token.ex:90`) —
phx.gen.auth writes the account before it sends anything. So submit creates the
user, the party, the car, the claims and the stewardship in one transaction, and
the owner lands on a real page immediately. **The magic-link click publishes
rather than unlocks.** Public rendering gates on `user.confirmed_at` through the
stewardship join — one join, zero ledger writes, and no `visibility` flipping on
claims after the fact.

This turns the worst moment in the flow into its best call to action: *your page
is live — confirm your email to make it public.*

**7. The handle is chosen at registration, and the screen says it's permanent.**
§4's refinement (chosen at issue, minted at proof) has no analogue here —
origination has neither event, and the party name joins every `content_hash`, so
the party must exist before the first claim, which is the same instant the car
does. We therefore ask a permanent, public, immutable question of someone who
has been in the product ninety seconds, and the design response is to say so in
the field's help text rather than bury it.

Rejected: a provisional handle (claims would need rehashing) and a system party
re-attributed later (already filed as an unsolved problem for corpus claims —
doing it deliberately on day one is worse). An abandoned registration burns a
handle permanently; every username system eats this.

*Round 5 generalized this: the handle is chosen at registration for **every**
account, not just originators — §9.1 carries the unified rule, and §4's
chosen-at-issue step goes away. What began as origination's special case turned
out to be the better universal.*

**8. Links are curation, not evidence — for now.** Held from §2, and made
visible in the UI: links sit in their own section, not on the timeline spine,
and carry no date of their own. Per-platform honesty from §9.3 renders
literally — YouTube gets a real oEmbed card (open, keyless), Instagram gets a
bare URL card (its oEmbed needs a Meta app and review we haven't done). The UI
does not pretend to a richness we lack the rights to.

Placement: linking is the **last step of onboarding**, not a feature to
discover later on the page. §0's landscape is unambiguous that nobody logs into
a void — Wheelwell died fighting forums for an audience, build threads run a
decade because replies keep coming — so the audience mechanism belongs in the
first session, after there is something worth pointing at.

The `vehicle_links` table this screen requires comes forward from ticket G
into this ticket (round 5) — screen 5 was pointing at a table that a
downstream ticket owned, which was a dependency inversion waiting to bite.

### 7b.2 Resolution — one-way, one-time, never refused

Adding a VIN to an `:asserted` car is **acquiring** an identity, not changing
one. That is why it does not violate ticket H's rule that a different VIN is a
different car: that rule governs *correction*, and there is nothing to correct
on a car that never had one. Once resolved, the VIN is locked; a bad resolution
is an operator problem, not a self-serve edit.

- **VIN unoccupied** — flip in place. `identity_kind` `:asserted` → `:vin`,
  `identity_key` rewritten, decode fires and its facts arrive `:admitted`,
  `claim_comparison/1` audits what the owner asserted. `public_id` never moves,
  because it was minted independent of the VIN for exactly this reason
  (`registry/vehicle.ex:23`). The log is untouched.
- **VIN occupied** — **the assertion is still recorded.** Greg, 2026-08-04:
  *"I don't think we should stop anyone from claiming.. even if there's a
  conflict."* This corrected an earlier recommendation in the walk to refuse the
  resolution, which would have been the only submission-time gate in an
  architecture that gates nothing anywhere else — the ledger records assertions
  and derives conflicts at read time, everywhere, and this is not the place to
  break that.

  `unique_index(:vehicles, [:identity_key])` (migration `20260730180000:25`)
  means both rows cannot hold the same key, so what is deferred is **the key
  flip, not the claim.** The owner becomes a claimant on the occupied row
  through §4's existing counter-claim path, an operator adjudicates, and the
  entries stay on the asserted row meanwhile. The copy says what happened —
  *we've recorded that you say this is your car* — rather than saying no.

**The bill, stated so it isn't a surprise.** When the claimant wins that
adjudication, the outcome has to move their entries onto the VIN row. That is an
**absorb write path in the ledger's blast radius**, and it does not exist. It is
deferred until the collision actually fires — but it is now owed, and it is a
ticket rather than a rendering change.

### 7b.3 The flow

Seven screens, drawn in the `vs-*` system and walked with Greg on 2026-08-04.
The visual walkthrough is the canonical reference for layout and copy.

1. **The box** — one field, VIN or sentence. The placeholder *is* the grammar,
   the way Fuelly's SMS string was. Nothing persisted.
2. **The read-back** — "we read: 2024 · Lexus · GX 550 · green · 35,000 mi",
   each line editable in place. The sentence stays on screen because it is about
   to become the artifact.
3. **Registration** — email and handle on one screen, permanence stated in the
   help text. Submit creates everything and sends the link.
4. **The page, minute one** — a named car, a colour, a dated odometer, and one
   timeline tick: *grolsen started this record*. The origination is itself an
   entry, which is the build thread's opening post.
5. **Links** — YouTube card, Instagram bare link, skippable.
6. **Day two** — the same page with a fill-up and a mod, price-per-gallon
   computed rather than typed.
7. **The collision** — the one screen where a resolution meets an occupied VIN.

Photos are deliberately not a screen in this flow (round 5): adding them is a
post-setup act — the hero's empty state on the owner's own view carries the
nudge, and the paths are §6c's. The flow asks for a sentence, an email, and a
handle; everything else is the page's job to invite.

**A note on the signal colours.** The `vs-*` system rations two: track lime
(`--vs-illum`) means the ledger verified something, while flag red
(`--vs-needle`) means something disagrees. An originated car has earned neither,
so the flow is almost entirely unlit — and this is the system telling the truth
rather than a gap to style around. Lime appears once on screen 4, on the owner's
own timeline tick (`.vs-tick[data-owner="true"]`, the established rule). Red
appears once in the entire flow, on screen 7, where something finally diverges.

**The disclosure and the hook are the same sentence.** *"Everything on this page
is your word. Add the VIN and the factory record fills in underneath it."* That
is the honest statement of a tier-1 record and the strongest next action in the
product, in one line — so there is no trade between candour and conversion, and
copy never has to assert more than the ledger supports. By day fourteen it
quiets to a standing footnote: it should not shout, and it should still be true.

The §6 paper ground — the factory record — does not render at all on an
`:asserted` car. It is not an empty shell with dashes in it. The page simply
ends, and the VIN is what unrolls it.

### 7b.4 What it costs

| Where | What changes |
|---|---|
| `registry/identity_key.ex`, `registry/vehicle.ex` | Fourth constructor and the enum value. **Load-bearing** — a wrong key merges two cars or splits one, and there is no merge machinery to undo it. |
| `registry.ex` | An origination entry point beside `ingest/1`, plus one-way resolution. |
| Extraction | First hosted LLM call in the project. `:req`, per convention; stubbed with `Req.Test` in tests. |
| Registration | Handle field on the phx.gen.auth form; the pending origination carried into it. |
| Adjudication | The absorb outcome. Deferred, owed. |

Reused without change: `ensure_party/2`, `grant_stewardship/2` (both already
public and independent of the challenge machinery — `owners.ex:54`,
`owners.ex:106`), `compose_entry/3`, both projections, `timeline/1`, the
composer, and the whole `vs-*` system. **Claiming turned out to be one caller of
the owner machinery rather than its owner**, which is why origination is mostly
new surface over existing plumbing.

### 7b.5 Open

- **Links as evidence.** A dated YouTube video of the car carries the same
  contemporaneity that makes a build thread credible (§0's third lesson). If
  links become evidence they gain a date and an artifact and move onto the
  spine. That is a claim-writing change, not a layout one, so holding §2's
  curation position costs nothing today. `GREG'S CALL`.
- **Unconfirmed orphans.** A registration never confirmed leaves a car with a
  log and a steward that nobody can see. Greg, 2026-08-04: *"who cares? that's
  fine."* Recorded as accepted, not as unresolved.
- **Origination throttle.** Asserted origination is a second door that mints
  vehicle rows, now bounded by email-address rather than by nothing. Needs a
  ceiling of the same shape as §7's lookup limit.

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
  `event.outing`, `event.service`, `event.plan` as of round 5,
  `observation.mileage`); anything that
  doesn't fit falls into the note residual, never rejected. Creates the
  claims under one `entry_ref` — proposed and self-ratified in one
  transaction, per the ticket H decision — and returns a human-readable echo
  for the assistant to read back.
- `amend_entry(vehicle, entry_ref, claims[])` / `delete_entry(vehicle,
  entry_ref)` — correction, which replaced the confirm step (decided
  2026-08-03). Retract-and-relog under the same `entry_ref`; the withdrawn
  values stay in the ledger.
- `attach_link(vehicle, url, label?)` — link curation (§2). *Not built in
  ticket H:* it needs `vehicle_links`, which round 5 moved to the origination
  ticket (N, TK-024).
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
  attribution on every entry. **Party name = the handle, immutable** (decided
  2026-08-02); a separate mutable display name is presentation-only. The
  immutability isn't aesthetics: the party name is baked into every claim's
  `content_hash`, so a renamed party would orphan its own history's hashes.
  Pseudonymous handles are also the privacy posture (below).

  **Timing, unified 2026-08-04 (round 5): chosen at registration, for every
  account.** The rule had moved twice — chosen at the grant (2026-08-02),
  then at code issue (ticket E), then §7b put it on the registration screen
  for originators — and three timings in one product was two too many. The
  *user* now carries the reserved handle from registration; the party is
  minted with it at the first assertive act, so the binding principle — no
  placeholder ever hashed, no party until there is something to attribute —
  is untouched. Only the reservation moved earlier. The claim flow's handle
  step goes away (one less screen), commenters (§6b) get an identity for
  free, and the migration is trivial because existing users are seed and
  test accounts. Lands with ticket N (TK-024).
- **MCP tokens.** Mint/revoke in account settings (§8): scoped to the user's
  stewardships, shown once, revocable individually. Token last-used display
  so a leaked token is noticeable.
- **Notifications: email-only in v1.** Magic links, claiming decision,
  counter-claim alert (§4 — time-sensitive, the one that must not be missed).
  (The pending-entry nudge died with the confirm step — ticket H.) Swoosh
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

- **Claiming queue** (§4): proof photo, vehicle context, approve/deny —
  shipped with ticket E. The vision pre-check's read joins this screen as a
  proposal when volume forces auto-approve, not before.
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
  30-day check), correction rates (amend/delete, the confirm step's
  replacement signal), claims/day. Read-only, computed, no new tables.

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
>    possession proof · **origination** (§7b: a car asserted into existence
>    before its VIN — one box for lookup and origination, extraction as the
>    first hosted LLM call) · logbook vocabulary (`event.fuel`,
>    `event.modification`, `event.note`, `event.outing`, `event.plan`,
>    `state.*` traits) ·
>    **`current_state` projection** (the logbook as a replayable log folding
>    into "the car now"; page leads with the living car, provenance as
>    foundation) · phone-first
>    composer · **MCP agent entry surface** (voice via the owner's own LLM;
>    self-ratifying — the tool call is the owner's assertive act, correction
>    replaces confirmation) · scope-split self-ratification · **narrative
>    layer** (§6c: story, plans, photos) ·
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

### Build tickets (letters map to TK tickets in the tracker)

| # | Ticket | Depends on | Notes |
|---|---|---|---|
| A | Auth + accounts: `phx.gen.auth` magic link, User↔Party link, operator flag, /bench behind auth | — | |
| B | Ledger prerequisites: `ratified_by_party_id`/`ratified_at`, `entry_ref` column + event-hash amendment, artifact `source_party_id` fix, `visibility` columns | — | Load-bearing (claim ledger) — main-thread work, not delegated. Test-first; corpus re-run green is the acceptance test. |
| C | Logbook vocabulary: `event.fuel`, `event.modification`, `event.note`, `event.outing`, `state.*` seed traits, `sets` deltas + validators + tests | — | Small, test-first. |
| M | `current_state` fold (§2b): derived map, transaction-hook refresh, admitted-only latest-wins fold, replay test (drop + re-fold = identical) | B, C | Load-bearing (arithmetic, same class as facts) — main-thread work, not delegated. |
| D | Public vehicle page: `/v/:public_id`, VIN resolver, §6 hierarchy (hero from `current_state`, timeline-centered, record as foundation layer), lookup + create-on-first-lookup, rate limit | B, M | Read-only; ships before claiming exists (unclaimed pages are the bait). |
| E | Claiming: challenge codes, proof upload, /bench approval queue, stewardships | A, B | Shipped 2026-08-03 (TK-015) — without the vision pre-check, struck below. |
| F | Entry composer: segmented modes, photos, scope-split self-ratification path, current-spec panel (§2b cold start) | A, B, C, M | The make-or-break ticket; §1 is its spec. Shipped 2026-08-02 (TK-014) without links — the table moved to N. Plan mode arrives with O. |
| G | Privacy controls (flipping visibility after the fact) + full-record export | F | TK-016. The own-view slice shipped 2026-08-03; `vehicle_links` moved to N in round 5. |
| H | MCP agent entry surface: token auth, tool set (`my_vehicles`, `log_entry`, `amend_entry`, `delete_entry`, `get_timeline`), self-ratifying entries + owner correction | A, B, C | §8's contract. Shipped 2026-08-03 (TK-017); confirm step and pending queue struck below, `attach_link` waits on N's table. |
| I | Distribution kit: share card, forum snippet (BBcode/markdown), embeddable badge, per-vehicle thread URL + "post to my thread" flow | D, F | Shipped 2026-08-10 (TK-018). Entries travel to existing audiences; page remains canonical. |
| J | Platform plumbing: transactional email, S3-compatible artifact storage, image pipeline (share cards, thumbnails), rate limiting, ToS/privacy pages | — | Launch blocker; parallelizes with A–D. Email before A ships (magic links), storage before E ships (proof photos). |
| K | Operator admin: claiming/ratification/dispute/report queues in /bench, user suspend + stewardship revoke, metrics strip | A, E | Greg's daily surface; §9.2 is its spec. |
| L | Embeds: YouTube oEmbed + iframe, IG bare-link cards, oEmbed metadata storage; Discourse crosspost when a target community warrants | D, F | Phased per the §9.3 honesty table. |
| N | Origination (§7b): `:asserted` identity kind, one-box entry + extraction endpoint (first hosted LLM call), one-way VIN resolution, registration handle (universal, §9.1), `vehicle_links`, origination throttle | A, B, J | TK-024. Load-bearing at the identity key — main-thread work, not delegated. |
| O | Narrative layer (§6c): story block, `event.plan` + composer Plan mode, photo-first update, mutable hero/gallery presentation | C, F | Shipped 2026-08-10 (TK-025). External-gallery links reuse N's `vehicle_links`. |

**Status, 2026-08-10.** Shipped: A (TK-007), B (TK-008), C (TK-009), M
(TK-010), D (TK-013), E (TK-015), F (TK-014, sans links), H (TK-017), J
(TK-006), I (TK-018), O (TK-025), plus G's own-view slice and the composer edit
mode ticket H's correction rule exposed (TK-021, open). Open: G (TK-016, minus
links), K (TK-019), L (TK-020), N (TK-024).

**Build order (Greg, round 3): infra first.** J, A, B open the build — no
design dependencies, and they gate everything downstream (email gates A's
magic links, storage gates E's proof photos, B is the ledger seam every
other ticket touches). C and M follow immediately; then D ships value
(public pages, lookup) before any auth-gated surface exists — layered
commits, each green. A→E→F/H remains the critical path to the first owner
entry. F and H land together conceptually — the same self-ratifying write
path, two doors — but commit separately. K, I, L trail
the critical path and can land incrementally after first owners exist. Round
5's addendum to the order: N is the new front of the funnel and I is upstream
of comments (§6b) — so the remaining sequence is N → O → I → G/K/L, with
§6b's build unscheduled behind I. The
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

### Decided 2026-08-04, origination design walk

Prompted by Greg walking his own first-run case — a 2024 Lexus GX 550, green,
35,000 miles, no VIN — and by analysis of two Rennlist threads (classified
1508628, build thread 1451795). Full rationale in §7b; the calls, compressed:

- **§7b `:asserted` identity kind.** A car may exist before it has a VIN. Chosen
  over VIN-required and over a draft object outside the registry.
- **§7b self-ratifying identity claims on asserted cars** — a scoped deviation
  from §3, affordable precisely because VIN resolution audits it through
  `claim_comparison/1` rather than on trust.
- **§7b one box.** Origination and §7 lookup share an input; the identity kind
  is an outcome of what was typed.
- **§7b extraction over a form.** Sentence in, claims out, the sentence stored
  as the artifact. The project's first hosted LLM call. This also reopens §1's
  parser deferral, which was priced when we had no parser at all.
- **§7b conflicts are never refused.** Greg: *"I don't think we should stop
  anyone from claiming.. even if there's a conflict."* This overturned a
  recommendation made earlier in the same walk to refuse a resolution into an
  occupied VIN — a submission-time gate in an architecture that gates nothing
  anywhere else. The unique index defers the key flip, not the claim. Accepted
  cost: an absorb write path is now owed.
- **§7b the user exists before the email is sent**, so the magic link publishes
  rather than unlocks and there is no pending state to carry.
- **§7b handle at registration, permanence stated on the screen.** §4's
  chosen-at-issue/minted-at-proof refinement has no analogue in a flow with
  neither event.
- **§7b unconfirmed orphans accepted.** Greg: *"who cares? that's fine."*
- **§6b opened** — comments and likes, stated as a question with its doctrinal
  edge (a comment is not a claim; the promote-to-claim seam is the real
  decision) rather than designed.
- **§1 amended** — the entry-UI question Greg raised (*"click a button and start
  talking"*) is recorded as undesigned and `GREG'S CALL`, with §1's own analysis
  noted as cutting against voice for the fill-up case specifically.

### Decided 2026-08-04, round 5 (Greg, reviewing against the build-thread use case)

The review's finding: a build thread is story + plan + photos + replies, and
the doc had formalized only the events. The calls:

- **§6c opened — the narrative layer** (ticket O, TK-025).
  *Story*: an optional, mutable curation block, never a claim. The bar is
  deliberately low — Greg: *"sometimes what's special about it is just that
  it's mine and it's my baby"* — one sentence clears it, and the public page
  renders nothing rather than a nudge.
  *Plans*: dated aspiration entries (`event.plan`), Greg's framing — *"almost
  like a blog post... let me record this on Monday and I can review it. These
  are the wheels I'm looking at now"* — not a checklist, not threaded. His
  forum-nervousness is answered structurally: every response mechanic stays in
  §6b, and a plan asserts intent, never history.
  *Photos*: added after setup, never an origination screen — Greg: *"I don't
  think they're gonna be in the origination flow... once the whole thing is
  set up."* Composer photos, the photo-first note, gallery/platform links,
  and the hero's owner-facing nudge.
- **§6b doctrine calls taken**: owners cannot moderate others' comments
  (report-to-operator only — witnessed credibility is the product); no
  promote-to-claim in v1; likes cosmetic, never a tier input; handles
  required; comments sequenced after the distribution kit (I). The surface
  itself remains undesigned and unscheduled.
- **§9.1 handle timing unified**: chosen at registration for every account,
  reserved on the user, party minted with it at the first assertive act.
  Supersedes chosen-at-grant (2026-08-02) and chosen-at-issue (ticket E).
- **`vehicle_links` moves from ticket G to N** — §7b's screen 5 needs it, and
  a downstream ticket owning an onboarding table was a dependency inversion.
- **§10 hygiene** (Maya's call, delegated): roadmap text and ticket rows
  still describing the struck confirm step and vision pre-check corrected;
  shipped statuses recorded; N and O cut as TK-024/TK-025.

### Decisions still queued for the walk, in order

5. §9.1 — the deletion posture: credentials delete, party + claims persist.
   The ledger-integrity vs right-to-erasure line, in Greg's words. Not yet
   blocking: nothing deletes an account today.
6. §1 — mobile-web-only v1 (no native app).
7. §10 — the §11 rewrite text and ticket cut A–L.
8. §7b — links as evidence or curation. Holding §2's curation position costs
   nothing today, because promoting links to evidence is a claim-writing change
   rather than a layout one. Greg has build-thread links still to supply that
   may argue the other way.
9. §1 — the entry surface for a fill-up, in Greg's words: "click a button and
   start talking." Needs its own pass; §7b's extraction endpoint changes what it
   costs to build.
10. §6b — the comments surface itself: schema, rendering, report handling for
    speech, email volume. The doctrine calls are taken (round 5); what remains
    is the design pass and its scheduling, behind ticket I.
