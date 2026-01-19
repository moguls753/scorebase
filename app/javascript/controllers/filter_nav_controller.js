import { Controller } from "@hotwired/stimulus"

// Simple navigation controller for filter dropdowns
// Navigates to the selected option's URL when changed
export default class extends Controller {
  static targets = ["select"]

  navigate() {
    const url = this.selectTarget.value
    if (url) {
      Turbo.visit(url)
    }
  }
}
