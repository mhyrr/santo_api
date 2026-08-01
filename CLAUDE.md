# VNI — Vote No Incumbents

Phoenix 1.8/LiveView + PostGIS political data project: the public case against
incumbency entrenchment. Design spec: `docs/design/001-design-pass-1.md`,
interface pass: `docs/design/002-interface-pass-1.md`. Phoenix/Elixir framework
conventions: `AGENTS.md`.

## Development commands

### Essential commands
- `mix setup` — install deps, create/migrate database, build assets
- `mix precommit` — compile with warnings-as-errors, unused-deps check, format, test. Run before claiming done.
- `mix test` — full suite (sandboxed against the local Docker PostGIS)
- `mix ecto.reset` — drop, create, migrate, seed. Seeds ingest all 435 districts for every supported Congress (119/118/117) from Census TIGER/Line, stamp current-map authorship, and score each congress within its own cohort (archives cached under `priv/repo/data/tiger/`; first run downloads ~100 zips). `VNI_SKIP_DISTRICT_SEEDS=1` skips.
- `mix vni.ingest.shapefiles --congress N` — (re)ingest TIGER CD geometry (119 current; 118/117 historical, ingested closed), idempotent
- `mix vni.ingest.zctas` — ZIP Code Tabulation Area polygons and the ZIP→district crosswalk. Not part of `mix setup`: one 530 MB archive, cached under `priv/repo/data/tiger/zcta2025/`, and the crosswalk INSERT runs several minutes. Required for `/find` to answer anything; without it every ZIP reports as unknown. Rerun `--crosswalk-only` after any district ingest — the pairs are only true of the map they were computed against.
- `mix vni.score` — full scoring pass: metrics, normalize, national rank (`--congress N` scores a historical cohort within itself)
- `mix vni.og.cards` — render the unfurl images every link needs: one site-wide default plus one per current district, into `priv/static/images/og/`. **Commit the PNGs** — generation needs the database and the Docker build cannot reach it, so they travel as committed binaries like `priv/promotion` does. Rerun after any ingest that moves geometry, incumbents, or margins; the art states facts true of the map it was drawn against.
- `mix phx.server` — **NEVER RUN** (user manages the dev server separately)
- Use Tidewave's tools for runtime evaluation and database queries when the dev server is up; `get_docs` for documentation, `get_source_location` for definitions.

### Database
- Local Postgres runs in Docker: `docker compose up -d` in `~/work/infra/` (imresamu/postgis:17-3.5, pinned to major 17 to match Fly prod and the data volume). Database `vni_dev`, credentials postgres/postgres on localhost:5432.
- The volume `arete_postgres-data` holds every project's dev DBs — never remove it.
- Brew postgresql@14/16/17 are installed but stopped; don't start them (port 5432 collision on the loopback).
- GDAL's `ogr2ogr` (brew postgis formula) is required for shapefile ingest.
- `rsvg-convert` (brew `librsvg`) is required for `mix vni.og.cards`. Same dev-side posture as GDAL — production never rasterizes anything. The task refuses to run when fontconfig cannot resolve Arial Black, because a silent substitution bakes hundreds of wrong images whose only symptom is looking wrong in someone else's timeline.

## Load-bearing subsystems (handle inline, never delegate)

- **Map versioning** (`VNI.Atlas`). Districts are addressed through map versions; current = `effective_until IS NULL`. Never make a district slug globally unique or query districts without a map-version constraint — mid-decade redistricting breaks that instantly.
- **Scoring methodology** (`VNI.Scores`). The site's credibility rests on reproducible open methodology. Measurement rules are documented in the moduledoc and are not negotiable: geography casts for area/perimeter, EPSG:5070 for constructions, never raw 4326 degrees. Any formula change bumps `@methodology_version`.
- **Pledge data (Phase 3, future).** Politically sensitive PII. Double opt-in, encrypt at rest, minimal retention. Treat like money.

## Doctrine constraints on code and copy

Exclusively anti-entrenchment: incumbency, gerrymandering, term limits. No position on anything the parties fight about. SCOTUS carve-out (no term limits there). No challenger info on district pages — any challenger will do; the purity is the point. Published facts only in `VNI.Politics`. Never use Cook PVI (licensed); lean comes from our formula over public data. All ingested data must come from government or non-partisan sources, cited with a source URL.

## Project conventions

- Ingest tasks are rerunnable and idempotent (upserts keyed on natural identity).
- Compactness scoring is Elixir orchestrating SQL — keep the math in PostGIS, the orchestration thin.
- Hand-curated data (map authorship, ~50 rows) lives in seeds with a source URL per row.
- Public LiveViews consume `VNIWeb.DistrictPresenter` maps, never raw structs — geometry stays out of the socket.
- Use `:req` (`Req`) for HTTP; avoid `:httpoison`, `:tesla`, `:httpc`.
