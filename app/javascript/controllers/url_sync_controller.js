import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.boundHandleFrameLoad = this.handleFrameLoad.bind(this)
    this.syncFromUrl()
    document.addEventListener("turbo:frame-load", this.boundHandleFrameLoad)
  }

  disconnect() {
    document.removeEventListener("turbo:frame-load", this.boundHandleFrameLoad)
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
      if (field === document.activeElement) return // don't clobber the caret while typing

      let paramValue = params.get(field.name) || ""

      // Default sort to "popularity" when not specified in URL
      if (field.name === "sort" && paramValue === "") {
        paramValue = "popularity"
      }

      if (field.type === "hidden" || field.type === "text" || field.type === "search") {
        field.value = paramValue
      } else if (field.tagName === "SELECT") {
        field.value = paramValue
      }
    })
  }

  submit() {
    this.element.requestSubmit()
  }
}
