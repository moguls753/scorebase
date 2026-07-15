// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import { Turbo } from "@hotwired/turbo-rails"
import "controllers"
import "chartkick"
import "Chart.bundle"
import "ahoy"

// Ahoy: no cookies (matches Ahoy.cookies = :none server-side); manual
// trackView on every Turbo navigation since ahoy.js doesn't auto-fire it.
// visitsUrl/eventsUrl override the gem's default /ahoy/* paths so EasyPrivacy
// (and similar default-on filter lists) don't block our requests.
window.ahoy.configure({
  cookies: false,
  visitsUrl: "/_internal/visits",
  eventsUrl: "/_internal/events"
})

// Only the hostname, never the full referrer URL — a Referer can carry search
// queries, private forum/webmail paths and tokens, so the URL never leaves here.
function referringDomain() {
  try {
    const referrer = document.referrer
    if (!referrer) return null
    return new URL(referrer).hostname || null
  } catch (e) {
    return null
  }
}

document.addEventListener("turbo:load", () => {
  const domain = referringDomain()
  window.ahoy.trackView(domain ? { referring_domain: domain } : {})
})
