import { Controller } from "@hotwired/stimulus"

/**
 * Instrument Context Controller
 * Shows/hides vocal-specific filters when Voice/Choir is selected.
 *
 * Simple, focused controller - just toggles visibility with smooth animation.
 */
export default class extends Controller {
  static targets = ["select", "vocalFilters"]

  // Instruments that trigger vocal filter display
  static VOCAL_INSTRUMENTS = ["voice", "choir", "a cappella"]

  connect() {
    // Initial state is set server-side via hidden attribute
  }

  update() {
    const value = this.selectTarget.value.toLowerCase()
    const isVocal = this.constructor.VOCAL_INSTRUMENTS.some(v => value.includes(v))

    if (isVocal) {
      this.showVocalFilters()
    } else {
      this.hideVocalFilters()
    }
  }

  showVocalFilters() {
    const el = this.vocalFiltersTarget
    el.hidden = false
    el.classList.add("is-visible")
  }

  hideVocalFilters() {
    const el = this.vocalFiltersTarget
    el.classList.remove("is-visible")

    // Wait for CSS transition before hiding
    setTimeout(() => {
      if (!el.classList.contains("is-visible")) {
        el.hidden = true
      }
    }, 200)
  }
}
