# Free acquisition corpus

*Implementation note, 2 August 2026. This is the first collection run arising
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

`priv/free_acquisition/targets.json` contains only minimum transaction facts,
vehicle identity, and outbound source URLs. Marketplace prose and media are not
copied. Each source page becomes a pointer-only `reference` artifact; its date,
result, currency, and venue become a proposed `event.sale` claim.

Direct auction pages assert their own results. When an index page supplies a
result from another auction house, the index is the asserting party and the
auction house remains the venue. Those are different facts and must not collapse.

The claim's legacy three-field shape means `outcome` absent is a completed sale.
`outcome: not_sold` records an unsuccessful auction appearance, and `price` is
the reported high bid in that case. The checked-in manifest states either
outcome explicitly; the persistence layer omits `sold` to keep existing claim
hashes stable.

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

When only the checked-in transaction spine changed, avoid minting another set
of immutable vPIC retrievals:

```sh
mix santo.acquire.free --skip-providers
```

The command is safe to resume. A target may carry any non-empty number of
transactions. Vehicle identities, source references, and sale claims deduplicate;
a fresh provider request remains a new retrieval event. The operator report
separates materialized targets, provider attempts, skips, and failures so partial
runs are visible rather than laundered into success.

Both dry and live runs print the longitudinal result and each repeat price path.
The 2 August manifest contains:

- 40 auction events on 30 exact VIN or chassis identities;
- 37 completed sales and three unsuccessful appearances with reported high bids;
- 10 vehicles with repeat auction appearances;
- seven vehicles with two or more completed sales;
- six vehicles observed across more than one auction venue.

The six venues-crossed records span Bring a Trailer paired with Mecum, Broad
Arrow, or RM. Secondary index evidence is retained only as its outbound pointer;
it is not promoted to first-party auction evidence.

## Next measurement

Use two of the repeat-sale records as the first public dossier walkthrough: one
same-venue path and one cross-venue path. That will test whether a buyer can see
identity, chronology, result status, evidence source, and unresolved conflicts
without reading registry internals. Expansion beyond 30 cars should wait until
that surface makes the persistence legible.
