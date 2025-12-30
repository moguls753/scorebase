import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item"]

  connect() {
    this.boundHandleResize = this.handleResize.bind(this)
    this.handleResize()
    window.addEventListener('resize', this.boundHandleResize)
  }

  disconnect() {
    window.removeEventListener('resize', this.boundHandleResize)
  }

  toggle(event) {
    const button = event.currentTarget
    const item = button.closest('[data-faq-accordion-target="item"]')

    // Only toggle on mobile (when toggle is visible)
    const toggle = item.querySelector('.faq-toggle')
    if (window.getComputedStyle(toggle).display !== 'none') {
      const isOpen = item.getAttribute('data-faq-open') === 'true'
      const newState = !isOpen
      item.setAttribute('data-faq-open', newState)
      button.setAttribute('aria-expanded', newState)
    }
  }

  handleResize() {
    const isDesktop = window.matchMedia('(min-width: 768px)').matches

    if (isDesktop) {
      // Open all FAQs on desktop
      this.itemTargets.forEach(item => {
        const button = item.querySelector('.faq-q')
        item.setAttribute('data-faq-open', 'true')
        if (button) {
          button.setAttribute('aria-expanded', 'true')
        }
      })
    }
  }
}
