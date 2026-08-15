import { Controller } from "@hotwired/stimulus"

// Mirrors HubPagesHelper#filter_options_for_select - both must slug identically
const slugify = (value) =>
  value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")

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
        // Assigning the raw param would blank the select: ?instrument=Organ filters, but the option value is "organ"
        const wanted = slugify(paramValue)
        const option = Array.from(field.options).find(o => slugify(o.value) === wanted)
        field.value = option ? option.value : paramValue
      }
    })
  }

  submit() {
    this.element.requestSubmit()
  }
}
