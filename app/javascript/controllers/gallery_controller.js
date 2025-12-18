import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="gallery"
// Sheet music page gallery with neubrutalist aesthetics
// Supports: keyboard navigation, touch swipe, click-to-advance, fullscreen
export default class extends Controller {
  static targets = ["image", "counter", "dot", "prevBtn", "nextBtn", "container"]
  static values = {
    pages: Array,
    current: { type: Number, default: 0 },
    loading: { type: Boolean, default: true }
  }

  connect() {
    this.preloadedImages = new Set()
    this.touchStartX = 0
    this.touchStartY = 0

    // Start loading first image
    this.loadCurrentImage()
    this.preloadAdjacentPages()
    this.updateUI()

    // Keyboard events (scoped to prevent conflicts)
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

    // Show loading state
    this.loadingValue = true
    this.imageTarget.style.opacity = "0.5"

    // If already preloaded, show immediately
    if (this.preloadedImages.has(url)) {
      this.imageTarget.src = url
      this.imageTarget.style.opacity = "1"
      this.loadingValue = false
    } else {
      // Load with transition
      const img = new Image()
      img.onload = () => {
        this.imageTarget.src = url
        this.imageTarget.style.opacity = "1"
        this.loadingValue = false
        this.preloadedImages.add(url)
      }
      img.onerror = () => {
        this.loadingValue = false
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

    // Counter
    if (this.hasCounterTarget) {
      this.counterTarget.textContent = `${current + 1} / ${total}`
    }

    // Navigation buttons
    if (this.hasPrevBtnTarget) {
      this.prevBtnTarget.disabled = isFirst
      this.prevBtnTarget.classList.toggle("gallery-btn-disabled", isFirst)
    }
    if (this.hasNextBtnTarget) {
      this.nextBtnTarget.disabled = isLast
      this.nextBtnTarget.classList.toggle("gallery-btn-disabled", isLast)
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
