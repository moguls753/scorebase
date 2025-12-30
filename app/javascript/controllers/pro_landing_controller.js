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
            entry.target.classList.add('visible')
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
