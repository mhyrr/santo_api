defmodule SantoApiWeb.ThemeLive do
  @moduledoc """
  The visual-system reference for the identity and production components.
  """
  use SantoApiWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    intake_form =
      to_form(
        %{
          "text" => "Filled it yesterday — 13.1 gallons at $5.15, 48,291 miles."
        },
        as: :theme_intake
      )

    event_form =
      to_form(
        %{
          "event" => "WDCR 2026 AX Championship Event #2",
          "journal" =>
            "The car finally rotated without asking twice. We softened the rear bar after lunch and found the balance I had been chasing.",
          "tags" => "autocross, WDCR, Waldorf",
          "detail_1_label" => "Best run",
          "detail_1_value" => "44.182 +1",
          "detail_2_label" => "Class",
          "detail_2_value" => "S2",
          "detail_3_label" => "Change tried",
          "detail_3_value" => "Rear bar one step softer",
          "attachment_label" => "Run 6 · onboard video",
          "attachment_url" => "https://video.example/run-6",
          "file" => nil,
          "visibility" => "public"
        },
        as: :event_update
      )

    theme_car = %{
      id: "theme-long-name",
      public_id: "theme-long-name",
      marque: "Mercedes-Benz",
      identity: "2025 · VIN on file",
      title: "Mercedes-AMG GT 63 S E Performance",
      spec: "Graphite grey · grand touring setup · driven often",
      latest: "First 1,000-mile service and a long way home.",
      odometer: %{miles: 1_184},
      entries: 7,
      steward: "longwayhome"
    }

    {:ok,
     socket
     |> assign(:page_title, "Theme lab")
     |> assign(:intake_form, intake_form)
     |> assign(:event_form, event_form)
     |> assign(:theme_car, theme_car)}
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
                <Layouts.avatar handle="air.cooled" size={:large} />
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
              <.form for={@intake_form} id="theme-garage-form" class="club-theme-intake-form">
                <div id="theme-garage-context" class="club-intake-car-context">
                  <span>Adding to</span>
                  <strong>1985 Datsun 280Z</strong>
                </div>
                <div id="theme-garage-dictation" phx-hook=".ThemeDictation" phx-update="ignore">
                  <.input
                    field={@intake_form[:text]}
                    type="textarea"
                    label="What happened?"
                    rows="3"
                  />
                  <div class="club-dictation-actions">
                    <button
                      type="button"
                      id="theme-voice-button"
                      class="club-voice-button"
                      aria-pressed="false"
                      aria-label="Dictate update"
                      title="Dictate update"
                    >
                      <.icon name="hero-microphone" class="size-5" />
                      <span class="sr-only">Dictate update</span>
                    </button>
                    <span id="theme-voice-status" class="sr-only" aria-live="polite">
                      Dictation is available.
                    </span>
                  </div>
                </div>
                <button type="button" class="club-button club-button-primary">Review the update</button>
              </.form>
            </article>
          </div>
        </section>

        <.car_page_study />
        <.shared_event_study />
        <.event_composer_study form={@event_form} />

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
              <.car_card id="theme-car-card" row={@theme_car} />

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
                    Factory details
                  </h3>
                </div>
                <p class="club-record-strength"><strong>5 of 8</strong> details verified</p>
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
                      <dt>Source</dt><dd>Porsche factory data</dd>
                    </div>
                    <div>
                      <dt>Date</dt><dd>At production</dd>
                    </div>
                    <div>
                      <dt>Backed by</dt><dd>Vehicle data sticker</dd>
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

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ThemeDictation">
        export default {
          mounted() {
            this.button = this.el.querySelector("#theme-voice-button")
            this.status = this.el.querySelector("#theme-voice-status")
            this.textarea = this.el.querySelector("textarea")
            const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition

            if (!Recognition) {
              this.button.hidden = true
              this.status.textContent = "This browser does not offer dictation."
              return
            }

            this.recognition = new Recognition()
            this.recognition.continuous = true
            this.recognition.interimResults = true
            this.recognition.lang = document.documentElement.lang || "en-US"
            this.listening = false
            this.baseText = ""
            this.button.addEventListener("click", () => this.toggle())

            this.recognition.onstart = () => {
              this.listening = true
              this.baseText = this.textarea.value.trim()
              this.button.setAttribute("aria-pressed", "true")
              this.setButtonLabel("Stop dictation")
              this.status.textContent = "Listening…"
            }

            this.recognition.onresult = event => {
              let transcript = ""
              for (let i = 0; i < event.results.length; i++) {
                transcript += event.results[i][0].transcript
              }
              const separator = this.baseText && transcript ? " " : ""
              this.textarea.value = `${this.baseText}${separator}${transcript}`.trim()
              this.textarea.dispatchEvent(new Event("input", {bubbles: true}))
            }

            this.recognition.onend = () => {
              this.listening = false
              this.button.setAttribute("aria-pressed", "false")
              this.setButtonLabel("Dictate update")
              this.status.textContent = "Transcript ready."
            }
          },

          setButtonLabel(label) {
            this.button.querySelector("span").textContent = label
            this.button.setAttribute("aria-label", label)
            this.button.title = label
          },

          toggle() {
            if (this.listening) this.recognition.stop()
            else this.recognition.start()
          },

          destroyed() {
            if (this.recognition && this.listening) this.recognition.stop()
          }
        }
      </script>
    </Layouts.app>
    """
  end

  defp car_page_study(assigns) do
    ~H"""
    <section id="theme-car-page-study" class="theme-study theme-car-study">
      <div class="club-wrap">
        <header class="theme-study-heading">
          <div>
            <p class="club-kicker club-kicker-paper">04 · Public car page</p>
            <h2 class="club-display club-display-dark">The car earns the first screen</h2>
          </div>
          <p>
            The car comes first, followed by the owner’s journal, its current setup, and the
            history underneath it.
          </p>
        </header>

        <article class="theme-car-page" aria-label="Recommended public car page composition">
          <header id="theme-car-hero" class="theme-car-hero">
            <div class="theme-car-hero-copy">
              <p class="club-kicker">2007 · 987.1 · WP0AB29827U782968</p>
              <h3>2007 Porsche Cayman S</h3>
              <p class="theme-car-storyline">
                The back-road car I wanted when I was twenty, kept honest and driven hard.
              </p>
              <p class="theme-car-maintainer">
                Maintained by <strong>@grolsen</strong> · Frederick, Maryland
              </p>
              <dl class="theme-car-hero-metrics">
                <div>
                  <dt>Odometer</dt>
                  <dd>48,291 <span>mi</span></dd>
                </div>
                <div>
                  <dt>Last update</dt>
                  <dd>Aug 9</dd>
                </div>
              </dl>
              <div class="theme-car-hero-actions">
                <.button href="#theme-event-composer" variant="primary">Log an update</.button>
                <.button href="#theme-car-page-study" variant="secondary">
                  <.icon name="hero-arrow-up-on-square" class="size-4" /> Share
                </.button>
              </div>
            </div>

            <div class="theme-car-hero-media" aria-label="Signal green Porsche Cayman illustration">
              <img src={~p"/images/tire-arcs.svg"} alt="" class="theme-car-tracks" />
              <.cayman_art />
              <p><span>Hero study</span> Owner-selected media fills this field in production</p>
            </div>
          </header>

          <nav class="theme-car-nav" aria-label="Car page sections">
            <a href="#theme-owner-story">Story</a>
            <a href="#theme-journal">Journal</a>
            <a href="#theme-current-state">As it sits</a>
            <a href="#theme-history-provenance">Provenance</a>
          </nav>

          <section
            id="theme-owner-story"
            class="theme-owner-story"
            aria-labelledby="theme-story-heading"
          >
            <div class="theme-owner-story-copy">
              <p class="club-kicker club-kicker-paper">The story</p>
              <h3 id="theme-story-heading">Bought for the roads, slowly made my own.</h3>
              <p>
                I found this Cayman after a year of looking for a simple, analog car I would not
                be afraid to use. It still has the marks from long trips and autocross weekends.
                The plan is to improve feel and durability without sanding away what Porsche got
                right in the first place.
              </p>
              <p class="theme-story-byline">Written by @grolsen · edited Aug 4, 2026</p>
            </div>

            <div id="theme-recent-media" class="theme-recent-media" aria-label="Recent car media">
              <figure class="theme-media-frame theme-media-frame-wide">
                <.cayman_art />
                <figcaption>Regency Furniture Stadium grid · May 24</figcaption>
              </figure>
              <figure class="theme-media-frame theme-media-detail">
                <span class="theme-wheel-study" aria-hidden="true"></span>
                <figcaption>Fresh alignment · Aug 9</figcaption>
              </figure>
              <figure class="theme-media-frame theme-media-road">
                <span aria-hidden="true"></span>
                <figcaption>Blue Ridge loop · Jun 14</figcaption>
              </figure>
            </div>
          </section>

          <div class="theme-car-body">
            <section id="theme-journal" class="theme-journal" aria-labelledby="theme-journal-heading">
              <header class="theme-section-head">
                <div>
                  <p class="club-kicker club-kicker-paper">Living build thread</p>
                  <h3 id="theme-journal-heading">Journal</h3>
                </div>
                <button type="button" class="theme-text-action">Start at the beginning</button>
              </header>

              <div class="theme-journal-spine">
                <article id="theme-owner-update" class="theme-journal-item theme-owner-update">
                  <div class="theme-journal-meta">
                    <time datetime="2026-08-09">Aug 9, 2026</time>
                    <.status tone={:owner}>Owner reported</.status>
                  </div>
                  <h4>Back from alignment, finally sitting right.</h4>
                  <p>
                    Added a half degree of front camber and backed the rear toe down. The car is
                    calmer at speed and stopped eating the inside shoulder. The steering still
                    talks; it just stopped arguing.
                  </p>
                  <figure class="theme-update-media">
                    <.cayman_art />
                    <figcaption>Alignment check at Flat Six Works</figcaption>
                  </figure>
                  <dl class="theme-update-details">
                    <div>
                      <dt>Shop</dt><dd>Flat Six Works</dd>
                    </div>
                    <div>
                      <dt>Odometer</dt><dd>48,291 mi</dd>
                    </div>
                    <div>
                      <dt>Evidence</dt><dd>Invoice · 2 photos</dd>
                    </div>
                  </dl>
                  <div class="theme-journal-actions" aria-label="Update actions">
                    <button type="button"><.icon name="hero-heart" class="size-4" /> 12</button>
                    <button type="button"><.icon name="hero-chat-bubble-left" class="size-4" />
                    3 replies</button>
                    <button type="button"><.icon name="hero-arrow-up-on-square" class="size-4" />
                    Share</button>
                    <a href="#theme-owner-update"><.icon name="hero-link" class="size-4" /> Permalink</a>
                  </div>
                </article>

                <.event_journal_card />

                <article id="theme-record-event" class="theme-journal-item theme-record-event">
                  <div class="theme-record-event-date">
                    <time datetime="2018-05-12">May 12, 2018</time>
                    <.status tone={:verified}>Verified</.status>
                  </div>
                  <div>
                    <p class="club-kicker club-kicker-paper">External history</p>
                    <h4>40,884-mile service recorded</h4>
                    <p>Brake fluid, drive belt, and oil service. Imported from the dated invoice.</p>
                    <a href="#theme-history-provenance">Flat Six Works invoice · view source</a>
                  </div>
                </article>

                <article id="theme-plan-update" class="theme-journal-item theme-plan-update">
                  <div class="theme-journal-meta">
                    <time datetime="2026-03-02">Mar 2, 2026</time>
                    <span class="theme-intent-label">Plan · intent</span>
                  </div>
                  <h4>Thinking about a quieter exhaust and another season on these dampers.</h4>
                  <p>
                    No parts ordered. I want to hear one more setup in person before changing a car
                    that already works. If it happens, the installation gets its own update.
                  </p>
                </article>
              </div>
            </section>

            <aside
              id="theme-current-state"
              class="theme-current-state"
              aria-labelledby="theme-current-heading"
            >
              <p class="club-kicker club-kicker-paper">Current setup</p>
              <h3 id="theme-current-heading">As it sits</h3>
              <dl>
                <div>
                  <dt>Engine</dt><dd>3.4L flat-six</dd>
                </div>
                <div>
                  <dt>Transmission</dt><dd>6-speed manual</dd>
                </div>
                <div class="theme-state-changed">
                  <dt>Wheels &amp; tires</dt><dd>Apex SM-10 · RE-71RS</dd><small>17-inch Cayman S wheels as built</small>
                </div>
                <div class="theme-state-changed">
                  <dt>Suspension</dt><dd>Öhlins Road &amp; Track</dd><small>Factory dampers as built</small>
                </div>
                <div>
                  <dt>Brakes</dt><dd>Stock calipers · DS1.11 pads</dd>
                </div>
                <div>
                  <dt>Exterior</dt><dd>Speed Yellow · paint code 12H</dd>
                </div>
              </dl>
              <p class="theme-state-note">
                Event-local notes—like 32 psi on Sunday—stay with that day. Only a lasting car
                update changes this summary.
              </p>
            </aside>
          </div>

          <section
            id="theme-history-provenance"
            class="theme-provenance"
            aria-labelledby="theme-provenance-heading"
          >
            <header class="theme-provenance-head">
              <div>
                <p class="club-kicker club-kicker-paper">Original details and history</p>
                <h3 id="theme-provenance-heading">History &amp; provenance</h3>
              </div>
              <p><strong>7 of 9</strong> details verified</p>
            </header>

            <div class="theme-provenance-rows">
              <details id="theme-provenance-verified" open>
                <summary>
                  <span>Paint</span><strong>Speed Yellow · 12H</strong><.status tone={:verified}>
                    Verified
                  </.status><.icon name="hero-chevron-down" class="size-4" />
                </summary>
                <div class="theme-provenance-detail">
                  <dl>
                    <div>
                      <dt>Source</dt><dd>Porsche factory data</dd>
                    </div>
                    <div>
                      <dt>Date</dt><dd>At production</dd>
                    </div>
                    <div>
                      <dt>Backed by</dt><dd>Vehicle data sticker</dd>
                    </div>
                  </dl>
                  <a href="#theme-provenance-verified">Open public source</a>
                </div>
              </details>
              <details id="theme-provenance-owner">
                <summary>
                  <span>Current mileage</span><strong>48,291 mi</strong><.status tone={:owner}>
                    Owner reported
                  </.status><.icon name="hero-chevron-down" class="size-4" />
                </summary>
                <div class="theme-provenance-detail">
                  <p>Recorded by @grolsen on Aug 9, 2026.</p>
                </div>
              </details>
              <details id="theme-provenance-conflict">
                <summary>
                  <span>Delivery dealer</span><strong>Two sources disagree</strong><.status tone={
                    :conflict
                  }>
                    Conflicted
                  </.status><.icon name="hero-chevron-down" class="size-4" />
                </summary>
                <div class="theme-provenance-detail">
                  <p>The certificate and dealer invoice remain visible together until adjudicated.</p>
                </div>
              </details>
            </div>
          </section>
        </article>
      </div>
    </section>
    """
  end

  defp event_journal_card(assigns) do
    ~H"""
    <article id="theme-event-journal-card" class="theme-journal-item theme-event-card">
      <div class="theme-event-card-head">
        <div>
          <p class="club-kicker">Event update · May 24, 2026</p>
          <h4>WDCR 2026 AX Championship Event #2</h4>
          <p>Regency Furniture Stadium · Waldorf, Maryland</p>
        </div>
        <div class="theme-tags" aria-label="Event tags">
          <span>Autocross</span><span>#37</span><span>S2</span>
        </div>
      </div>

      <figure class="theme-event-lead-media">
        <.cayman_art />
        <figcaption>
          <.icon name="hero-play" class="size-4" /> Run 6 · onboard video · 1:08
        </figcaption>
      </figure>

      <p class="theme-event-narrative">
        The car finally rotated without asking twice. We softened the rear bar after lunch and
        found the balance I had been chasing. The cone on the quickest run was entirely mine.
      </p>

      <dl class="theme-event-details" aria-label="Owner-selected event details">
        <div>
          <dt>Best run</dt><dd>44.182 +1</dd>
        </div>
        <div>
          <dt>Class</dt><dd>S2</dd>
        </div>
        <div>
          <dt>Change tried</dt><dd>Rear bar one step softer</dd>
        </div>
        <div>
          <dt>Tire pressure</dt><dd>32F / 30R hot</dd>
        </div>
      </dl>

      <div class="theme-event-attachments" aria-label="Labeled attachments">
        <a href="#theme-event-journal-card"><.icon name="hero-video-camera" class="size-4" />
        Run 6 · onboard video</a>
        <a href="#theme-event-journal-card"><.icon name="hero-document-text" class="size-4" />
        Official result sheet</a>
        <a href="#theme-event-journal-card"><.icon name="hero-photo" class="size-4" />
        Paddock gallery · @cornerworker</a>
      </div>

      <footer class="theme-event-card-footer">
        <div class="theme-event-counts" aria-label="Event participation counts">
          <span><strong>18</strong> people &amp; cars</span>
          <span><strong>12</strong> media</span>
          <span><strong>8</strong> replies</span>
        </div>
        <div class="theme-event-card-actions">
          <.button href="#theme-event-journal-card" variant="primary">Our day</.button>
          <.button href="#theme-shared-event-study" variant="secondary">View the event</.button>
        </div>
      </footer>
    </article>
    """
  end

  defp shared_event_study(assigns) do
    ~H"""
    <section id="theme-shared-event-study" class="theme-study theme-event-study">
      <div class="club-wrap">
        <header class="theme-study-heading">
          <div>
            <p class="club-kicker club-kicker-paper">05 · Shared occurrence</p>
            <h2 class="club-display club-display-dark">One day, several honest accounts</h2>
          </div>
          <p>
            The event supplies time and place. Each member keeps authorship of their car's day,
            media, details, and replies.
          </p>
        </header>

        <article class="theme-event-page" aria-label="Recommended shared event page composition">
          <header id="theme-event-hero" class="theme-event-hero">
            <div>
              <div class="theme-event-source">
                <.status tone={:owner}>Community created</.status>
                <span>Checked against organizer details · May 22</span>
              </div>
              <p class="club-kicker">Washington DC Region SCCA</p>
              <h3>WDCR 2026 AX Championship Event #2</h3>
              <p class="theme-event-when">Sun, May 24 · gate opens 7:10 AM</p>
              <p class="theme-event-where">
                Regency Furniture Stadium · Waldorf, Maryland
              </p>
              <p class="theme-event-description">
                The second points event of the 2026 Solo season at Regency Furniture Stadium.
                Public member accounts and media are gathered below without flattening their
                owner-named details into results.
              </p>
              <div class="theme-tags" aria-label="Shared event tags">
                <span>Autocross</span><span>WDCR</span><span>Waldorf</span><span>2026</span>
              </div>
            </div>
            <div class="theme-event-hero-art" aria-hidden="true">
              <img src={~p"/images/tire-arcs.svg"} alt="" />
              <svg viewBox="0 0 420 260">
                <path d="M36 204C101 186 91 103 174 106s65 84 137 45 79-86 87-119" />
                <circle cx="36" cy="204" r="5" />
                <circle cx="398" cy="32" r="5" />
              </svg>
              <span>18 public participations</span>
            </div>
          </header>

          <div class="theme-event-page-body">
            <section
              id="theme-event-people"
              class="theme-event-section"
              aria-labelledby="theme-event-people-heading"
            >
              <header class="theme-section-head">
                <div>
                  <p class="club-kicker club-kicker-paper">People &amp; cars</p>
                  <h3 id="theme-event-people-heading">The field, in their own words</h3>
                </div>
                <span class="theme-section-count">18 public accounts</span>
              </header>

              <div class="theme-participation-grid">
                <article class="theme-participation-card">
                  <header>
                    <Layouts.avatar handle="grolsen" tone={:petrol} />
                    <div>
                      <p>@grolsen</p><h4>2007 Porsche Cayman S</h4>
                    </div>
                  </header>
                  <p>Found the balance after lunch; took one cone along for the quickest lap.</p>
                  <dl>
                    <div>
                      <dt>Best run</dt><dd>44.182 +1</dd>
                    </div>
                    <div>
                      <dt>Camber</dt><dd>-3.0° front</dd>
                    </div>
                  </dl>
                  <a href="#theme-event-journal-card">Our day →</a>
                </article>

                <article class="theme-participation-card">
                  <header>
                    <Layouts.avatar handle="apexandink" tone={:orange} />
                    <div>
                      <p>@apexandink</p><h4>2024 Chevrolet Corvette Stingray</h4>
                    </div>
                  </header>
                  <p>
                    First event on the new tires. Fast enough to be useful, messy enough to learn.
                  </p>
                  <dl>
                    <div>
                      <dt>Focus</dt><dd>Looking ahead</dd>
                    </div>
                    <div>
                      <dt>Photos</dt><dd>@cornerworker</dd>
                    </div>
                  </dl>
                  <a href="#theme-event-happened">Read the account →</a>
                </article>
              </div>
            </section>

            <section
              id="theme-event-happened"
              class="theme-event-section"
              aria-labelledby="theme-event-happened-heading"
            >
              <header class="theme-section-head">
                <div>
                  <p class="club-kicker club-kicker-paper">What happened</p>
                  <h3 id="theme-event-happened-heading">Public accounts from the day</h3>
                </div>
                <p>Replies stay attached to each car update.</p>
              </header>

              <div class="theme-event-accounts">
                <article>
                  <time datetime="2026-05-24T12:42:00-04:00">12:42 PM · @grolsen</time>
                  <h4>Rear bar softened after the fourth run</h4>
                  <p>The car stopped pushing on entry and gave up nothing in the faster offset.</p>
                  <div>
                    <a href="#theme-event-journal-card">Run 6 video</a><a href="#theme-event-journal-card">Setup notes</a>
                  </div>
                </article>
                <article>
                  <time datetime="2026-05-24T16:18:00-04:00">4:18 PM · @apexandink</time>
                  <h4>First full day on the new tires</h4>
                  <p>
                    They wanted more heat than the morning gave them. The afternoon photos tell the rest.
                  </p>
                  <div>
                    <a href="#theme-event-media">12-photo gallery</a><a href="#theme-event-about">Course walk notes</a>
                  </div>
                </article>
              </div>
            </section>

            <section
              id="theme-event-media"
              class="theme-event-section"
              aria-labelledby="theme-event-media-heading"
            >
              <header class="theme-section-head">
                <div>
                  <p class="club-kicker club-kicker-paper">Media</p>
                  <h3 id="theme-event-media-heading">Seen by the people who were there</h3>
                </div>
              </header>
              <div class="theme-event-media-grid">
                <figure class="theme-event-media-car">
                  <.cayman_art /><figcaption>Run 6 · @grolsen</figcaption>
                </figure>
                <figure class="theme-event-media-cones">
                  <span aria-hidden="true"></span><figcaption>
                    Afternoon course · @cornerworker
                  </figcaption>
                </figure>
                <figure class="theme-event-media-paddock">
                  <span aria-hidden="true"></span><figcaption>
                    Paddock at noon · @apexandink
                  </figcaption>
                </figure>
              </div>
            </section>

            <section
              id="theme-event-about"
              class="theme-event-section theme-event-about"
              aria-labelledby="theme-event-about-heading"
            >
              <div>
                <p class="club-kicker club-kicker-paper">About &amp; sources</p>
                <h3 id="theme-event-about-heading">The shared coordinate</h3>
                <p>
                  Time, place, description, and source links describe the occurrence. Owners
                  describe their participation; imported files keep their own attribution.
                </p>
              </div>
              <dl>
                <div>
                  <dt>Time</dt><dd>May 24, 2026 · gate opens 7:10 AM EDT</dd>
                </div>
                <div>
                  <dt>Place</dt><dd>11765 St Linus Drive, Waldorf, MD</dd>
                </div>
                <div>
                  <dt>Event source</dt><dd>
                    <a
                      href="https://www.motorsportreg.com/events/wdcr-2026-ax-championship-event-2-regency-furniture-stadium-scca-802440"
                      target="_blank"
                      rel="noreferrer"
                    >WDCR registration &amp; event details</a>
                  </dd>
                </div>
                <div>
                  <dt>Community media</dt><dd>
                    <a href="#theme-event-media">Participant-labeled photos and video</a>
                  </dd>
                </div>
              </dl>
            </section>
          </div>
        </article>
      </div>
    </section>
    """
  end

  attr :form, :any, required: true

  defp event_composer_study(assigns) do
    ~H"""
    <section id="theme-event-composer" class="theme-study theme-composer-study">
      <div class="club-wrap">
        <header class="theme-study-heading">
          <div>
            <p class="club-kicker club-kicker-paper">06 · Generic event composer</p>
            <h2 class="club-display club-display-dark">Record the day without naming its schema</h2>
          </div>
          <p>
            One reusable path for a meet, tour, track day, show, or anything else: shared event,
            owner narrative, chosen details, labeled attachments, review.
          </p>
        </header>

        <article class="theme-composer-shell">
          <.form for={@form} id="theme-event-composer-form" class="theme-event-composer-form">
            <section aria-labelledby="theme-composer-event-heading">
              <p class="theme-form-step">1</p>
              <div>
                <h3 id="theme-composer-event-heading">Find or name the event</h3>
                <.input
                  field={@form[:event]}
                  type="search"
                  label="Event title, date, or place"
                  autocomplete="off"
                />
                <div class="theme-event-match">
                  <div>
                    <strong>WDCR 2026 AX Championship Event #2</strong><span>
                      May 24 · Regency Furniture Stadium
                    </span>
                  </div>
                  <button type="button">Use this event</button>
                </div>
                <button type="button" class="theme-text-action">Name a new event instead</button>
              </div>
            </section>

            <section aria-labelledby="theme-composer-account-heading">
              <p class="theme-form-step">2</p>
              <div>
                <h3 id="theme-composer-account-heading">Tell your car's day</h3>
                <p class="theme-form-context">Adding to <strong>2007 Porsche Cayman S</strong></p>
                <.input field={@form[:journal]} type="textarea" label="Journal text" rows="6" />
                <.input field={@form[:tags]} type="text" label="Tags" />
                <div class="theme-tags theme-form-tags" aria-label="Selected tags">
                  <span>Autocross</span><span>WDCR</span><span>Waldorf</span>
                </div>
              </div>
            </section>

            <section aria-labelledby="theme-composer-details-heading">
              <p class="theme-form-step">3</p>
              <div>
                <h3 id="theme-composer-details-heading">Add the details you care about</h3>
                <p class="theme-form-help">
                  Labels and values are yours. They stay searchable text; Vin Santo does not turn
                  unrelated details into standings or calculations.
                </p>
                <div id="theme-event-details-editor" class="theme-detail-editor">
                  <div class="theme-detail-row">
                    <span class="theme-detail-grip" aria-hidden="true">⋮⋮</span>
                    <.input field={@form[:detail_1_label]} type="text" label="Label" />
                    <.input field={@form[:detail_1_value]} type="text" label="Value" />
                    <div class="theme-detail-actions">
                      <button type="button" aria-label="Move Best run up"><.icon
                        name="hero-arrow-up"
                        class="size-4"
                      /></button>
                      <button type="button" aria-label="Move Best run down"><.icon
                        name="hero-arrow-down"
                        class="size-4"
                      /></button>
                      <button type="button" aria-label="Remove Best run"><.icon
                        name="hero-x-mark"
                        class="size-4"
                      /></button>
                    </div>
                  </div>
                  <div class="theme-detail-row">
                    <span class="theme-detail-grip" aria-hidden="true">⋮⋮</span>
                    <.input field={@form[:detail_2_label]} type="text" label="Label" />
                    <.input field={@form[:detail_2_value]} type="text" label="Value" />
                    <div class="theme-detail-actions">
                      <button type="button" aria-label="Move Class up"><.icon
                        name="hero-arrow-up"
                        class="size-4"
                      /></button>
                      <button type="button" aria-label="Move Class down"><.icon
                        name="hero-arrow-down"
                        class="size-4"
                      /></button>
                      <button type="button" aria-label="Remove Class"><.icon
                        name="hero-x-mark"
                        class="size-4"
                      /></button>
                    </div>
                  </div>
                  <div class="theme-detail-row">
                    <span class="theme-detail-grip" aria-hidden="true">⋮⋮</span>
                    <.input field={@form[:detail_3_label]} type="text" label="Label" />
                    <.input field={@form[:detail_3_value]} type="text" label="Value" />
                    <div class="theme-detail-actions">
                      <button type="button" aria-label="Move Change tried up"><.icon
                        name="hero-arrow-up"
                        class="size-4"
                      /></button>
                      <button type="button" aria-label="Move Change tried down"><.icon
                        name="hero-arrow-down"
                        class="size-4"
                      /></button>
                      <button type="button" aria-label="Remove Change tried"><.icon
                        name="hero-x-mark"
                        class="size-4"
                      /></button>
                    </div>
                  </div>
                </div>
                <button type="button" class="theme-add-row"><.icon name="hero-plus" class="size-4" />
                Add a detail</button>
                <p class="theme-form-note">
                  These describe this event only. A lasting modification gets its own car update.
                </p>
              </div>
            </section>

            <section aria-labelledby="theme-composer-attachments-heading">
              <p class="theme-form-step">4</p>
              <div>
                <h3 id="theme-composer-attachments-heading">Add labeled files or links</h3>
                <div class="theme-attachment-fields">
                  <.input field={@form[:attachment_label]} type="text" label="Label" />
                  <.input field={@form[:attachment_url]} type="url" label="Link" />
                </div>
                <.input
                  field={@form[:file]}
                  id="theme-event-file"
                  type="file"
                  label="Or choose a file"
                />
                <div class="theme-attachment-preview">
                  <.icon name="hero-video-camera" class="size-5" />
                  <div><strong>Run 6 · onboard video</strong><span>video.example/run-6</span></div>
                  <button type="button" aria-label="Remove onboard video"><.icon
                    name="hero-x-mark"
                    class="size-4"
                  /></button>
                </div>
                <button type="button" class="theme-add-row"><.icon name="hero-plus" class="size-4" />
                Add another attachment</button>
              </div>
            </section>

            <section aria-labelledby="theme-composer-visibility-heading">
              <p class="theme-form-step">5</p>
              <div>
                <h3 id="theme-composer-visibility-heading">Choose who can see it</h3>
                <.input
                  field={@form[:visibility]}
                  type="select"
                  label="Visibility"
                  options={[
                    {"Public — shown on the car and event", "public"},
                    {"Private — only you", "private"}
                  ]}
                />
                <button type="button" class="club-button club-button-primary">Review event update</button>
              </div>
            </section>
          </.form>

          <aside
            id="theme-event-composer-review"
            class="theme-composer-review"
            aria-labelledby="theme-composer-review-heading"
          >
            <p class="club-kicker">Review before save</p>
            <h3 id="theme-composer-review-heading">Our day at WDCR AX Event #2</h3>
            <p class="theme-review-meta">May 24 · Waldorf · Public</p>
            <p>
              The car finally rotated without asking twice. We softened the rear bar after lunch
              and found the balance I had been chasing.
            </p>
            <dl>
              <div>
                <dt>Best run</dt><dd>44.182 +1</dd>
              </div>
              <div>
                <dt>Class</dt><dd>S2</dd>
              </div>
              <div>
                <dt>Change tried</dt><dd>Rear bar one step softer</dd>
              </div>
            </dl>
            <div class="theme-review-attachment">
              <.icon name="hero-video-camera" class="size-4" /> Run 6 · onboard video
            </div>
            <p class="theme-review-note">
              Nothing is saved from the lab. This is the final read-back.
            </p>
            <button type="button" class="club-button club-button-primary">Save event update</button>
          </aside>
        </article>
      </div>
    </section>
    """
  end

  defp cayman_art(assigns) do
    ~H"""
    <svg
      class="theme-cayman-art"
      viewBox="0 0 960 390"
      role="img"
      aria-label="Side profile illustration of a Porsche Cayman"
    >
      <path class="theme-cayman-shadow" d="M88 310c134 26 657 28 788-3-87 55-683 58-788 3Z" />
      <path
        class="theme-cayman-body"
        d="M72 264c12-30 40-46 85-55l139-24c40-65 91-99 157-110 65-11 144 1 197 29 45 24 81 61 119 97l100 23c22 6 35 22 37 48l-4 24h-70c-8-61-51-93-105-93-56 0-99 36-106 93H330c-8-61-50-93-105-93-56 0-98 36-106 93H70c-7-9-7-21 2-32Z"
      />
      <path
        class="theme-cayman-glass"
        d="M326 179c37-54 82-81 137-91 56-9 118-2 164 17 35 15 66 42 100 78l-401-4Z"
      />
      <path
        class="theme-cayman-detail"
        d="M462 91l11 88m258 9-69 6m-330-8-36 7m250-9-8 95m-213-4 278 2m160-48c46 2 73 8 96 25M105 253l53-12"
      />
      <path class="theme-cayman-intake" d="M576 211c33-8 61-7 79 4-13 12-35 24-67 34l-12-38Z" />
      <circle class="theme-cayman-wheel" cx="225" cy="294" r="72" />
      <circle class="theme-cayman-wheel" cx="727" cy="294" r="72" />
      <circle class="theme-cayman-rim" cx="225" cy="294" r="39" />
      <circle class="theme-cayman-rim" cx="727" cy="294" r="39" />
      <path
        class="theme-cayman-spokes"
        d="M225 257v74m-37-37h74m-63-26 52 52m0-52-52 52M727 257v74m-37-37h74m-63-26 52 52m0-52-52 52"
      />
    </svg>
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
