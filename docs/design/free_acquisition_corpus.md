# Free acquisition corpus

*Implementation note, 1 August 2026. This is the first collection run arising
from `docs/research/porsche_ferrari_public_data_universe.md`.*

## Decision

Start with a checked-in qualification manifest and materialize it into the local
registry. Do not put external records in `seeds.exs`: seeds define application
state and run during setup/reset, while source acquisitions are dated evidence
events that need provenance, retry behavior, and an operator report.

The first cohort is 30 auction-visible collector cars:

- 10 air-cooled 911s;
- 10 vintage Ferraris with pre-standard chassis identities;
- 10 limited-production Porsche and Ferrari GT cars.

This is a transaction-selected qualification set, not a fleet sample and not yet
a coverage denominator. Its job is to exercise the identity and evidence paths
on cars whose records buyers will plausibly revisit.

## Storage and rights boundary

`priv/free_acquisition/targets.json` contains only the minimum transaction fact,
vehicle identity, and an outbound source URL. Marketplace prose and media are not
copied. Each source page becomes a pointer-only `reference` artifact; its sale
date, result, currency, and venue become a proposed `event.sale` claim attributed
to the venue.

Applicable VINs are then queried through the free NHTSA vPIC provider. Each
retrieval is an immutable `api_snapshot`, even when successive response payloads
are identical. Provider claims stay proposed. Pre-VIN chassis targets correctly
skip vPIC.

Ferrari is not currently a Santo decode adapter. Reviewed `ZFF` VINs and Ferrari
pre-VIN chassis numbers may therefore create identity-only vehicle rows; they do
not emit Vin Santo factory claims. vPIC or later artifacts supply proposed facts.

## Operation

Validate and inspect the cohort without Postgres or network access:

```sh
mix santo.acquire.free --dry-run
mix santo.acquire.free --dry-run --cohort limited_gt --limit 5
```

Materialize references, sale claims, and applicable free-provider snapshots:

```sh
mix ecto.migrate
mix santo.acquire.free
```

The command is safe to resume. Vehicle identities, source references, and sale
claims deduplicate; a fresh provider request remains a new retrieval event. The
operator report separates materialized targets, provider attempts, skips, and
failures so partial runs are visible rather than laundered into success.

## Next measurement

The next useful report is repeat-sale persistence inside these three families:
distinct chassis with two or more sale events, source coverage per chassis, and
the fraction of selected auction transactions attached to a persistent record.
Raw vehicle count remains a secondary metric.
