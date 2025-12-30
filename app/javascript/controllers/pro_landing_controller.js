import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["reveal"]

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

  submitWaitlist(event) {
    event.preventDefault()
    // TODO: Wire up to email service (Mailchimp, ConvertKit, etc)
    alert('Waitlist form - connect to your email service')
  }
}
