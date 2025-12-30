import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["reveal", "waitlistForm", "waitlistMessage"]

  connect() {
    this.setupScrollReveal()
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
    }
  }

  setupScrollReveal() {
    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            // For use-case boxes, animate all together when first one is visible
            if (entry.target.classList.contains('use-case')) {
              this.animateUseCaseGroup(entry.target)
            } else {
              entry.target.classList.add('visible')
            }
          }
        })
      },
      {
        threshold: 0.1,
        rootMargin: '0px 0px -50px 0px'
      }
    )

    this.revealTargets.forEach(el => this.observer.observe(el))
  }

  animateUseCaseGroup(triggeredElement) {
    // Find all use-case elements and animate them together
    const useCases = this.revealTargets.filter(el => el.classList.contains('use-case'))
    useCases.forEach((useCase, index) => {
      // Apply staggered delay based on actual order
      useCase.style.transitionDelay = `${index * 0.1}s`
      useCase.classList.add('visible')
      // Stop observing use cases after first trigger
      this.observer.unobserve(useCase)
    })
  }

  scrollToWaitlist(event) {
    event.preventDefault()
    const waitlistElement = document.getElementById('waitlist')

    if (waitlistElement) {
      waitlistElement.scrollIntoView({
        behavior: 'smooth',
        block: 'center'
      })
    }
  }

  async submitWaitlist(event) {
    event.preventDefault()

    const form = event.target
    const emailInput = form.querySelector('input[name="email"]')
    const submitButton = form.querySelector('button[type="submit"]')
    const email = emailInput.value.trim()

    if (!email) return

    // Store original button text before changing
    const originalText = submitButton.textContent

    // Disable form during submission
    submitButton.disabled = true
    submitButton.textContent = submitButton.dataset.submitting || 'Sending...'

    try {
      const locale = document.documentElement.lang || 'en'
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

      if (!csrfToken) {
        throw new Error('CSRF token not found')
      }

      const response = await fetch(`/${locale}/waitlist`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken
        },
        body: JSON.stringify({
          waitlist_signup: { email }
        })
      })

      const data = await response.json()

      if (data.success) {
        this.showMessage(data.message, 'success')
        form.reset()
      } else {
        this.showMessage(data.errors?.join(', ') || 'Something went wrong', 'error')
      }
    } catch (error) {
      console.error('Waitlist submission error:', error)
      this.showMessage('Network error. Please try again.', 'error')
    } finally {
      submitButton.disabled = false
      submitButton.textContent = originalText
    }
  }

  showMessage(message, type) {
    if (!this.hasWaitlistMessageTarget) return

    const messageEl = this.waitlistMessageTarget
    messageEl.textContent = message
    messageEl.className = `waitlist-message waitlist-message-${type}`
    messageEl.style.display = 'block'

    // Hide after 5 seconds
    setTimeout(() => {
      messageEl.style.display = 'none'
    }, 5000)
  }
}
