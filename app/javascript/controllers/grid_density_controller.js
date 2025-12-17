import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["grid", "button"]
  static values = { default: { type: String, default: "3" } }

  connect() {
    const saved = localStorage.getItem("gridDensity")
    this.density = saved || this.defaultValue
    this.applyDensity()
    this.updateButtons()
  }

  set(event) {
    const density = event.currentTarget.dataset.density
    this.density = density
    localStorage.setItem("gridDensity", density)
    this.applyDensity()
    this.updateButtons()
  }

  applyDensity() {
    const grid = this.gridTarget
    // Remove existing grid-cols classes (including responsive prefixes)
    grid.className = grid.className.replace(/\b(sm:|md:|lg:|xl:|2xl:)?grid-cols-\d+\b/g, "").replace(/\s+/g, " ").trim()

    // Apply new density
    switch(this.density) {
      case "2":
        grid.classList.add("grid-cols-2", "sm:grid-cols-2", "md:grid-cols-3", "lg:grid-cols-3")
        break
      case "3":
        grid.classList.add("grid-cols-3", "sm:grid-cols-3", "md:grid-cols-4", "lg:grid-cols-4")
        break
      case "4":
        grid.classList.add("grid-cols-4", "sm:grid-cols-4", "md:grid-cols-5", "lg:grid-cols-6")
        break
      default:
        grid.classList.add("grid-cols-3", "sm:grid-cols-3", "md:grid-cols-4", "lg:grid-cols-4")
    }
  }

  updateButtons() {
    this.buttonTargets.forEach(btn => {
      if (btn.dataset.density === this.density) {
        btn.classList.add("grid-density-btn--active")
      } else {
        btn.classList.remove("grid-density-btn--active")
      }
    })
  }
}
