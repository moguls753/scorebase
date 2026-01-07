import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toast"]
  static values = {
    autoDismiss: { type: Number, default: 4000 }
  }

  connect() {
    this.toastTargets.forEach((toast, index) => {
      const delay = this.autoDismissValue + (index * 500)
      toast.dataset.dismissTimeout = setTimeout(() => {
        this.dismissToast(toast)
      }, delay)
    })
  }

  disconnect() {
    this.toastTargets.forEach(toast => {
      const timeout = toast.dataset.dismissTimeout
      if (timeout) clearTimeout(parseInt(timeout, 10))
    })
  }

  dismiss(event) {
    const toast = event.target.closest("[data-flash-target='toast']")
    if (!toast) return

    const timeout = toast.dataset.dismissTimeout
    if (timeout) clearTimeout(parseInt(timeout, 10))

    this.dismissToast(toast)
  }

  dismissToast(toast) {
    if (toast.classList.contains("is-dismissing")) return

    toast.classList.add("is-dismissing")

    const cleanup = () => {
      if (!toast.parentNode) return // Already removed
      toast.remove()
      // Check if container is empty after removal
      if (this.element && !this.element.querySelector("[data-flash-target='toast']")) {
        this.element.remove()
      }
    }

    toast.addEventListener("animationend", cleanup, { once: true })

    // Fallback for reduced-motion or animation issues
    setTimeout(cleanup, 200)
  }
}
