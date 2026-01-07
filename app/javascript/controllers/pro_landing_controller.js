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
    const useCases = this.revealTargets.filter(el => el.classList.contains('use-case'))
    useCases.forEach((useCase, index) => {
      useCase.style.transitionDelay = `${index * 0.1}s`
      useCase.classList.add('visible')
      this.observer.unobserve(useCase)
    })
  }
}
