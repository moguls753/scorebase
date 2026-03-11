import { Controller } from "@hotwired/stimulus"

// Prevents bots from following buy links by requiring JS execution.
// The actual URL is in a data attribute, not in href.
export default class extends Controller {
  static values = { url: String }

  go(event) {
    event.preventDefault()
    if (this.urlValue) {
      // Use window.open without noreferrer so the Referer header is sent
      // (required by server-side referrer validation)
      window.open(this.urlValue, "_blank", "noopener")
    }
  }
}
