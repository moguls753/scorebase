import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="midi-player"
export default class extends Controller {
  static targets = ["container", "loading", "playBtn", "pauseBtn", "progress", "progressBar", "currentTime", "totalTime", "volumeSlider", "volumeIcon"]
  static values = { src: String }

  connect() {
    this.isPlaying = false
    this.duration = 0
    this.currentTime = 0
    this.volume = 0.8
    this.loadLibrary()
  }

  async loadLibrary() {
    if (this.hasLoadingTarget) {
      this.loadingTarget.classList.remove("hidden")
    }

    if (window.midiPlayerReady) {
      this.createPlayer()
      return
    }

    if (window.midiPlayerLoading) {
      window.midiPlayerCallbacks = window.midiPlayerCallbacks || []
      window.midiPlayerCallbacks.push(() => this.createPlayer())
      return
    }

    window.midiPlayerLoading = true

    const script = document.createElement("script")
    script.src = "https://cdn.jsdelivr.net/combine/npm/tone@14.7.58,npm/@magenta/music@1.23.1/es6/core.js,npm/html-midi-player@1.5.0"

    script.onload = () => {
      setTimeout(() => {
        window.midiPlayerReady = true
        window.midiPlayerLoading = false
        this.createPlayer()

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
    if (this.hasLoadingTarget) {
      this.loadingTarget.classList.add("hidden")
    }

    if (this.hasContainerTarget) {
      this.containerTarget.classList.remove("hidden")

      // Create hidden midi-player element
      const hiddenPlayer = document.createElement("midi-player")
      hiddenPlayer.setAttribute("src", this.srcValue)
      hiddenPlayer.setAttribute("sound-font", "")
      hiddenPlayer.style.display = "none"
      this.containerTarget.appendChild(hiddenPlayer)

      this.player = hiddenPlayer

      // Set up event listeners
      this.player.addEventListener("load", () => {
        this.duration = this.player.duration
        this.updateTimeDisplay()
      })

      this.player.addEventListener("start", () => {
        this.isPlaying = true
        this.updatePlayPauseButtons()
        this.startProgressUpdate()
      })

      this.player.addEventListener("stop", () => {
        this.isPlaying = false
        this.updatePlayPauseButtons()
        this.stopProgressUpdate()
        // Reset to beginning if stopped at end
        if (this.player.currentTime >= this.duration - 0.1) {
          this.currentTime = 0
          this.updateProgress()
        }
      })

      this.player.addEventListener("note", () => {
        this.currentTime = this.player.currentTime
        this.updateProgress()
      })

      // Initialize volume
      this.setVolume(this.volume)
    }
  }

  play() {
    if (this.player) {
      if (this.isPlaying) {
        this.player.stop()
      } else {
        this.player.start()
      }
    }
  }

  seek(event) {
    if (!this.player || !this.duration) return

    const rect = this.progressTarget.getBoundingClientRect()
    const x = event.clientX - rect.left
    const percent = Math.max(0, Math.min(1, x / rect.width))
    const seekTime = percent * this.duration

    this.player.currentTime = seekTime
    this.currentTime = seekTime
    this.updateProgress()
  }

  updateVolume(event) {
    const value = parseFloat(event.target.value)
    this.setVolume(value)
  }

  setVolume(value) {
    this.volume = value

    // Tone.js volume is in decibels, convert from 0-1 to dB
    if (window.Tone && window.Tone.Destination) {
      if (value === 0) {
        window.Tone.Destination.volume.value = -Infinity
      } else {
        // Map 0-1 to -40dB to 0dB
        window.Tone.Destination.volume.value = 20 * Math.log10(value)
      }
    }

    this.updateVolumeIcon()
  }

  updateVolumeIcon() {
    if (!this.hasVolumeIconTarget) return

    let icon
    if (this.volume === 0) {
      icon = `<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z"/>
             <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M17 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2"/>`
    } else if (this.volume < 0.5) {
      icon = `<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M15.536 8.464a5 5 0 010 7.072M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z"/>`
    } else {
      icon = `<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M15.536 8.464a5 5 0 010 7.072m2.828-9.9a9 9 0 010 12.728M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z"/>`
    }

    this.volumeIconTarget.innerHTML = icon
  }

  updatePlayPauseButtons() {
    if (this.hasPlayBtnTarget && this.hasPauseBtnTarget) {
      this.playBtnTarget.classList.toggle("hidden", this.isPlaying)
      this.pauseBtnTarget.classList.toggle("hidden", !this.isPlaying)
    }
  }

  updateProgress() {
    if (!this.hasProgressBarTarget || !this.duration) return

    const percent = (this.currentTime / this.duration) * 100
    this.progressBarTarget.style.width = `${percent}%`
    this.updateTimeDisplay()
  }

  updateTimeDisplay() {
    if (this.hasCurrentTimeTarget) {
      this.currentTimeTarget.textContent = this.formatTime(this.currentTime)
    }
    if (this.hasTotalTimeTarget) {
      this.totalTimeTarget.textContent = this.formatTime(this.duration)
    }
  }

  formatTime(seconds) {
    if (!seconds || isNaN(seconds)) return "0:00"
    const mins = Math.floor(seconds / 60)
    const secs = Math.floor(seconds % 60)
    return `${mins}:${secs.toString().padStart(2, "0")}`
  }

  startProgressUpdate() {
    this.progressInterval = setInterval(() => {
      if (this.player && this.isPlaying) {
        this.currentTime = this.player.currentTime
        this.updateProgress()
      }
    }, 100)
  }

  stopProgressUpdate() {
    if (this.progressInterval) {
      clearInterval(this.progressInterval)
    }
  }

  disconnect() {
    this.stopProgressUpdate()
    if (this.player && this.player.stop) {
      this.player.stop()
    }
  }
}
