import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="midi-player"
export default class extends Controller {
  static targets = ["player", "visualizer", "playButton", "stopButton", "progress", "time", "loading"]
  static values = { src: String }

  connect() {
    this.isPlaying = false
    this.loadLibrary()
  }

  async loadLibrary() {
    // Check if already loaded
    if (window.midiPlayerLoaded) {
      this.initPlayer()
      return
    }

    // Show loading state
    if (this.hasLoadingTarget) {
      this.loadingTarget.classList.remove("hidden")
    }

    // Load the html-midi-player library
    const script = document.createElement("script")
    script.src = "https://cdn.jsdelivr.net/npm/html-midi-player@1.5.0/dist/midi-player.min.js"
    script.onload = () => {
      window.midiPlayerLoaded = true
      this.initPlayer()
    }
    script.onerror = () => {
      console.error("Failed to load MIDI player library")
      if (this.hasLoadingTarget) {
        this.loadingTarget.textContent = "Failed to load player"
      }
    }
    document.head.appendChild(script)
  }

  initPlayer() {
    // Hide loading, show player
    if (this.hasLoadingTarget) {
      this.loadingTarget.classList.add("hidden")
    }
    if (this.hasPlayerTarget) {
      this.playerTarget.classList.remove("hidden")
    }

    // Get the midi-player element
    const player = this.element.querySelector("midi-player")
    const visualizer = this.element.querySelector("midi-visualizer")

    if (player) {
      // Link visualizer to player
      if (visualizer) {
        visualizer.setAttribute("src", this.srcValue)
        player.addEventListener("load", () => {
          visualizer.setAttribute("src", player.getAttribute("src"))
        })
      }

      // Update play/stop button states
      player.addEventListener("start", () => {
        this.isPlaying = true
        this.updateButtonStates()
      })

      player.addEventListener("stop", () => {
        this.isPlaying = false
        this.updateButtonStates()
      })
    }
  }

  play() {
    const player = this.element.querySelector("midi-player")
    if (player) {
      player.start()
    }
  }

  stop() {
    const player = this.element.querySelector("midi-player")
    if (player) {
      player.stop()
    }
  }

  updateButtonStates() {
    if (this.hasPlayButtonTarget) {
      this.playButtonTarget.classList.toggle("hidden", this.isPlaying)
    }
    if (this.hasStopButtonTarget) {
      this.stopButtonTarget.classList.toggle("hidden", !this.isPlaying)
    }
  }

  disconnect() {
    const player = this.element.querySelector("midi-player")
    if (player) {
      player.stop()
    }
  }
}
