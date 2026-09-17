# Vin Santo

A provenance registry for collector cars: the canonical, chassis-level record a
car carries across owners and sales. Owners keep a logbook, operators adjudicate
evidence at the bench, and the ledger underneath is the asset. One Phoenix
application: Elixir 1.17, Phoenix 1.8, LiveView 1.2, Ecto/PostgreSQL, Oban, on
top of the `santo` VIN-decode library (path dep, `../santo`).

| Read this | For |
|---|---|
| `design.md` | The product thesis and the staged build |
| `docs/design/evidence_contract.md` | Claim, scope, conflict, and evidence-request semantics. Read it before touching `lib/santo_api/registry/` |
| `docs/design/owner_surface.md` | The owner tranche: logbook, origination, privacy, agent surface. Numbered, and the code cites it (`owner_surface §7b`) |
| `docs/design/car_page.md`, `theme_system.md` | The public page and the visual system. Binding; they override generic UI guidance |
| `docs/design/providers.md`, `corpus.md` | Provider architecture; the dossier corpus and its friction log |

## The line the codebase is built around

The ledger is the product; everything else renders it. These are the evidence
contract's invariants — violating one is a design bug, not a style nit.

- **Claims are append-only.** A correction is a new claim plus an adjudication,
  or a retraction under the same `entry_ref` — never an edit, never a delete.
  Adjudication changes which claim is live; both stay in the ledger.
- **Basis fields are stamped, never cast.** `Claim.propose_changeset/4` casts
  the assertion and puts `vehicle_id`, `asserted_by_party_id`, `method`,
  `state`, and `content_hash`. A cast basis field lets a caller forge
  provenance; a caller-supplied hash collapses two distinct claims into one.
- **Santo-derived decode facts are the only claims born `:admitted`** — they are
  deterministic functions of the identifier, the one class of fact the registry
  may assert on its own authority. Everything else enters `:proposed` and is
  admitted only by ratification: one state flip with who and when
  (`ratified_by_party_id`, `ratified_at`), not a workflow. Scope decides who may
  ratify — owners self-ratify event and observed claims on cars they steward;
  factory and provenance claims ratify only at the operator gate or on evidence.
- **The predicate vocabulary is closed.** Only predicates in
  `registry/vocabulary.ex` exist; adding one is a reviewed code change, like
  santo's compiled data. Same for `providers/capability.ex`.
- **Conflicts and verification tiers are derived, never stored.**
  `claim_comparison/1` computes agreement, conflict, single_source, and history
  at read time. Nothing overwrites anything.
- **`vehicle.facts` is factory and provenance scope only.** Event-scoped
  material — service, modification, sale — is logbook territory and never
  flattens into facts. Observed claims fold into `vehicle.current_state`, the
  sibling projection, computed independently and never from `facts`. `facts`
  ties to the earliest claim, `current_state` to the latest: facts asks what was
  true at birth, current state what is true now. Get either wrong and the
  product lies about the car, which is the one thing it sells.
- **A wrong identity key merges two cars or splits one.**
  `registry/identity_key.ex` decides which physical chassis a row is about;
  `:disputed` rows carry candidates as data, `:asserted` rows are cars minted
  before any identifier, and no merge machinery exists to undo a bad key.
- **Stewardship is authorization, never registry truth.** Claiming a car creates
  no ownership claim: possession proves access, not title. A page says
  "maintained by", never "owned by".
- **Providers acquire; they never persist claims or decide truth.** Turning a
  payload into claims is Registry-side. `rights_profile` governs what may legally be stored and redistributed.
  `coverage: :none` means the provider had nothing to say — never "clean
  history."
- **LLMs extract, code computes.** Extraction proposes claims
  (`method: :llm_extract`) with the artifact attached; precedence, comparison,
  and hashing stay deterministic. No blending.
- **Evidence comes from licensed feeds, government and public sources, and
  owner-supplied artifacts.** No unlicensed scraping. Listing text and comments
  are proposed claims until corroborated.
- **Copy never asserts more than the ledger supports.** Absence of evidence is a
  gap, not a clean record.
- **Decode bugs are fixed upstream in `../santo`**, never patched around here.

## Where things live

```text
lib/santo_api/registry.ex      the ledger's API: ingest, propose, ratify, adjudicate, project
lib/santo_api/registry/        claim, adjudication, artifact, party, vehicle, vocabulary, identity_key
lib/santo_api/owners.ex        stewardship and what a user may assert; every ledger write goes through Registry
lib/santo_api/bench.ex         the authorized boundary for the operator workbench
lib/santo_api/providers/       evidence acquisition; static registry, capability-keyed
lib/santo_api/events.ex        shared events; social.ex is discourse about a record, outside the ledger
lib/santo_api/extraction.ex    the one-box extractor; entry_extraction.ex is its logbook sibling
lib/santo_api/storage.ex       artifact bytes; media.ex makes the public, metadata-stripped variants
lib/santo_api_web/router.ex    pipelines and their reasons, in comments — read it before adding a route
lib/santo_api_web/live/        bench_live (operator), owner_live, vehicle_live, garage, origination
lib/santo_api_web/mcp/         the agent surface at /mcp: bearer token, no session
priv/corpus/                   the dossier cars, replayed through the real registry paths
```

Contexts are the API: web and LiveView call contexts, contexts call Ecto. There
are no `Repo` calls under `lib/santo_api_web/`, and there should stay none. The
ledger, the projections, identity keying, and provider rights are handled inline
and never delegated to `elixir-dev`; the rest of the app is fine to delegate.

## Commands

```sh
mix precommit    # warnings-as-errors, unused deps, format, test — before calling anything done
mix run priv/corpus/cayman_s.exs  # also gt3_touring, carrera_gt; adjudications.exs runs last
mix santo.acquire.free            # the free public-source acquisition cohort
```

Greg runs the dev server himself on `PORT=4001`; don't start `mix phx.server`.
When it is up, Tidewave at `/tidewave/mcp` is the way to evaluate code, query the
database, and look up docs and definitions.

## Testing

No network: external HTTP is stubbed with `Req.Test` plugs from
`config/test.exs` against fixtures in `test/support/`, so a test that reaches the
internet is a bug in the test. Oban runs `testing: :manual` with queues off —
drive attempts with `Oban.Testing`. Rate limits are lifted except `login_email`,
exercised for real because it is keyed per address.

## Conventions

- Corpus and ingest scripts are re-runnable and idempotent: artifacts and claims
  dedupe by content hash, and a second run reports what already exists.
- Uploads are content-hashed into the configured `:uploads_dir`. `storage_ref`
  is the basename only and is validated as one on the way in and out, which is
  why moving to object storage is configuration rather than a migration.
- Original artifact bytes are served only at `/bench/artifacts/:id`, inside the
  operator gate. Public pages get metadata-stripped derivatives from
  `SantoApi.Media`, resolved through a placement, never a raw artifact id.
- `/bench` stays the operator surface: owner-facing affordances belong on the
  owner routes, which wear the public car-first layout.
- The operator flag is set out of band. `/bench/access` suspends accounts and
  revokes stewardships; it does not grant the flag.
- Moduledocs say why, name the rejected alternative, and cite the design docs by
  section. Match that when adding a module.
- Incidents and gotchas go to HIVE memory, not this file.
