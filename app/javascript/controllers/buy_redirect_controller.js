import { Controller } from "@hotwired/stimulus"

// Prevents bots from following buy links by requiring JS execution.
// The actual URL is in a data attribute, not in href.
export default class extends Controller {
  static values = { url: String, scoreId: Number, event: String }

  go(event) {
    event.preventDefault()
    if (!this.hasUrlValue) return

    // Track on the real click, not the bot/prefetch GET to /go/, so scanners never count.
    // One event name per partner, so the funnel stays split by merchant.
    if (window.ahoy && this.hasScoreIdValue && this.hasEventValue) {
      window.ahoy.track(this.eventValue, { score_id: this.scoreIdValue })
    }

    // Use window.open without noreferrer so the Referer header is sent
    // (required by server-side referrer validation)
    window.open(this.urlValue, "_blank", "noopener")
  }
}
