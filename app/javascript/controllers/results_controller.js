import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["frame", "live", "badge"]

  connect() {
    this.onFrameMissing = this.onFrameMissing.bind(this)
    this.onFrameLoad    = this.onFrameLoad.bind(this)
    this.onSubmitStart  = this.onSubmitStart.bind(this)
    document.addEventListener("turbo:frame-missing", this.onFrameMissing)
    document.addEventListener("turbo:frame-load",    this.onFrameLoad)
    document.addEventListener("turbo:submit-start",  this.onSubmitStart)
    this.syncBadge()
    if (!document.activeElement || document.activeElement === document.body) this.focusHeading()
  }

  disconnect() {
    document.removeEventListener("turbo:frame-missing", this.onFrameMissing)
    document.removeEventListener("turbo:frame-load",    this.onFrameLoad)
    document.removeEventListener("turbo:submit-start",  this.onSubmitStart)
  }

  // Query fresh each time — the heading lives inside the frame and is replaced on
  // every swap, so caching a reference would go stale.
  get heading() { return this.frameTarget.querySelector("#scores-results-heading") }

  // A frame-targeted request that resolves to the frameless landing (blank query
  // with no filters, clearing the last filter, a stale ?sort= on a source-only
  // page) would render "Content missing" into the frame. Promote it to a full,
  // locale-correct visit of the URL the form already generated.
  onFrameMissing(event) {
    if (event.target.id !== "scores") return
    event.preventDefault()
    event.detail.visit(event.detail.response)
  }

  onSubmitStart(event) {
    const form = event.target
    const targetsFrame = form.dataset.turboFrame === "scores" || this.frameTarget.contains(form)
    const active = document.activeElement
    this.refocusName = (targetsFrame && this.frameTarget.contains(active)) ? active.name : null
  }

  onFrameLoad(event) {
    if (event.target.id !== "scores") return
    this.syncBadge()
    this.scrollToHeading()
    this.manageFocus()
  }

  manageFocus() {
    const active  = document.activeElement
    const refocus = this.refocusName; this.refocusName = null
    if (active === this.heading) return
    if (active && active !== document.body && !this.frameTarget.contains(active)) { this.announce(); return }
    if (refocus) {
      const c = [...this.frameTarget.querySelectorAll(`[name="${refocus}"]`)].find(el => el.offsetParent !== null)
      if (c) { c.focus(); this.announce(); return }
    }
    this.focusHeading()
  }

  focusHeading() { this.heading?.focus({ preventScroll: true }) }

  // Clear then set on the next frame so an unchanged string (e.g. a sort that
  // keeps the count) is still re-announced.
  announce() {
    if (!this.hasLiveTarget || !this.heading) return
    const msg = this.heading.dataset.resultsAnnounce || ""
    this.liveTarget.textContent = ""
    requestAnimationFrame(() => { this.liveTarget.textContent = msg })
  }

  syncBadge() {
    if (!this.hasBadgeTarget || !this.heading) return
    const n = parseInt(this.heading.dataset.activeFilters || "0", 10)
    this.badgeTarget.textContent = n
    this.badgeTarget.hidden = n === 0
  }

  scrollToHeading() {
    if (!this.heading) return
    const behavior = window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth"
    this.heading.scrollIntoView({ block: "start", behavior })
  }
}
