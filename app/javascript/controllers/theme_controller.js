import { Controller } from "@hotwired/stimulus"

// Dark Warm Neubrutalism - Dark mode only, no toggle
export default class extends Controller {
  static targets = ["toggle"]

  connect() {
    // Force dark mode - no toggle available
    // The CSS no longer has a light theme, so this is just for consistency
  }

  toggle() {
    // Disabled - dark mode only
    // Keeping method for backwards compatibility if any views still call it
  }

  setTheme(theme) {
    // Disabled - dark mode only
  }
}
