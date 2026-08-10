defmodule SantoApiWeb.DistributionComponents do
  @moduledoc "The portable update, forum, and signature controls from owner_surface §6."

  use SantoApiWeb, :html

  attr :payload, :map, required: true
  attr :thread, :map, default: nil
  attr :thread_form, :map, default: nil
  attr :stewarding?, :boolean, required: true

  def share_kit(assigns) do
    ~H"""
    <section
      id="update-distribution"
      class="club-distribution"
      aria-labelledby="distribution-heading"
    >
      <header class="club-distribution-head">
        <div>
          <p class="club-kicker club-kicker-paper">From your garage</p>
          <h2 id="distribution-heading">Share this update</h2>
        </div>
        <p>Save the image, copy a forum post, or send the link.</p>
      </header>

      <div class="club-distribution-main">
        <figure class="club-share-card-preview">
          <img
            id="update-share-card-preview"
            src={@payload.card_path}
            alt={"Share card for #{@payload.title}: #{@payload.headline}"}
            width="1080"
            height="1350"
            loading="lazy"
          />
          <figcaption>4:5 image · ready for a post or story</figcaption>
        </figure>

        <div class="club-distribution-actions">
          <button
            id="share-update-link"
            type="button"
            class="club-button club-button-primary"
            phx-hook=".ShareUpdate"
            phx-update="ignore"
            data-title={@payload.title}
            data-text={@payload.headline}
            data-url={@payload.url}
          >
            <.icon name="hero-arrow-up-on-square" class="size-4" />
            <span>Share link</span>
          </button>

          <a
            id="download-share-card"
            href={@payload.card_path}
            download={@payload.download_name}
            class="club-button club-button-secondary"
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> Save image
          </a>

          <div class="club-distribution-copy-actions" aria-label="Forum copy formats">
            <.copy_button
              id="copy-update-bbcode"
              text={@payload.bbcode}
              label="Copy BBCode"
            />
            <.copy_button
              id="copy-update-markdown"
              text={@payload.markdown}
              label="Copy Markdown"
            />
          </div>

          <details id="forum-post-preview" class="club-distribution-preview">
            <summary>Preview the forum post</summary>
            <pre>{@payload.bbcode}</pre>
          </details>
        </div>
      </div>

      <div :if={@stewarding?} id="build-thread-destination" class="club-thread-destination">
        <div>
          <p class="club-kicker club-kicker-paper">Your build thread</p>
          <h3>{if @thread, do: display_url(@thread.url), else: "Remember it once"}</h3>
          <p>
            {if @thread,
              do: "We’ll copy the forum post and open this thread.",
              else: "Paste the thread URL here. Every future update can go straight back to it."}
          </p>
        </div>

        <div :if={@thread} class="club-thread-actions">
          <.copy_button
            id="post-to-build-thread"
            text={@payload.bbcode}
            label="Copy and open thread"
            copied_label="Copied — opening thread"
            open_url={@thread.url}
            variant="primary"
          />
          <button
            type="button"
            id="forget-build-thread"
            phx-click="clear_thread"
            class="club-text-button"
          >
            Forget this thread
          </button>
        </div>

        <.form
          :if={is_nil(@thread)}
          for={@thread_form}
          id="build-thread-form"
          phx-submit="save_thread"
          class="club-thread-form"
        >
          <.input
            field={@thread_form[:url]}
            type="url"
            label="Build thread URL"
            placeholder="https://rennlist.com/forums/…"
            required
          />
          <button type="submit" class="club-button club-button-secondary">Remember thread</button>
        </.form>
      </div>

      <details id="vehicle-badge-kit" class="club-badge-kit">
        <summary>Forum signature badge</summary>
        <div class="club-badge-kit-body">
          <img
            src={@payload.badge_url}
            alt={"#{@payload.title} on Vin Santo"}
            width="560"
            height="120"
            loading="lazy"
          />
          <p>A small linked badge for a forum signature.</p>
          <div class="club-distribution-copy-actions">
            <.copy_button id="copy-badge-bbcode" text={@payload.badge_bbcode} label="Copy BBCode" />
            <.copy_button id="copy-badge-html" text={@payload.badge_html} label="Copy HTML" />
          </div>
        </div>
      </details>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ShareUpdate">
        export default {
          mounted() {
            this.el.addEventListener("click", async () => {
              try {
                if (navigator.share) {
                  await navigator.share({
                    title: this.el.dataset.title,
                    text: this.el.dataset.text,
                    url: this.el.dataset.url
                  })
                } else {
                  await this.copy(this.el.dataset.url)
                  this.flash("Link copied")
                }
              } catch (_error) {
                // Closing the native share sheet is not an error to explain.
              }
            })
          },
          async copy(text) {
            if (navigator.clipboard?.writeText) return navigator.clipboard.writeText(text)
            const field = document.createElement("textarea")
            field.value = text
            field.setAttribute("readonly", "")
            field.style.position = "fixed"
            field.style.opacity = "0"
            document.body.appendChild(field)
            field.select()
            document.execCommand("copy")
            field.remove()
          },
          flash(label) {
            const target = this.el.querySelector("span")
            const original = target.textContent
            target.textContent = label
            window.setTimeout(() => target.textContent = original, 1800)
          }
        }
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyShareText">
        export default {
          mounted() {
            this.el.addEventListener("click", async () => {
              const destination = this.el.dataset.openUrl
              const destinationTab = destination
                ? window.open(destination, "_blank", "noopener,noreferrer")
                : null

              try {
                await this.copy(this.el.dataset.copy)
                this.flash(this.el.dataset.copiedLabel)
              } catch (_error) {
                if (destinationTab) destinationTab.close()
              }
            })
          },
          async copy(text) {
            if (navigator.clipboard?.writeText) return navigator.clipboard.writeText(text)
            const field = document.createElement("textarea")
            field.value = text
            field.setAttribute("readonly", "")
            field.style.position = "fixed"
            field.style.opacity = "0"
            document.body.appendChild(field)
            field.select()
            document.execCommand("copy")
            field.remove()
          },
          flash(label) {
            const target = this.el.querySelector("span")
            const original = target.textContent
            target.textContent = label
            window.setTimeout(() => target.textContent = original, 1800)
          }
        }
      </script>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :text, :string, required: true
  attr :label, :string, required: true
  attr :copied_label, :string, default: "Copied"
  attr :open_url, :string, default: nil
  attr :variant, :string, default: "secondary"

  defp copy_button(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      class={[
        "club-button",
        if(@variant == "primary", do: "club-button-primary", else: "club-button-secondary")
      ]}
      phx-hook=".CopyShareText"
      phx-update="ignore"
      data-copy={@text}
      data-copied-label={@copied_label}
      data-open-url={@open_url}
    >
      <.icon name="hero-clipboard-document" class="size-4" /> <span>{@label}</span>
    </button>
    """
  end

  defp display_url(url) do
    uri = URI.parse(url)
    path = if uri.path in [nil, "", "/"], do: "", else: uri.path
    "#{uri.host}#{path}"
  end
end
