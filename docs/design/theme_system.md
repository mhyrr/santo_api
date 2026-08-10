# Vin Santo visual system

**Status:** approved direction, being applied across production surfaces.

## Direction

Vin Santo should feel like an enthusiast club with the discipline of a
provenance ledger. The visual sources are period garage ephemera, racing
programs, service stickers, bottle labels, and data plates. The product still
has to carry dates, sources, conflicts, private entries, and long records
without turning those things into decoration.

The name stays **Vin Santo** for the lab. It carries the VIN reading without
excluding cars by transmission or powertrain, and the wine vocabulary has a
real relationship to the product: maker, vintage, origin, condition, and
provenance all matter.

### Mark

The primary mark is the carafe alone. The earlier carafe-and-skid combination
made the motion line look like a stray hose at icon size. Tire arcs belong at
page scale, where they read immediately as evidence of a car being used. The
mark should survive as a one-color favicon. A gas pump is not the primary mark:
it reads as fuel tracking and narrows the product around gasoline. A bottle by
itself reads as an alcohol product.

The shift-gate Unicode glyph is out. If a gate pattern returns later, it can be
an illustration or club patch rather than the identity.

## Visual grammar

- **Ground:** warm label stock is the application default. Asphalt belongs to
  the top bar, media, and deliberate contrast sections; it is not the page
  background. Provenance uses a quieter paper variation of the same family.
- **Blocks:** petrol teal, signal orange, and paper appear as large flat fields,
  not a repeated racing stripe. This avoids borrowing BMW M's livery grammar.
- **Texture:** original skid arcs and tread crops can occupy empty edges, hero
  fields, share cards, and empty states at low contrast. Never put tire texture
  beneath body copy or form controls.
- **Shape:** square blocks with one clipped service-tag corner for actionable
  controls. Small radii are reserved for fields; pills are reserved for
  statuses and avatars.
- **Illustration:** preserve the recognizable shape of a particular car when a
  model is named. A generic abstract silhouette is allowed only as a placeholder.
- **Motion:** 120–180ms response on hover/focus; one restrained rise on page
  entry. Respect reduced-motion preferences.

## Color roles

| Token | Value | Use |
| --- | --- | --- |
| Asphalt | `#141716` | top bar, media, and deliberate contrast |
| Graphite | `#242927` | raised dark panels |
| Bone | `#F2EADB` | primary dark-ground text; light cards |
| Paper | `#DDD3C1` | application ground and provenance panels |
| Signal orange | `#F26B35` | brand action and primary controls |
| Petrol | `#176A75` | secondary blocks, verification, informational fields, timeline markers |
| Track lime | `#B7D63B` | rare illustration accent on asphalt only; never status text on paper |
| Flag red | `#E05243` | conflict, destructive action, failure |
| Muted | `#9C9F97` | secondary dark-ground text |

Orange is interaction. Petrol is verification and information. Red is disagreement or loss.
Those roles do not trade places for decoration.

## Typography

- **Display:** Barlow Condensed ExtraBold Italic. Use for the wordmark, page
  titles, car names, and major numeric statements. It is not a body face.
- **Body/UI:** Barlow Regular and Semibold. Sentence case by default.
- **Codes:** the system monospace stack for VINs, dates, paint codes, source
  IDs, and tabular readings.

The lab uses compatible system fallbacks until the Barlow webfonts and their
OFL license are vendored locally. Production must not load a font from a CDN.

## Application shell

The top bar is universal now that the product has real destinations. It is
compact, sticky, and dark:

- mark + wordmark on the left;
- Garage for the signed-in owner's working space;
- Cars for the complete public directory;
- a persistent car search, by model, marque, VIN, or chassis;
- Add a car as the one high-contrast action;
- Sign in when anonymous;
- a monogram avatar when signed in;
- Settings, operator Bench, and Log out in the avatar menu.

The first avatar is a generated monogram from the immutable handle. Profile
photo storage is not required for the shell to ship.

## Product language

The interface speaks as a place where people keep cars, not as a database
people visit. The underlying registry and claim ledger remain exact technical
terms in code and operator surfaces; they are not the public product voice.

| Internal / earlier copy | Product copy |
| --- | --- |
| Registry | Cars |
| Registry listing | Car directory |
| Stewarded vehicles | Your garage |
| Log an entry | Log an update |
| Current spec | As it sits |
| The record | History & provenance |
| Facts | As built |

"Maintained by" remains on the public car page. Stewardship proves authority
to maintain a log, not legal ownership, and the copy must not collapse that
distinction.

## Information architecture

- `/` — the public club front door. It leads with cars and recent work rather
  than registry machinery. A signed-in member goes to `/garage`.
- `/garage` — authenticated daily-use surface: natural-language intake first,
  then the member's cars and direct car actions.
- `/cars` — the complete searchable public directory.
- `/v/:public_id` — the living car page: story, as-it-sits state, updates, then
  history and provenance.
- `/v/:public_id/updates/:entry_ref` — stable share target for one update and
  the home for reactions and replies.
- `/v/:public_id/log` — the structured review/editor for a new update. It may
  be opened with natural language from the garage.
- `/v/:public_id/events/new` — the authenticated generic event composer for a
  car the member maintains.
- `/events/:public_id` — the public shared occurrence, aggregating public
  participation accounts without an event-wide comment river or scoreboard.

`Garage` is the primary personal noun. `My cars` is too ownership-specific for
a stewardship model, while `Projects` excludes stock, survivor, and daily cars.
Project remains useful descriptive language within a garage.

## Daily-use intake

Adding data is the first task after sign-in. The garage opens with one question:
**What happened with the car?** A member chooses a car and can type or dictate a
sentence. Dictation transcribes into the same text field; it does not create a
second storage or extraction path.

The sentence is parsed into the existing structured composer and shown back as
editable fields before save. Models extract; deterministic code validates,
computes money, and writes claims. Parse failure becomes a plain note containing
the owner's complete words, so the intake never discards a memory or dead-ends.
MCP remains the lower-friction agent path and writes through the same owner
context.

## Social layer

Social interaction attaches to a particular public update, not to the car as a
whole and never to a fact row.

- A reaction is lightweight appreciation. Counts are visible; reactions never
  affect verification, ranking, or record strength.
- A reply is discourse about the update. It is stored outside the claim ledger,
  never folded into facts, current state, or the timeline.
- There is no promote-to-claim shortcut in v1. A correction raised in a reply
  still enters through an ordinary owner or operator claim path.
- Car maintainers cannot remove skeptical replies. Any signed-in member may
  report one; operators may hide or dismiss it. Authors may withdraw their own
  words. The moderation trail is retained.
- Handles are the public author identity. Email addresses are never exposed.

## Component set

Tailwind supplies layout primitives. First-party Phoenix function components
own the product vocabulary and states. No new component library; daisyUI was
removed when the remaining generator surfaces were migrated.

| Component | Use |
| --- | --- |
| Top bar / avatar menu | global wayfinding and account actions |
| Button | one primary action per region; secondary and destructive variants |
| Field / select / toggle | all owner and auth input |
| Status | verified, owner-reported, conflicted, private, pending |
| Car card | browse and garage grids; identity + one useful activity signal |
| Log entry | timeline content, attribution, evidence, share/edit actions |
| Record row | expandable fact, status, source count, evidence detail |
| Metric | mileage, entry count, record strength; never decorative dashboard filler |
| Notice | inline information, warning, refusal, and reconnect state |
| Empty state | next useful action, with optional low-contrast track art |
| Disclosure / menu | secondary detail and compact actions |

Repeated data uses rows and rules by default. A card exists when the whole
object is selectable or the content needs a distinct ground.

## Page families

1. **Public club:** registry, car page, share surfaces. Expressive, editorial,
   and photo-led.
2. **Owner garage:** origination, composer, current spec, links. Same identity,
   larger targets and clearer task hierarchy.
3. **Provenance record:** paper ground, dense rows, restrained color with status
   semantics intact.
4. **Operator bench:** compact data density, full top bar, fewer decorative
   motifs. It should still be recognizably Vin Santo.
5. **Auth/settings:** simple centered task surface inside the shared shell.

## `/theme` acceptance pass

The lab must show the identity, full token palette, type scale, real top-bar
states, avatars, controls and their states, and the three load-bearing domain
objects: car card, log entry, and record row. It should include desktop and
compact shell examples and remain usable at 390px without horizontal overflow.

The 2026-08-09 review pass extends the lab with one cohesive public-car study,
a rich event journal card, a shared-event page, and the generic event composer.
The study deliberately chooses newest-first journal order, a mutable story near
the hero, a desktop current-state rail, and Share without Follow. Greg ratified
those choices for the first production iteration on 2026-08-09. The sample
content remains illustrative; the event persistence contract comes from
`car_page.md`, not from copying the lab's markup into schemas.

The accepted review uses petrol teal as a large field and `Vin Santo` as two
words in prose and the wordmark. The carafe remains the compact mark; it can be
revisited independently without changing the system around it.
