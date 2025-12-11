import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "overlay", "hamburger"]

  connect() {
    document.addEventListener('keydown', this.handleKeydown.bind(this))
  }

  disconnect() {
    document.removeEventListener('keydown', this.handleKeydown.bind(this))
  }

  toggle() {
    const isOpen = this.menuTarget.classList.contains('mobile-menu--open')
    isOpen ? this.close() : this.open()
  }

  open() {
    this.menuTarget.classList.add('mobile-menu--open')
    this.overlayTarget.classList.add('mobile-overlay--visible')
    this.hamburgerTarget.classList.add('hamburger--active')
    document.body.style.overflow = 'hidden'
  }

  close() {
    this.menuTarget.classList.remove('mobile-menu--open')
    this.overlayTarget.classList.remove('mobile-overlay--visible')
    this.hamburgerTarget.classList.remove('hamburger--active')
    document.body.style.overflow = ''
  }

  handleKeydown(event) {
    if (event.key === 'Escape') this.close()
  }
}
