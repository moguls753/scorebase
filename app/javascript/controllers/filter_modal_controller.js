import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "closeButton"]

  connect() {
    this.handleKeydown = this.handleKeydown.bind(this)
  }

  open() {
    this.previousActiveElement = document.activeElement
    this.modalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
    document.addEventListener("keydown", this.handleKeydown)

    // Focus first focusable element or close button
    requestAnimationFrame(() => {
      const firstFocusable = this.modalTarget.querySelector(
        'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
      )
      if (firstFocusable) firstFocusable.focus()
    })
  }

  close() {
    this.modalTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
    document.removeEventListener("keydown", this.handleKeydown)

    // Restore focus to trigger element
    if (this.previousActiveElement) {
      this.previousActiveElement.focus()
    }
  }

  closeOnBackdrop(event) {
    if (event.target === this.modalTarget) {
      this.close()
    }
  }

  closeAndSubmit(event) {
    const form = event.target.form
    if (form) {
      form.requestSubmit()
      this.close()
    }
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      this.close()
      return
    }

    // Trap focus within modal
    if (event.key === "Tab") {
      const focusableElements = this.modalTarget.querySelectorAll(
        'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
      )
      const firstElement = focusableElements[0]
      const lastElement = focusableElements[focusableElements.length - 1]

      if (event.shiftKey && document.activeElement === firstElement) {
        event.preventDefault()
        lastElement.focus()
      } else if (!event.shiftKey && document.activeElement === lastElement) {
        event.preventDefault()
        firstElement.focus()
      }
    }
  }

  disconnect() {
    document.removeEventListener("keydown", this.handleKeydown)
    document.body.classList.remove("overflow-hidden")
  }
}
