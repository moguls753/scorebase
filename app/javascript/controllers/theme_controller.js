import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle", "label"]

  connect() {
    // Check for saved theme preference, default to light
    const savedTheme = localStorage.getItem("theme") || "light"
    this.setTheme(savedTheme, false)
  }

  toggle() {
    const currentTheme = document.documentElement.getAttribute("data-theme")
    const newTheme = currentTheme === "dark" ? "light" : "dark"
    this.setTheme(newTheme, true)
  }

  setTheme(theme, animate) {
    if (theme === "dark") {
      document.documentElement.setAttribute("data-theme", "dark")
      if (this.hasLabelTarget) {
        // Use translated label from data attribute
        const darkLabel = this.labelTarget.dataset.dark || "Dark"
        this.labelTarget.textContent = darkLabel
      }
    } else {
      document.documentElement.removeAttribute("data-theme")
      if (this.hasLabelTarget) {
        // Use translated label from data attribute
        const lightLabel = this.labelTarget.dataset.light || "Light"
        this.labelTarget.textContent = lightLabel
      }
    }
    localStorage.setItem("theme", theme)
  }
}
