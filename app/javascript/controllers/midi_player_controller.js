import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="midi-player"
export default class extends Controller {
  static targets = ["container", "loading"]
  static values = { src: String }

  connect() {
    this.loadLibrary()
  }

  async loadLibrary() {
    // Show loading state
    if (this.hasLoadingTarget) {
      this.loadingTarget.classList.remove("hidden")
    }

    // Check if already loaded
    if (window.midiPlayerReady) {
      this.createPlayer()
      return
    }

    // If currently loading, wait for it
    if (window.midiPlayerLoading) {
      window.midiPlayerCallbacks = window.midiPlayerCallbacks || []
      window.midiPlayerCallbacks.push(() => this.createPlayer())
      return
    }

    window.midiPlayerLoading = true

    // Load the html-midi-player library
    const script = document.createElement("script")
    script.src = "https://cdn.jsdelivr.net/combine/npm/tone@14.7.58,npm/@magenta/music@1.23.1/es6/core.js,npm/html-midi-player@1.5.0"

    script.onload = () => {
      // Give a moment for custom elements to register
      setTimeout(() => {
        window.midiPlayerReady = true
        window.midiPlayerLoading = false
        this.createPlayer()

        // Call any waiting callbacks
        if (window.midiPlayerCallbacks) {
          window.midiPlayerCallbacks.forEach(cb => cb())
          window.midiPlayerCallbacks = []
        }
      }, 100)
    }

    script.onerror = () => {
      window.midiPlayerLoading = false
      if (this.hasLoadingTarget) {
        this.loadingTarget.innerHTML = `
          <span class="text-xs font-semibold text-[var(--color-text-muted)]">
            Failed to load player
          </span>
        `
      }
    }

    document.head.appendChild(script)
  }

  createPlayer() {
    // Hide loading
    if (this.hasLoadingTarget) {
      this.loadingTarget.classList.add("hidden")
    }

    // Show container and create elements
    if (this.hasContainerTarget) {
      this.containerTarget.classList.remove("hidden")

      // Create the player elements dynamically
      const visualizerId = `midi-viz-${Date.now()}`

      this.containerTarget.innerHTML = `
        <div class="midi-staff-container">
          <midi-visualizer
            id="${visualizerId}"
            src="${this.srcValue}"
            type="staff">
          </midi-visualizer>
        </div>
        <midi-player
          src="${this.srcValue}"
          sound-font
          visualizer="#${visualizerId}">
        </midi-player>
      `
    }
  }

  disconnect() {
    const player = this.element.querySelector("midi-player")
    if (player && player.stop) {
      player.stop()
    }
  }
}
