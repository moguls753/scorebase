import { Controller } from "@hotwired/stimulus"

// Landing-side arrival focus. Attached to the hero search box. On a fine-pointer
// desktop with an empty box, focus the box; otherwise focus the hero heading — an
// arrival cue that avoids popping the mobile keyboard (and fires on Back-to-landing).
export default class extends Controller {
  connect() {
    const desktop = window.matchMedia("(min-width: 640px) and (pointer: fine)").matches
    if (desktop && !this.element.value) {
      this.element.focus({ preventScroll: true })
    } else {
      document.getElementById("hero-heading")?.focus({ preventScroll: true })
    }
  }
}
