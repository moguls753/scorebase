import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.syncFromUrl()
    document.addEventListener("turbo:frame-load", this.handleFrameLoad.bind(this))
  }

  disconnect() {
    document.removeEventListener("turbo:frame-load", this.handleFrameLoad.bind(this))
  }

  handleFrameLoad(event) {
    if (event.target.id === "scores") {
      // URL is updated by turbo-action="advance", just sync form fields
      this.syncFromUrl()
    }
  }

  syncFromUrl() {
    const params = new URLSearchParams(window.location.search)

    // Sync all inputs/selects in this form based on their name attribute
    this.element.querySelectorAll("input, select").forEach(field => {
      const paramValue = params.get(field.name) || ""
      if (field.type === "hidden" || field.type === "text") {
        field.value = paramValue
      } else if (field.tagName === "SELECT") {
        field.value = paramValue
      }
    })
  }
}
