import { Controller } from "@hotwired/stimulus"

// User menu dropdown with keyboard navigation
// 37signals pattern: instant, accessible, Turbo-aware
export default class extends Controller {
  static targets = ["menu", "trigger", "firstItem"]

  connect() {
    this.closeOnClickOutside = this.closeOnClickOutside.bind(this)
    this.handleKeydown = this.handleKeydown.bind(this)
    this.closeOnTurboNav = this.close.bind(this)

    // Close menu on Turbo navigation
    document.addEventListener("turbo:before-visit", this.closeOnTurboNav)
  }

  toggle(event) {
    event.stopPropagation()
    if (this.element.classList.contains("is-open")) {
      this.close()
    } else {
      this.open()
    }
  }

  open() {
    this.element.classList.add("is-open")
    this.menuTarget.classList.add("is-open")
    this.triggerTarget.setAttribute("aria-expanded", "true")

    // Focus first menu item for keyboard users
    if (this.hasFirstItemTarget) {
      this.firstItemTarget.focus()
    }

    document.addEventListener("click", this.closeOnClickOutside)
    document.addEventListener("keydown", this.handleKeydown)
  }

  close() {
    this.element.classList.remove("is-open")
    this.menuTarget.classList.remove("is-open")
    this.triggerTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.closeOnClickOutside)
    document.removeEventListener("keydown", this.handleKeydown)
  }

  closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      this.close()
      this.triggerTarget.focus()
    }
  }

  disconnect() {
    document.removeEventListener("click", this.closeOnClickOutside)
    document.removeEventListener("keydown", this.handleKeydown)
    document.removeEventListener("turbo:before-visit", this.closeOnTurboNav)
  }
}
