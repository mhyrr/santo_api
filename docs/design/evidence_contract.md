# Evidence Contract

*Defines artifact, claim, scope, conflict, and evidence-request semantics for the
Vin Santo registry. Precedes vendor selection and all domain schemas (design.md §"Staged
build", step 1). Forks A–C decided by Greg 2026-07-30.*

Inherited commitments, treated as canon here:

- Santo claims only identifier-defensible facts; everything else is evidence
  (hive decision, 2026-07-30).
- The oracle pattern: observers label agreements, conflicts, and coverage gaps —
  they never overwrite (hive decision, 2026-07-30).
- Ratification-gate shaped: proposals are never auto-applied; the system never guesses
  (santo's `Invalid.repaired`, revrec's approval flow).
- LLMs extract, code computes.
- No Ash — plain contexts + Ecto; these tables are hand-designed because they are
  the product.

---

## 1. Identity — what a record is *about*

The registry keys on **identity, not input string** (`Santo.Identity`: VIN ≠ identity).

- A `vehicles` row is created from `Santo.Identity.key/1`, which always returns one
  keyable term: `{:vin, s}`, `{:chassis, marque, era, number}`, or
  `{:disputed, [candidates], evidence_requirements}`.
- The row's primary key is a surrogate id. Identity is an *attribute* of the row,
  because identity itself can be corrected (re-stamps, replicas, era crossovers) and
  the page/URL must survive the correction. Identity corrections are adjudication
  events (§5), never updates in place.
- A `:disputed` identity is a first-class registry state, not an error: the row
  stores its candidate identities and open evidence requirements (§6) from day one.

**Decided (A):** one row per disputed input, candidates as data, adjudication
resolves in place. No merge machinery until a real case forces it.

## 2. Artifact — what we hold

An artifact is an immutable acquired thing: uploaded document, photo, receipt,
API response snapshot, scraped listing.

- Fields: content hash (sha256), storage ref, mime, kind
  (`document | photo | receipt | api_snapshot | listing`), source (supplying party
  or vendor + URL where applicable), `acquired_at`, free metadata.
- Artifacts never change. A re-fetch of the same URL is a new artifact.
- `acquired_at` is when *we* obtained it. A document's issue date is a claim *about*
  the artifact, extracted like any other claim.
- Artifacts evidence claims; they assert nothing by themselves.

## 3. Claim — the atom of the registry

A typed assertion about one vehicle.

- **subject**: vehicle id.
- **predicate**: namespaced term — `identity.era`, `build.paint_code`,
  `build.option_package`, `observation.mileage`, `legal.title_brand`,
  `config.engine_number`. The namespace *is* the scope-kind hint (§4).
- **value**: jsonb, validated per predicate by vendored code (santo's compiled-data
  pattern: vocabularies live in code, not in rows).
- **scope**: §4.
- **basis** (the source chain): asserting party + evidencing artifact(s) + method
  (`santo | structured_api | llm_extract | human`). Verification tier (§7) is
  computed from basis, never stored.
- **state**: `proposed → admitted | rejected`, later `superseded | retracted`.
  Proposed claims are the ratification gate; only admitted claims are the record.
  External evidence enters `:proposed`. *Who* may ratify depends on scope
  (amended 2026-08-01, owner_surface §3): owners self-ratify event- and
  observed-scope claims on cars they steward; factory- and provenance-scope
  claims ratify only at the operator gate or by corroborating evidence.
  `Vocabulary.scope_kind/1` is where that line is drawn.
- Claims are append-only and content-hashed (the attestation seam, §8). A
  correction is a new claim plus an adjudication linking the two — never an edit.

**Decided (B):** closed-small predicate vocabulary — only predicates with vendored
validators exist; adding one is a code change, like santo's compiled data. Revisit
open-namespace only when agent-ingestion pressure is real.

**Decided (C):** minimal `parties` table from day one (name, kind
`owner | vendor | shop | registry | vin_santo`) — tier computation needs real
asserters.

## 4. Scope — the two tenses, made mechanical

Every claim carries a scope kind; predicates imply their kind:

- **`factory`** — as-built, timeless (paint code, option list, engine number as
  delivered).
- **`observed`** — true as of a date (mileage, current configuration, photos).
  Two observations of the same predicate at different dates are *history*, not
  conflict.
- **`event`** — happened at a date (title issue, sale, accident, rebuild).
  Events accumulate; they never supersede each other.

"Current configuration" is computed: latest admitted `observed` per predicate.
It is never conflated with `factory` — that distinction is the whole dossier.

## 5. Conflict — disagreement as data

- A conflict is *derived*, not stored as truth: two admitted claims, same subject +
  predicate + overlapping scope, incompatible values. Surfaced exactly as the
  oracle does: agreement / conflict / coverage gap.
- Resolution is an **adjudication**: its own record — who decided, on what evidence
  (artifact refs), outcome (supersede one claim | coexist with note | request
  evidence). Adjudications are the casebook (design.md moat #4).
- Nothing is deleted. A superseded claim remains visible in the record's history —
  that visible history is the trust product.

## 6. Evidence request — the addressable gap

Generalizes santo's `{:evidence_required, subject, classes}` notes.

- Fields: vehicle, subject (predicate or `identity`), acceptable evidence classes
  (`kardex | coa | pps | window_sticker | build_sheet | inspection | nmvtis |
  engine_number | title_document | ...`), status (`open | satisfied | abandoned`),
  satisfying claim/artifact.
- Created three ways: automatically from santo notes at ingest; by adjudications
  that need evidence; by humans in the dossier workflow.
- This is also the monetization seam: an evidence request with a price attached is
  a product (PPS order, inspection, NMVTIS pull).

## 7. Verification tier — computed, never asserted

From claim basis, by code:

1. **self-reported** — party assertion, no artifact.
2. **receipt-backed** — evidencing artifact attached.
3. **third-party verified** — evidencing artifact whose source is independent of
   the asserting party.

Tier composition per vehicle ("87% receipt-backed over 6 years") is an aggregate
over admitted claims — free once claims carry basis.

## 8. Facts — the one-row projection

*(Added after the 2026-07-30 walk: claims are the ledger; this is the balance
sheet. Decided with Greg.)*

Each vehicle carries a materialized `facts` map — one row per vehicle, queryable
across the registry: predicate → `{value, status}`.

- **Projected from factory/provenance-scoped claims only.** Facts describe the
  car and its provenance: build data, plant, delivery market, PTS color.
  Event-scoped claims (modifications, maintenance, rebuilds) are the logbook's
  substrate and present as a timeline — they never flatten into facts.
- **Status** is computed, three values: `verified` (an admitted claim, no live
  disagreement), `unverified` (proposed claims only), `conflicted` (live
  disagreement — surfaced, never hidden).
- **Value precedence** when sources differ: admitted beats proposed; ties break
  to the earliest claim. The losing value stays visible in the claims and the
  comparison — facts pick a face, they don't erase.
- Recomputed inside every transaction that writes claims. Reading facts costs
  one row; the receipts underneath are for sale moments, disputes, appraisals.

**The second projection** (added 2026-08-02, owner_surface §2b). `facts` answers
what the factory built. `current_state` answers what the car *is* — latest
admitted observed-scope claim per predicate, plus the `sets` deltas carried by
admitted `event.modification` and `event.outing` claims. It is a sibling map on
the vehicle, folded from the same ledger in the same transaction hook
(`refresh_projections/1`) and **never computed from `facts`**: a swapped car has
a thin factory column and a full current-state one, so factory can't be the
baseline. Its precedence deliberately inverts §8's — latest scope date wins,
ties to the latest insertion — because facts asks what was true at birth. Only
admitted claims fold; a proposed entry never mutates public state. Divergence
between the two maps (originality vs. build story) is computed at render, never
stored, same doctrine as conflicts.

Canonical examples of evidence-borne facts santo can never claim: paint-to-sample
color (Kardex/PPS/COA territory), European delivery (delivery provenance ≠ VIN
market). They enter as proposed claims from artifacts or owners and become
verified facts through the gate.

Ratification, named precisely: one state flip, `proposed → admitted`, with who
and when attached. Not a workflow. The who and when are columns —
`ratified_by_party_id` and `ratified_at` (TK-008) — and they are null exactly
when no ratification happened: santo decode facts, which are born `:admitted`,
and claims admitted by an adjudication, whose decider lives on the adjudication
row instead.

The scope split above is what lets an owner's own logbook entry admit without an
operator in the loop. It is low-stakes by construction: event-scoped claims never
enter `facts`, never conflict, and never move any verified status. What carries
the honesty is attribution and tier (§7), both mechanical.

## 9. Seams deliberately left, not built

- **Attestation**: a signed statement over a content-hashed set of admitted claims
  at a point in time. v1 only ensures claims are hashable and immutable.
- **Extraction pipeline**: artifact → extractor → proposed claims → human
  ratification → admitted. Import revrec's lesson: capture corrections as signal;
  prefer deterministic post-extraction fixes over prompt hints. Oban when real.
- **Logbook entries** (design.md layer 2): a logbook entry is a presentation of
  claims sharing an event scope — same substrate, no separate entry store. The
  facts/logbook boundary is §8: owner-facing event streams stay out of facts.

## 10. Shape on disk (indicative, not DDL)

`vehicles` (surrogate id, identity fields, materialized `facts`) · `parties` ·
`artifacts` · `claims` (subject, predicate, value, scope, basis refs, state,
hash) · `evidence_requests` · `adjudications`. Six tables; conflicts, tiers,
and facts are computed from claims — facts materialized for cross-registry
queries, the rest on read.

## 11. Roadmap (updated 2026-07-30 with Greg — no auth, no users yet)

The v1 product is the dossier, and its only user is us: the plumbing target is an
operator workbench, not an auth system. Auth arrives with the first non-operator
surface (owner claiming is design.md layer 1/2 territory, explicitly deferred).

Done: registry schemas + ingest · vPIC evidence · facts projection · provider
abstraction (capability-based; providers acquire, the registry persists and
interprets) · bench context (file artifacts to local disk via `uploads_dir`,
propose/ratify/reject, evidence-request satisfaction).

1. **Operator bench UI** — LiveView workbench per vehicle: facts, claims with the
   ratify gate, comparison, uploads, propose-claim form. Local-only; BasicAuth
   one-liner when it ever deploys.
2. **Dossier corpus** — real documents from public well-documented sales
   (BaT-style listings with posted window stickers/COAs become `:listing` and
   `:photo` artifacts). Vocabulary predicates (paint, delivery, title events) are
   added as the corpus demands them, test-first.
3. **Extraction** — LLM reads artifacts, emits proposed claims into the same
   gate. Only after the bench can review its output. Revrec lessons apply.
4. **Dossier rendering** — the sellable output: facts, tier composition,
   timeline, citations.
5. **More providers** — DataOne/NMVTIS/listing history as capability mappers,
   benchmarked against real dossier demand; PPS as an `:async_order` provider.
