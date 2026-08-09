defmodule SantoApiWeb.ThemeLive do
  @moduledoc """
  The visual-system reference for the identity and production components.
  """
  use SantoApiWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Theme lab")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} chrome={false}>
      <div id="theme-page" class="club-shell">
        <Layouts.topbar id="theme-topbar" current_scope={@current_scope} />

        <section id="theme-identity" class="club-home-hero">
          <img src={~p"/images/tire-arcs.svg"} alt="" class="club-home-tracks" />
          <div class={["club-wrap club-hero-grid"]}>
            <div class="club-hero-copy">
              <p class="club-kicker club-kicker-paper">Identity study 01 · provenance garage</p>
              <h1 class={["club-wordmark club-wordmark-hero club-display-dark"]}>Vin Santo</h1>
              <p class="club-lede">A living record for cars that get used.</p>
              <p class="club-body-copy club-ink-muted">
                Log the work, the miles, the parts, and the proof. Share the car as it sits
                today without losing the record of what it was.
              </p>
              <div class="club-actions">
                <button
                  id="theme-primary-action"
                  type="button"
                  class={["club-button club-button-primary"]}
                >
                  Add your car
                </button>
                <button type="button" class={["club-button club-button-secondary"]}>See the cars</button>
              </div>
            </div>

            <aside id="theme-mark-study" class="club-mark-study" aria-labelledby="mark-study-heading">
              <p id="mark-study-heading" class={["club-kicker club-kicker-dark"]}>Compact mark</p>
              <img
                src={~p"/images/vin-santo-mark.svg"}
                alt="Vin Santo carafe mark"
                class="club-mark-large"
              />
              <p class="club-mark-note">
                The carafe stays legible at icon size. Tire arcs live at page scale, where
                they read as motion instead of a stray line.
              </p>
            </aside>
          </div>
        </section>

        <section id="theme-foundations" class={["club-section club-section-paper"]}>
          <div class="club-wrap">
            <header class="club-section-heading">
              <p class={["club-kicker club-kicker-paper"]}>01 · Foundations</p>
              <h2 class={["club-display club-display-dark"]}>Color with a job</h2>
              <p class={["club-section-intro club-ink-muted"]}>
                Large fields provide the richness. Status colors keep one meaning across the club,
                owner, provenance, and operator surfaces.
              </p>
            </header>

            <div id="theme-swatches" class="club-swatch-grid">
              <.swatch name="Asphalt" value="#141716" class="club-swatch-asphalt" />
              <.swatch name="Bone" value="#F2EADB" class="club-swatch-bone" dark?={true} />
              <.swatch name="Signal orange" value="#F26B35" class="club-swatch-orange" dark?={true} />
              <.swatch name="Petrol" value="#176A75" class="club-swatch-petrol" />
              <.swatch name="Track lime" value="#B7D63B" class="club-swatch-lime" dark?={true} />
              <.swatch name="Flag red" value="#E05243" class="club-swatch-red" dark?={true} />
            </div>

            <div id="theme-type" class="club-type-grid">
              <article class="club-type-display">
                <p class="club-kicker">Display · condensed extra bold italic</p>
                <p class={["club-display club-type-sample"]}>1985 Datsun 280Z</p>
                <p class={["club-display club-type-sample club-orange"]}>LS1 · 18×11 · driven</p>
              </article>
              <article class="club-type-body">
                <p class={["club-kicker club-kicker-paper"]}>Body and interface</p>
                <p class="club-body-sample">
                  Keep long copy calm. The type carries service notes, ownership stories, and
                  evidence without dressing every sentence for a starting grid.
                </p>
                <p class="club-code-sample">WP0AC2A97JS176473 · PAINT 226 · 2026-08-09</p>
              </article>
            </div>
          </div>
        </section>

        <section id="theme-navigation" class={["club-section club-section-dark"]}>
          <div class="club-wrap">
            <header class="club-section-heading">
              <p class="club-kicker">02 · Application shell</p>
              <h2 class="club-display">One bar, real destinations</h2>
              <p class={["club-section-intro club-muted"]}>
                The live example at the top reflects the current session. These two states fix the
                information architecture before we move it into the shared layout.
              </p>
            </header>

            <div class="club-shell-studies">
              <div class="club-shell-study">
                <p class="club-kicker">Anonymous</p>
                <Layouts.topbar id="theme-topbar-anonymous" embedded?={true} />
              </div>
              <div class="club-shell-study">
                <p class="club-kicker">Signed in</p>
                <Layouts.topbar
                  id="theme-topbar-signed-in"
                  handle="grolsen"
                  embedded?={true}
                  operator?={true}
                />
              </div>
            </div>

            <div id="theme-avatars" class="club-avatar-study">
              <p class="club-kicker">Handle-first avatars</p>
              <div class="club-avatar-row">
                <Layouts.avatar handle="grolsen" size={:large} />
                <Layouts.avatar handle="flat6" size={:large} tone={:petrol} />
                <Layouts.avatar handle="air.cooled" size={:large} tone={:lime} />
                <div>
                  <p class="club-avatar-title">No upload required</p>
                  <p class={["club-muted club-avatar-copy"]}>
                    The immutable handle creates a useful fallback now. Photos can arrive with a
                    real profile surface later.
                  </p>
                </div>
              </div>
            </div>
          </div>
        </section>

        <section id="theme-garage" class={["club-section club-section-paper"]}>
          <div class="club-wrap">
            <header class="club-section-heading">
              <p class={["club-kicker club-kicker-paper"]}>03 · Daily surface</p>
              <h2 class={["club-display club-display-dark"]}>Intake before dashboard</h2>
              <p class={["club-section-intro club-ink-muted"]}>
                The signed-in home opens with the question that earns repeat use. Voice and text
                share one read-back; the member's cars sit immediately below it.
              </p>
            </header>

            <article id="theme-garage-intake" class="club-theme-intake">
              <div>
                <p class="club-kicker">Your garage</p>
                <h3 class="club-display">What happened with the car?</h3>
                <p>Say it normally. Nothing reaches the record until the fields look right.</p>
              </div>
              <div class="club-theme-intake-form">
                <label class="club-field-label" for="theme-garage-car">Which car?</label>
                <select id="theme-garage-car" class="club-input">
                  <option>1985 Datsun 280Z</option>
                </select>
                <label class="club-field-label" for="theme-garage-words">What happened?</label>
                <textarea id="theme-garage-words" class="club-input club-textarea" rows="3">Filled it yesterday — 13.1 gallons at $5.15, 48,291 miles.</textarea>
                <div class="club-dictation-actions">
                  <button type="button" class="club-voice-button">
                    <.icon name="hero-microphone" class="size-5" /> Speak it
                  </button>
                  <span class="club-dictation-status">Voice fills this same box.</span>
                </div>
                <button type="button" class="club-button club-button-primary">Review the update</button>
              </div>
            </article>
          </div>
        </section>

        <section id="theme-controls" class={["club-section club-section-petrol"]}>
          <div class="club-wrap">
            <header class="club-section-heading">
              <p class="club-kicker">04 · Controls</p>
              <h2 class="club-display">Flat, quick, obvious</h2>
            </header>

            <div class="club-control-grid">
              <article class="club-control-panel">
                <h3 class="club-control-title">Actions</h3>
                <div class="club-button-stack">
                  <button type="button" class={["club-button club-button-primary"]}>Save the entry</button>
                  <button type="button" class={["club-button club-button-secondary"]}>Add evidence</button>
                  <button type="button" class={["club-button club-button-quiet"]}>Cancel</button>
                  <button type="button" class={["club-button club-button-danger"]}>Remove entry</button>
                </div>
              </article>

              <article class="club-control-panel">
                <h3 class="club-control-title">Fields</h3>
                <div class="club-field-stack">
                  <label for="theme-odometer" class="club-field-label">Odometer</label>
                  <div class="club-field-unit">
                    <input id="theme-odometer" type="text" value="48,291" class="club-field" />
                    <span>mi</span>
                  </div>
                  <label for="theme-entry-type" class="club-field-label">Entry type</label>
                  <select id="theme-entry-type" class="club-field">
                    <option>Service</option>
                    <option>Modification</option>
                    <option>Drive</option>
                  </select>
                  <label class="club-toggle-row">
                    <input type="checkbox" checked class="club-toggle" />
                    <span>
                      <strong>Public entry</strong>
                      <small>Visible on the car's record.</small>
                    </span>
                  </label>
                </div>
              </article>

              <article class="club-control-panel">
                <h3 class="club-control-title">Status</h3>
                <div class="club-status-stack">
                  <.status tone={:verified}>Verified</.status>
                  <.status tone={:owner}>Owner reported</.status>
                  <.status tone={:conflict}>Conflicted</.status>
                  <.status tone={:private}>Private</.status>
                  <.status tone={:pending}>Pending review</.status>
                </div>
                <div class={["club-notice club-notice-warning"]}>
                  <.icon name="hero-exclamation-triangle" class="size-5" />
                  <p>The decoded model disagrees with an evidence-backed claim.</p>
                </div>
              </article>
            </div>
          </div>
        </section>

        <section id="theme-domain-components" class={["club-section club-section-asphalt"]}>
          <div class="club-wrap">
            <header class="club-section-heading">
              <p class="club-kicker">05 · Product components</p>
              <h2 class="club-display">The car stays visible</h2>
              <p class={["club-section-intro club-muted"]}>
                These carry the product. Generic cards and dashboard tiles do not.
              </p>
            </header>

            <div class="club-domain-grid">
              <article id="theme-car-card" class="club-car-card">
                <div class="club-car-art" aria-hidden="true">
                  <svg viewBox="0 0 620 240">
                    <path d="M78 165c22-8 57-13 96-16l83-74c12-10 26-15 42-15h102c19 0 34 6 47 20l58 64 48 9c13 3 21 14 21 27v9H55v-4c0-10 9-17 23-20Z" />
                    <path d="m212 144 66-58c7-6 15-9 25-9h82c13 0 24 4 33 13l45 54H212Z" />
                    <circle cx="172" cy="186" r="39" />
                    <circle cx="468" cy="186" r="39" />
                    <circle cx="172" cy="186" r="19" />
                    <circle cx="468" cy="186" r="19" />
                  </svg>
                </div>
                <div class="club-car-card-copy">
                  <p class="club-kicker">Current build</p>
                  <h3 class={["club-display club-card-title"]}>1985 Datsun 280Z</h3>
                  <p class="club-card-spec">LS1 swap · bronze 18×11 · street / track</p>
                  <div class="club-card-meta">
                    <span class="club-code">48,291 mi</span>
                    <span class="club-code">23 entries</span>
                    <.status tone={:owner}>grolsen</.status>
                  </div>
                </div>
              </article>

              <article id="theme-log-entry" class="club-log-entry">
                <div class="club-log-rail" aria-hidden="true"></div>
                <div>
                  <div class="club-entry-head">
                    <p class={["club-code club-muted"]}>AUG 09 · 48,291 MI</p>
                    <.status tone={:owner}>Owner reported</.status>
                  </div>
                  <h3 class="club-entry-title">Back from alignment, finally sitting right.</h3>
                  <p class="club-entry-copy">
                    Added a half degree of front camber and backed the rear toe down. The car is
                    calmer at speed and stopped eating the inside shoulder.
                  </p>
                  <dl class="club-entry-facts">
                    <div>
                      <dt>Shop</dt><dd>Flat Six Works</dd>
                    </div>
                    <div>
                      <dt>Cost</dt><dd>$240</dd>
                    </div>
                    <div>
                      <dt>Evidence</dt><dd>Invoice + 2 photos</dd>
                    </div>
                  </dl>
                  <div class="club-entry-actions">
                    <button type="button">Love · 12</button>
                    <button type="button">Reply · 3</button>
                    <button type="button">Share</button>
                  </div>
                </div>
              </article>
            </div>

            <article id="theme-record-row" class="club-record-panel">
              <div class="club-record-heading">
                <div>
                  <p class={["club-kicker club-kicker-paper"]}>History &amp; provenance</p>
                  <h3 class={["club-display club-display-dark club-record-title"]}>
                    Factory and provenance
                  </h3>
                </div>
                <p class="club-record-strength"><strong>62%</strong> document-backed</p>
              </div>
              <details open class="club-record-row">
                <summary>
                  <span class="club-record-label">Paint</span>
                  <span class="club-record-value">Linden Green · 226</span>
                  <.status tone={:verified}>Verified</.status>
                </summary>
                <div class="club-record-detail">
                  <dl>
                    <div>
                      <dt>Asserted by</dt><dd>Porsche factory data</dd>
                    </div>
                    <div>
                      <dt>Applicable</dt><dd>At production</dd>
                    </div>
                    <div>
                      <dt>Evidence</dt><dd>Vehicle data sticker</dd>
                    </div>
                  </dl>
                </div>
              </details>
              <details class="club-record-row">
                <summary>
                  <span class="club-record-label">Model</span>
                  <span class="club-record-value">911 GT3 Touring</span>
                  <.status tone={:conflict}>Conflicted</.status>
                </summary>
              </details>
            </article>
          </div>
        </section>

        <section id="theme-usage" class={["club-section club-section-paper"]}>
          <div class={["club-wrap club-usage-grid"]}>
            <div>
              <p class={["club-kicker club-kicker-paper"]}>06 · Usage rules</p>
              <h2 class={["club-display club-display-dark"]}>A component earns its ground</h2>
            </div>
            <ul class="club-rules">
              <li>
                <strong>Rows</strong> for repeated facts, entries, sources, and dense bench data.
              </li>
              <li><strong>Cards</strong> when the whole car or object is selectable.</li>
              <li><strong>Paper</strong> for provenance and evidence detail.</li>
              <li><strong>Texture</strong> in unused edges, never beneath a task.</li>
              <li><strong>Italic display</strong> for identity and hierarchy, never paragraphs.</li>
            </ul>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :class, :string, required: true
  attr :dark?, :boolean, default: false

  defp swatch(assigns) do
    ~H"""
    <article class={["club-swatch", @class, @dark? && "club-swatch-dark"]}>
      <p>{@name}</p>
      <code>{@value}</code>
    </article>
    """
  end

  attr :tone, :atom,
    values: [:verified, :owner, :conflict, :private, :pending],
    required: true

  slot :inner_block, required: true

  defp status(assigns) do
    ~H"""
    <span class={["club-status", "club-status-#{@tone}"]}>
      {render_slot(@inner_block)}
    </span>
    """
  end
end
