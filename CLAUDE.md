# Vin Santo — a provenance registry for collector cars

Phoenix 1.8/LiveView + Ecto/Postgres, on top of the `santo` VIN-decode library
(path dep, `../santo`). Elixir/Phoenix style rules: `AGENTS.md`. Product thesis:
`design.md`. Domain semantics: `docs/design/evidence_contract.md` — read the
contract before touching anything under `lib/santo_api/registry/`.

## Development commands

### Essential commands
- `mix setup` — install deps, create/migrate database, build assets
- `mix precommit` — compile with warnings-as-errors, unused-deps check, format, test. Run before claiming done.
- `mix test` — full suite (Ecto sandbox against the local Docker Postgres)
- `mix ecto.reset` — drop, create, migrate, seed
- `mix run priv/corpus/cayman_s.exs` (also `gt3_touring.exs`, `carrera_gt.exs`) — replay a corpus car through the real registry paths. Idempotent. `adjudications.exs` runs after all three.
- `mix phx.server` — **NEVER RUN** (user manages the dev server separately). Port 4000 is usually taken on Greg's machine; he runs it with `PORT=4001`.
- Use Tidewave's tools for runtime evaluation and database queries when the dev server is up (`/tidewave/mcp`); `get_docs` for documentation, `get_source_location` for definitions.

### Database
- Local Postgres runs in Docker: `docker compose up -d` in `~/work/infra/` (imresamu/postgis:17-3.5, pinned to major 17 to match Fly prod and the data volume). Database `santo_api_dev`, credentials postgres/postgres on localhost:5432. The PostGIS image is shared infra — santo_api itself uses no geo types.
- The volume `arete_postgres-data` holds every project's dev DBs — never remove it.
- Brew postgresql@14/16/17 are installed but stopped; don't start them (port 5432 collision on the loopback).

## Load-bearing subsystems (handle inline, never delegate)

- **The claim ledger** — `lib/santo_api/registry/claim.ex`, `registry/adjudication.ex`,
  and the write paths in `registry.ex` (`propose_claim`, `ratify_claim`,
  `adjudicate_claims`). `content_hash` is the attestation seam and includes the
  asserting party; basis fields (`vehicle_id`, `party_id`, `method`, `state`,
  `content_hash`) are stamped, never cast. A cast basis field lets a caller forge
  provenance; a wrong hash silently collapses two distinct claims into one.
- **Fact materialization and comparison** — `refresh_facts/1`,
  `claim_comparison/1`, `Vocabulary.equivalent?/3`. This is the arithmetic:
  precedence (admitted > proposed, ties to earliest), conflict detection,
  verified/unverified/conflicted status. Get it wrong and the product lies about
  what's been verified, which is the one thing it sells.
- **Identity keying** — `registry/identity_key.ex` and `Registry.ingest/1`. The key
  decides which physical chassis a row is about. A wrong key merges two cars or
  splits one; `:disputed` rows carry candidates as data and there is no merge
  machinery to undo a bad key.
- **Provider rights and coverage semantics** — `providers/acquisition.ex`,
  `providers/provider.ex`. `rights_profile` governs what we may legally store and
  redistribute. `coverage: :none` means the provider had nothing to say — never
  "clean history."

Everything else — bench LiveView, JSON rendering, controllers, corpus scripts,
migrations — is fine to delegate to `elixir-dev`.

## Doctrine constraints on code and copy

These are the evidence contract's invariants. Violating one is a design bug, not a style nit.

- **Claims are append-only.** Corrections are a new claim plus an adjudication — never an edit, never a delete. Adjudication changes which claim is live; both stay in the ledger.
- **External evidence enters `:proposed`.** Only santo-derived decode facts enter `:admitted`. Ratification is one state flip with who and when, not a workflow.
- **The predicate vocabulary is closed.** Only predicates in `registry/vocabulary.ex` exist; adding one is a reviewed code change, like santo's compiled data. Same for provider capabilities in `providers/capability.ex`.
- **Conflicts and verification tiers are derived, never stored.** `claim_comparison/1` computes agreement/conflict/single_source at read time. Nothing overwrites anything.
- **`vehicle.facts` is factory/provenance scope only.** Event-scoped material (service, modification, sale) is logbook territory and never flattens into facts. Observed claims (e.g. `observation.mileage`) deliberately never appear there either.
- **Providers acquire; they never persist claims or decide truth.** Per-provider interpretation lives Registry-side (`acquisition_facts/1`). Providers own transport, diagnostics, and rights metadata.
- **LLMs extract, code computes.** Extraction proposes claims (`method: :llm_extract`) with the artifact attached. Precedence, comparison, and hashing stay deterministic. No blending.
- **Evidence comes from licensed feeds, government/public sources, and owner-supplied artifacts.** No unlicensed scraping. Listing text and comments are proposed claims until corroborated.
- **Decode bugs get fixed upstream in `../santo`**, not patched around in the registry.
- Copy never asserts more than the ledger supports: absence of evidence is a gap, not a clean record.

## Project conventions

- Corpus and ingest scripts are re-runnable and idempotent — artifacts and claims dedupe by content hash, and a second run reports what already exists.
- Ingest-heavy test files are `async: false` on purpose. Two sandbox transactions inserting the same real VINs and parties in opposite order hit Postgres `deadlock_detected`. Don't flip them back.
- Vendor values are normalized into the value shapes santo emits (e.g. `identity.model` is always `%{"code", "label"}`) so comparison compares like with like. Per-predicate equivalence lives in `Vocabulary.equivalent?/3`.
- Uploads are content-hashed into the configured `:uploads_dir`; `storage_ref` is the basename only, so the store can move.
- Use `:req` (`Req`) for HTTP; avoid `:httpoison`, `:tesla`, `:httpc`. External calls are stubbed in tests via `Req.Test` with fixtures under `test/support/`.
- `/bench` is the internal operator surface (propose, ratify, adjudicate, upload). It sits behind `require_authenticated_user` + `require_operator_user` (plus the matching `live_session` on_mounts). Don't add user-facing affordances to it — owner surfaces are their own routes.
- Auth is `phx.gen.auth`, magic-link only. Passwords are deliberately not shipped in v1 (`owner_surface.md` §5): the `hashed_password` column and the `Accounts` password functions are kept so enabling them later is a UI change, not a migration. Don't wire password forms back in without Greg's call.
- The operator flag is set out of band — `SantoApi.Accounts.set_operator(user, true)` from IEx. There is no self-serve path until the user admin surface (§9.2) exists.
- Every corpus dossier documents sale result, paint code, production/delivery dates, delivery dealer, and service events. Those are required vocabulary fields, not optional metadata.
