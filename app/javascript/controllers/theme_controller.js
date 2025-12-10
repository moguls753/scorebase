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
        this.labelTarget.textContent = "Dark"
      }
    } else {
      document.documentElement.removeAttribute("data-theme")
      if (this.hasLabelTarget) {
        this.labelTarget.textContent = "Light"
      }
    }
    localStorage.setItem("theme", theme)
  }
}
