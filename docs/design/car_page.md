# Public car page — working design

*Status: design pass, 2026-08-09. The hierarchy below is proposed, not
ratified. Small corrections to the existing page may ship independently; the
page reconstruction waits for Greg's review.*

## The job

`/v/:public_id` is the canonical page for one car. It has to work as three
things without looking like three products bolted together:

1. **Showpiece** — the page an owner is proud to send somebody.
2. **Living build thread** — dated work, drives, plans, photos, and witnessed
   discussion.
3. **Durable record** — current state, factory provenance, evidence, gaps, and
   conflicts.

The order matters. The car and its story lead; the documentary record explains
why the page can be trusted.

## What the references actually contribute

### Rennlist and phpBB-style build threads

The useful unit is a post, not a database event. A strong opening post says
where the car came from and what the owner wants to make of it. Later posts mix
prose, photos, work performed, discoveries, plans, and replies. Dates,
attribution, edits, and public witnesses make the history credible. Long-running
threads also expose the failure of the format: a newcomer must read dozens of
pages to learn what the car is now.

References:

- [My 964 C2 Transformation Build Thread](https://rennlist.com/forums/964-forum/904951-my-964-c2-transformation-build-thread.html)
- [My 1967 912 Build Thread](https://rennlist.com/forums/912-forum/794728-my-1967-912-build-thread.html)
- [phpBB viewtopic feature set](https://www.phpbb.com/community/viewtopic.php?t=104463)

### Bring a Trailer

BaT makes an unfamiliar car legible immediately: strong photography, a precise
title, a short summary, an essentials block, candid defects, documentation, and
discussion on one canonical page. Its weakness for Vin Santo is temporal: an
auction is a frozen moment assembled for a sale. The car's life before and after
that moment sits elsewhere.

References:

- [2007 Porsche Cayman S listing](https://bringatrailer.com/listing/2007-porsche-cayman-s-32/)
- [How BaT works](https://bringatrailer.com/how-bat-works/)

## Proposed hierarchy

The first screen answers **what is this car now, why is it interesting, and who
is keeping it?** The journal then answers **how did it get here?** The record at
the bottom answers **what backs the story?**

```text
Car page (/v/:public_id)
├── Showpiece hero
│   ├── Owner-selected hero photo or typographic fallback
│   ├── Current-build title and one-line story
│   ├── Maintainer, location if shared, odometer, last update
│   └── Log update / Follow / Share
├── In-page navigation
│   ├── Story
│   ├── Journal
│   ├── As it sits
│   └── Provenance
├── Owner story
│   ├── Mutable opening-post prose
│   └── Compact photo strip
├── Build-at-a-glance
│   ├── Current engine / transmission
│   ├── Suspension / wheels / brakes / exterior
│   └── Diverged-from-factory markers
├── Journal
│   ├── Rich owner posts
│   ├── Compact registry events
│   ├── Plans visibly marked as intent
│   └── Appreciation, reply count, share, permalink
├── Gallery and elsewhere
│   ├── Public owner photos
│   └── Forum / Instagram / YouTube / gallery links
└── History & provenance
    ├── Factory facts and disagreements
    ├── Sources and public evidence
    └── Record coverage statement
```

## Desktop shape

```text
┌──────────────────────────────────────────────────────────────────────┐
│ HERO PHOTO                                                    SHARE │
│ 2007 PORSCHE CAYMAN                                                │
│ Signal Green, built to be driven · maintained by @mhyrr           │
│ 42,480 mi · updated 4 Aug                     [LOG AN UPDATE]       │
└──────────────────────────────────────────────────────────────────────┘
  STORY        JOURNAL        AS IT SITS        PROVENANCE

┌──────────────────────────────────────┐  ┌──────────────────────────┐
│ OWNER STORY + RECENT PHOTOS          │  │ AS IT SITS               │
└──────────────────────────────────────┘  │ engine / wheels / brakes │
┌──────────────────────────────────────┐  │ modified from factory    │
│ JOURNAL POST                         │  └──────────────────────────┘
│ photo / date / narrative / facts     │
│ ♥ 12   3 replies   share             │
├──────────────────────────────────────┤
│ compact external or registry event   │
└──────────────────────────────────────┘

                         HISTORY & PROVENANCE
```

The right rail is a summary, not a second navigation system. It should stop
being sticky before the provenance section so it never competes with the
documentary record.

## Journal grammar

The current timeline makes every entry roughly equal. That is accurate and
visually dead. The page needs two deliberate weights:

- **Owner post:** title or first sentence, narrative, photos, useful structured
  details, author/date, appreciation, reply count, and permalink. This is the
  build-thread unit.
- **Record event:** auction sale, imported service line, mileage observation,
  or other externally sourced occurrence. Compact, source-forward, and visually
  quieter. It is part of the car's history without impersonating the owner's
  voice.

Comments remain attached to one update. The car page shows the count and perhaps
the most recent reply; the update permalink holds the full conversation. A
car-wide comment river would lose the thing being discussed and recreate forum
thread pagination without the forum.

## Ordering

The hero and current-state summary make the present legible first. The journal
can therefore default newest-first for returning visitors without forcing a
newcomer to infer the beginning. A **Start at the beginning** control reverses
the journal order and lands on the opening post.

This is the first unresolved product call in the pass: a traditional build
thread defaults oldest-first; an active car profile defaults newest-first.

## Photo requirement

The page cannot become a showpiece through typography alone. The next build
needs:

- an owner-selected hero image;
- public serving for public owner-photo artifacts;
- derived thumbnails and responsive image sizes;
- photo ordering and alt text;
- a typographic fallback for cars with no public images.

Marketplace photos are never copied into this gallery. External listings stay
links or evidence pointers according to their rights profile.

## Event-centered journal

*Opened 2026-08-09. Working design, not ratified.*

An outing is not merely a larger timeline entry. **The shared event is the
coordinate; the car's participation is the journal object.** "WDCR 2026 Event
2" should exist once as a place, time, organizer, and field. The Cayman's
story, setup, runs, video, and result are its participation in that occurrence.
Another member's Corvette gets a separate participation attached to the same
event. The event page can then show who was there and what they did without
making any one owner's post the canonical account of the day.

This requires a real object outside the claim ledger. `entry_ref` remains what
it was designed to be: a presentation grouping tag for claims, not a lifecycle
object and not a shared-event identity. The existing `event.outing` claim can
state that this car attended and can carry the owner's summary; it cannot serve
as the occurrence every other car joins.

### The generic core

The first pass should resist event-type schemas. We will never enumerate every
thing somebody records at an autocross, rally, track day, tour, meet, show, or
photoshoot, and a table per discipline would encode our guesses as product
constraints.

```text
Event occurrence
├── title, time/range, place text, description, tags
└── participation(s)
    ├── member + car
    ├── journal text
    ├── tags
    ├── owner-defined details: label + value
    └── photos, video, links, files
```

That is the entire universal model. A detail is deliberately opaque and
owner-named:

```text
Class          S2
Best run       44.182 +1
Tire pressure  32F / 30R hot
Camber         -3.0° front
Photographer   @handle
Route          Skyline Drive to Sperryville
```

Owners may add, remove, repeat, and order details. The interface calls them
**details**, not fields or metrics: both label and value are chosen by the
owner, and the value remains display text. Tags handle discovery and loose
grouping; details carry the specifics of this participation. A file or link
gets an owner-written label, so a SoloStorm export, onboard video, route map,
official result sheet, and photo gallery all use the same attachment mechanic.

No `instructors`, `runs`, `classes`, `setups`, `awards`, `routes`, or
`photographers` tables exist in this first model. If three real workflows need
the same behavior—not merely the same label—we can pull a typed extension out
of the generic content then. Integrations may also interpret their own
artifacts without changing the event's universal shape.

The caveat is intentional: arbitrary details can be displayed and searched as
text, but Vin Santo cannot safely calculate standings, compare tire pressures,
or build class leaderboards from them. Those features require a typed adapter
or an earned extension later. V1 is a social record of the day, not timing and
scoring software.

### Time is part of the product model

A single `scope_date` still cannot carry this surface. Three times must not
collapse:

1. **Occurrence time** — when the event was scheduled in the venue's local
   timezone; date-only and multi-day events remain possible without inventing
   midnight.
2. **Detail time, when supplied** — an owner may optionally date or time a
   detail or attachment, but ordering is sufficient when precision is unknown.
3. **Record time** — when the owner uploaded or amended the account, which may
   be months after the event.

Event identity must survive a date, title, or venue correction, so it keys on
its own stable public ID rather than a title/date composite. "WDCR 2026" and
"Event 2" can live naturally in the title, tags, or owner-defined details. A
separate series hierarchy waits until real use demonstrates that grouping
events by tags is insufficient.

Owner-defined event details are deliberately separate from `current_state`.
Thirty-two psi at an autocross is an event note, not the car's present tire
pressure. A camber change tried for one day is not a durable build modification
unless the owner separately records that it stayed on the car. This proposes a
narrow correction to
`owner_surface.md` §2/§2b, whose original autocross example treated "tried 3
degrees camber" as a `sets` delta: *tried for this event* belongs to the
event's owner-defined details; *changed the car and left it that way* remains a
modification/current-state delta.

### The two connected pages

The car page gets a rich event card in its journal:

```text
19 APR 2026  /  WDCR 2026 EVENT 2                  SUMMIT POINT
AUTOCROSS · #37 · S2

Owner's account of the day, a lead photo or video, and whichever details the
owner thought mattered.

6 details   12 photos   3 files   8 replies
[OUR DAY]                                         [VIEW THE EVENT →]
```

The title and **View the event** link to `/events/:public_id`, the shared hub.
**Our day** opens the existing stable update permalink at
`/v/:public_id/updates/:entry_ref`, expanded into the full participation
dossier: story, details, attachments, media, and the existing witnessed
conversation. There is no third participation URL in the first pass.

The event hub begins with title, date/range, venue, organizer, source status,
and lead media. Its content adapts to what exists rather than showing empty
tabs:

- **People & cars** — public Vin Santo participations, grouped by car, with a
  useful excerpt and the owner's chosen details.
- **What happened** — the participants' public accounts and attachments,
  without pretending their differently named details form one scoreboard.
- **Media** — public event-linked photos and videos with owner/photographer
  attribution.
- **About** — time, place, description, source links, and event provenance.

An event with one Vin Santo car is still valid. As more owners attach their
participations, the page becomes the social index for that day. Comments stay
on each car's account, where the subject is clear; the shared event does not
gain a contextless comment river.

The only new parent surface is `/events` for discovery and archive. A series,
club, venue, or calendar page waits until tags and search prove inadequate.

### Joining, duplicates, and source honesty

When an owner says "WDCR Event 2," the composer searches existing occurrences
by title, date, and place before offering to create one. A new occurrence
starts as community-created. Similar names and dates produce suggestions,
never an automatic merge; an operator can merge duplicates later without
rewriting participation permalinks.

The event and every imported attachment expose their source independently:

- organizer-supplied or imported event details;
- community-created event details;
- official documents or files;
- owner-authored text, tags, and details.

Public entry lists can identify a field, but they do not automatically create
Vin Santo people or car profiles. A member explicitly attaches their account
and car. Organizer authority and event-page moderation are later seams; an
event creator cannot delete another owner's participation.

### Data and media ingestion

Vin Santo accepts a file or link without first understanding it. A SoloStorm
export, official result sheet, GPX route, video, or photo set appears as an
attributed attachment with the owner's label. The original artifact is
preserved; its usefulness does not wait on a parser.

An integration may later add an adapter-specific presentation beneath the
attachment. Computed metrics come from deterministic parsers. An LLM may help
write narrative, suggest tags, or propose owner-editable details; it never
computes timing, standings, pressure deltas, or telemetry-derived values.

Landscape references:

- [SoloStorm user guide](https://www.petreldata.com/support/solostorm-circuitstorm-user-guide/)
- [SoloStorm export FAQ](https://www.petreldata.com/support/solostorm-faq-frequently-asked-questions/)
- [MotorsportReg REST API](https://api.motorsportreg.com/)
- [SCCA National Solo live timing example](https://sololive.scca.com/26LVPS2/index.php)

## Open decisions for the walk

1. **Default journal order:** newest-first with *Start at the beginning*, or
   oldest-first like a forum thread?
2. **Owner story:** one mutable opening paragraph near the hero, or a pinned
   first journal post that remains immutable?
3. **Current-state rail:** show the six folded traits persistently on desktop,
   or keep the first pass single-column and let imagery carry the showpiece?
4. **Follower action:** ship *Follow this car* with notifications in this pass,
   or make Share the only audience action until notification policy is designed?
5. **Event attachment:** may any member create a community occurrence and attach
   their own car, with operator merge later? Recommendation: yes; organizer-only
   creation would kill the ten-second logging path.
6. **Future attendance:** should a public plan automatically announce that an
   owner will be at a future event? Recommendation: event plans keep the existing
   entry visibility control, but Vin Santo never publishes live location or
   implies checked-in attendance from a plan.
7. **First typed extension:** none by default. Let real event posts accumulate,
   then promote a repeated workflow only when generic details and attachments
   fail to support something owners are actually trying to do.

## Deliberately excluded

- Auction mechanics, valuation, bidding, and watchers. BaT contributes
  presentation and discussion patterns, not its transaction model.
- Car-wide free-floating comments.
- Owner moderation of other people's replies.
- Popularity-based ranking or verification.
- Scraped forum posts, auction prose, or marketplace photography.
