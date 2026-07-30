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

## 8. Seams deliberately left, not built

- **Attestation**: a signed statement over a content-hashed set of admitted claims
  at a point in time. v1 only ensures claims are hashable and immutable.
- **Extraction pipeline**: artifact → extractor → proposed claims → human
  ratification → admitted. Import revrec's lesson: capture corrections as signal;
  prefer deterministic post-extraction fixes over prompt hints. Oban when real.
- **Logbook entries** (design.md layer 2): a logbook entry is a presentation of
  claims sharing an event scope — same substrate, no separate entry store.

## 9. Shape on disk (indicative, not DDL)

`vehicles` (surrogate id, identity fields, status) · `parties` · `artifacts` ·
`claims` (subject, predicate, value, scope, basis refs, state, hash) ·
`evidence_requests` · `adjudications`. Six tables; conflicts and tiers are queries.

## 10. Build order after sign-off

1. Schemas + contexts for §9, with the dossier corpus cars
   (Carrera GT / 959 / Cayman S) as the seed fixtures — fixtures must enter through
   the real ingest path, not hand-inserted rows.
2. `POST /api/vins` — accept input, `Identity.key/1`, persist vehicle, snapshot the
   santo decode as claims with `basis.method = santo`.
3. Dossier workflow surfaces (upload artifact, propose claim, ratify, adjudicate).
4. Vendor benchmarks (vPIC oracle already exists; DataOne/NMVTIS later) — only
   after the contract holds real data.
