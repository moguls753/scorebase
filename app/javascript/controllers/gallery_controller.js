import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="gallery"
// Sheet music page gallery with neubrutalist aesthetics
// Supports: keyboard navigation, touch swipe, click-to-advance, fullscreen
export default class extends Controller {
  static targets = ["image", "counter", "dot", "prevBtn", "nextBtn", "container", "progressBar"]
  static values = {
    pages: Array,
    current: { type: Number, default: 0 }
  }

  connect() {
    this.preloadedImages = new Set()
    this.touchStartX = 0
    this.touchStartY = 0
    this.isDragging = false

    this.loadCurrentImage()
    this.preloadAdjacentPages()
    this.updateUI()

    // Keyboard events
    this.boundKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)

    // Fullscreen change listener
    this.boundFullscreenChange = this.handleFullscreenChange.bind(this)
    document.addEventListener("fullscreenchange", this.boundFullscreenChange)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
    document.removeEventListener("fullscreenchange", this.boundFullscreenChange)
  }

  // Navigation
  next() {
    if (this.currentValue < this.pagesValue.length - 1) {
      this.currentValue++
      this.loadCurrentImage()
    }
  }

  prev() {
    if (this.currentValue > 0) {
      this.currentValue--
      this.loadCurrentImage()
    }
  }

  goToPage(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10)
    if (!isNaN(index) && index >= 0 && index < this.pagesValue.length) {
      this.currentValue = index
      this.loadCurrentImage()
    }
  }

  // Click on progress bar to jump to page
  progressClick(event) {
    if (!this.hasProgressBarTarget) return
    // Don't trigger on drag end
    if (this.isDragging) return

    this.seekToPosition(event.clientX)
  }

  // Drag support for progress bar
  progressDragStart(event) {
    if (!this.hasProgressBarTarget) return
    this.isDragging = true
    this.progressBarTarget.classList.add("is-dragging")
    // Prevent default to avoid text selection
    event.preventDefault()
  }

  progressDragMove(event) {
    if (!this.isDragging || !this.hasProgressBarTarget) return
    event.preventDefault()

    const touch = event.touches[0]
    this.seekToPosition(touch.clientX)
  }

  progressDragEnd() {
    if (!this.isDragging) return
    this.isDragging = false
    this.progressBarTarget.classList.remove("is-dragging")
  }

  // Shared seek logic - reads padding from CSS custom property
  seekToPosition(clientX) {
    if (!this.hasProgressBarTarget) return

    const rect = this.progressBarTarget.getBoundingClientRect()
    const style = getComputedStyle(this.progressBarTarget)
    const padding = parseFloat(style.getPropertyValue('--padding')) || 10
    const trackWidth = rect.width - (padding * 2)
    const clickX = clientX - rect.left - padding

    const percentage = Math.max(0, Math.min(1, clickX / trackWidth))
    const newIndex = Math.round(percentage * (this.pagesValue.length - 1))

    if (newIndex !== this.currentValue && newIndex >= 0 && newIndex < this.pagesValue.length) {
      this.currentValue = newIndex
      this.loadCurrentImage()
    }
  }

  // Click on image advances (desktop convenience)
  imageClick(event) {
    // Don't advance if user is selecting text or clicking controls
    if (event.target.closest("button")) return

    if (this.currentValue < this.pagesValue.length - 1) {
      this.next()
    }
  }

  loadCurrentImage() {
    if (!this.hasImageTarget) return

    const url = this.pagesValue[this.currentValue]
    if (!url) return

    // If already preloaded, show immediately
    if (this.preloadedImages.has(url)) {
      this.imageTarget.src = url
    } else {
      // Show loading state, then swap
      this.imageTarget.style.opacity = "0.5"
      const img = new Image()
      img.onload = () => {
        this.imageTarget.src = url
        this.imageTarget.style.opacity = "1"
        this.preloadedImages.add(url)
      }
      img.onerror = () => {
        this.imageTarget.style.opacity = "1"
      }
      img.src = url
    }

    this.updateUI()
    this.preloadAdjacentPages()
  }

  updateUI() {
    const current = this.currentValue
    const total = this.pagesValue.length
    const isFirst = current === 0
    const isLast = current === total - 1

    // Counter (only used in progress bar mode - shows current page number)
    if (this.hasCounterTarget) {
      this.counterTarget.textContent = `${current + 1}`
    }

    // Navigation buttons
    if (this.hasPrevBtnTarget) {
      this.prevBtnTarget.disabled = isFirst
    }
    if (this.hasNextBtnTarget) {
      this.nextBtnTarget.disabled = isLast
    }

    // Dot indicators (wrapper button with inner span.gallery-dot)
    this.dotTargets.forEach((wrapper, index) => {
      const isActive = index === current
      const dot = wrapper.querySelector(".gallery-dot")
      if (dot) {
        dot.classList.toggle("is-active", isActive)
      }
      wrapper.setAttribute("aria-selected", isActive ? "true" : "false")
    })

    // Progress bar (for 5+ pages) - just set CSS custom property, CSS does the rest
    if (this.hasProgressBarTarget) {
      const progress = total > 1 ? current / (total - 1) : 0
      this.progressBarTarget.style.setProperty('--progress', progress)
      this.progressBarTarget.setAttribute("aria-valuenow", current + 1)
    }
  }

  preloadAdjacentPages() {
    // Preload previous, next, and next+1 for smooth navigation
    const indices = [
      this.currentValue - 1,
      this.currentValue + 1,
      this.currentValue + 2
    ]

    indices.forEach(i => {
      if (i >= 0 && i < this.pagesValue.length) {
        const url = this.pagesValue[i]
        if (!this.preloadedImages.has(url)) {
          const img = new Image()
          img.onload = () => this.preloadedImages.add(url)
          img.src = url
        }
      }
    })
  }

  // Keyboard navigation
  handleKeydown(event) {
    // Ignore if in input field
    if (event.target.matches("input, textarea, select")) return

    // Only respond when gallery is visible
    if (!this.element.offsetParent) return

    switch (event.key) {
      case "ArrowRight":
      case "ArrowDown":
        event.preventDefault()
        this.next()
        break
      case "ArrowLeft":
      case "ArrowUp":
        event.preventDefault()
        this.prev()
        break
      case "Home":
        event.preventDefault()
        this.currentValue = 0
        this.loadCurrentImage()
        break
      case "End":
        event.preventDefault()
        this.currentValue = this.pagesValue.length - 1
        this.loadCurrentImage()
        break
      case "f":
      case "F":
        if (!event.ctrlKey && !event.metaKey) {
          event.preventDefault()
          this.toggleFullscreen()
        }
        break
      case "Escape":
        if (document.fullscreenElement) {
          document.exitFullscreen()
        }
        break
    }
  }

  // Touch/swipe support
  touchStart(event) {
    this.touchStartX = event.changedTouches[0].screenX
    this.touchStartY = event.changedTouches[0].screenY
  }

  touchEnd(event) {
    const touchEndX = event.changedTouches[0].screenX
    const touchEndY = event.changedTouches[0].screenY

    const diffX = this.touchStartX - touchEndX
    const diffY = this.touchStartY - touchEndY

    // Only handle horizontal swipes (ignore vertical scrolling)
    if (Math.abs(diffX) > Math.abs(diffY) && Math.abs(diffX) > 50) {
      if (diffX > 0) {
        this.next() // Swipe left = next
      } else {
        this.prev() // Swipe right = prev
      }
    }
  }

  // Fullscreen
  toggleFullscreen() {
    if (document.fullscreenElement) {
      document.exitFullscreen()
    } else if (this.hasContainerTarget) {
      this.containerTarget.requestFullscreen().catch(() => {
        // Fullscreen not supported, fail silently
      })
    }
  }

  handleFullscreenChange() {
    const isFullscreen = !!document.fullscreenElement
    this.element.classList.toggle("gallery-fullscreen", isFullscreen)
  }
}
