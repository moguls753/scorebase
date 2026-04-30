// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import { Turbo } from "@hotwired/turbo-rails"
import "controllers"
import "chartkick"
import "Chart.bundle"
import "ahoy"

// Ahoy: no cookies (matches Ahoy.cookies = :none server-side); manual
// trackView on every Turbo navigation since ahoy.js doesn't auto-fire it.
window.ahoy.configure({ cookies: false })

document.addEventListener("turbo:load", () => {
  window.ahoy.trackView()
})
