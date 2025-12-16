import { Controller } from "@hotwired/stimulus"

/**
 * ListFilterController - Generic fuzzy search filter for hub pages
 *
 * Provides instant client-side filtering with:
 * - Fuzzy matching (typo-tolerant search)
 * - Match highlighting
 * - Alphabet navigation
 * - Grouped sections that hide when empty
 *
 * Usage:
 *   <div data-controller="list-filter"
 *        data-list-filter-search-attribute-value="composerName"
 *        data-list-filter-singular-text-value="composer found"
 *        data-list-filter-plural-text-value="composers found"
 *        data-list-filter-no-match-text-value="No composers matching">
 *
 *     <input data-list-filter-target="input" data-action="input->list-filter#search">
 *     <button data-list-filter-target="clear" data-action="list-filter#clear">×</button>
 *     <div data-list-filter-target="resultsCount"></div>
 *
 *     <nav>
 *       <a data-list-filter-target="alphabetLink" data-letter="A" data-action="list-filter#jumpToLetter">A</a>
 *       ...
 *     </nav>
 *
 *     <section data-list-filter-target="group" data-letter="A">
 *       <a data-list-filter-target="item" data-composer-name="bach">...</a>
 *       <!-- Note: data-composer-name becomes dataset.composerName in JS -->
 *     </section>
 *   </div>
 */
export default class extends Controller {
  static targets = [
    "input",
    "clear",
    "resultsCount",
    "noResults",
    "noResultsText",
    "item",
    "group",
    "alphabetLink",
    "itemName"
  ]

  static values = {
    searchAttribute: { type: String, default: "filter-value" },
    singularText: { type: String, default: "result found" },
    pluralText: { type: String, default: "results found" },
    noMatchText: { type: String, default: "No results matching" },
    debounceMs: { type: Number, default: 150 }
  }

  static classes = ["hidden", "filtered", "disabled", "active", "visible"]

  connect() {
    this.buildAvailableLetters()
    this.disableEmptyLetters()
    this.bindKeyboardShortcuts()
  }

  disconnect() {
    this.unbindKeyboardShortcuts()
    clearTimeout(this.searchTimeout)
  }

  // ─────────────────────────────────────────────────────────────
  // Actions
  // ─────────────────────────────────────────────────────────────

  search() {
    clearTimeout(this.searchTimeout)
    this.searchTimeout = setTimeout(() => {
      this.performSearch(this.inputTarget.value.trim())
    }, this.debounceMsValue)
  }

  clear() {
    this.clearSearch()
    this.inputTarget.focus()
  }

  jumpToLetter(event) {
    const link = event.currentTarget

    if (link.classList.contains(this.disabledClass)) {
      event.preventDefault()
      return
    }

    // Clear search if active
    if (this.hasInputTarget && this.inputTarget.value.trim()) {
      this.clearSearch()
    }

    // Briefly highlight the clicked letter
    this.alphabetLinkTargets.forEach(l => l.classList.remove(this.activeClass))
    link.classList.add(this.activeClass)
    setTimeout(() => link.classList.remove(this.activeClass), 1000)
  }

  // ─────────────────────────────────────────────────────────────
  // Private: Search Logic
  // ─────────────────────────────────────────────────────────────

  performSearch(query) {
    if (!query) {
      this.clearSearch()
      return
    }

    this.showClearButton()

    let matchCount = 0

    this.itemTargets.forEach(item => {
      const searchValue = item.dataset[this.camelizedSearchAttribute]
      const result = this.fuzzyMatch(searchValue, query)

      if (result.match) {
        matchCount++
        item.classList.remove(this.filteredClass)
        this.highlightMatch(item, result.indices)
      } else {
        item.classList.add(this.filteredClass)
        this.clearHighlight(item)
      }
    })

    this.updateGroupVisibility()
    this.updateResultsCount(matchCount, query)
    this.updateAlphabetNav()
  }

  clearSearch() {
    if (this.hasInputTarget) {
      this.inputTarget.value = ""
    }
    this.hideClearButton()
    this.clearResultsCount()

    this.itemTargets.forEach(item => {
      item.classList.remove(this.filteredClass)
      this.clearHighlight(item)
    })

    this.groupTargets.forEach(group => {
      group.classList.remove(this.hiddenClass)
    })

    this.hideNoResults()
    this.resetAlphabetNav()
  }

  // ─────────────────────────────────────────────────────────────
  // Private: Fuzzy Matching
  // ─────────────────────────────────────────────────────────────

  /**
   * Normalize text for search: strip accents, lowercase
   * "Händel" -> "handel", "Dvořák" -> "dvorak"
   */
  normalizeForSearch(text) {
    if (!text) return ""
    return text.normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
  }

  fuzzyMatch(text, query) {
    if (!text) return { match: false, score: 0, indices: [] }

    const textNormalized = this.normalizeForSearch(text)
    const queryNormalized = this.normalizeForSearch(query)

    // Direct substring match (higher priority)
    if (textNormalized.includes(queryNormalized)) {
      const start = textNormalized.indexOf(queryNormalized)
      const indices = Array.from({ length: queryNormalized.length }, (_, i) => start + i)
      return { match: true, score: 100, indices }
    }

    // Fuzzy character-by-character match
    let queryIdx = 0
    let indices = []
    let consecutiveBonus = 0
    let score = 0

    for (let i = 0; i < textNormalized.length && queryIdx < queryNormalized.length; i++) {
      if (textNormalized[i] === queryNormalized[queryIdx]) {
        indices.push(i)

        // Bonus for consecutive matches
        if (indices.length > 1 && indices[indices.length - 1] === indices[indices.length - 2] + 1) {
          consecutiveBonus += 5
        }

        // Bonus for word boundary matches
        if (i === 0 || text[i - 1] === " " || text[i - 1] === "-") {
          score += 10
        }

        queryIdx++
      }
    }

    if (queryIdx === queryNormalized.length) {
      score += 50 - indices.length + consecutiveBonus
      return { match: true, score, indices }
    }

    return { match: false, score: 0, indices: [] }
  }

  // ─────────────────────────────────────────────────────────────
  // Private: UI Updates
  // ─────────────────────────────────────────────────────────────

  highlightMatch(item, indices) {
    if (!this.hasItemNameTarget) return

    const nameEl = item.querySelector("[data-list-filter-target='itemName']")
    if (!nameEl) return

    const text = nameEl.textContent
    nameEl.innerHTML = this.applyHighlight(text, indices)
  }

  clearHighlight(item) {
    const nameEl = item.querySelector("[data-list-filter-target='itemName']")
    if (nameEl) {
      nameEl.innerHTML = nameEl.textContent
    }
  }

  applyHighlight(text, indices) {
    if (!indices.length) return text

    // Group consecutive indices for cleaner markup
    const groups = []
    let currentGroup = [indices[0]]

    for (let i = 1; i < indices.length; i++) {
      if (indices[i] === indices[i - 1] + 1) {
        currentGroup.push(indices[i])
      } else {
        groups.push(currentGroup)
        currentGroup = [indices[i]]
      }
    }
    groups.push(currentGroup)

    let result = ""
    let lastIdx = 0

    groups.forEach(group => {
      const start = group[0]
      const end = group[group.length - 1] + 1
      result += text.slice(lastIdx, start)
      result += `<mark>${text.slice(start, end)}</mark>`
      lastIdx = end
    })

    result += text.slice(lastIdx)
    return result
  }

  updateGroupVisibility() {
    this.groupTargets.forEach(group => {
      const visibleItems = group.querySelectorAll(
        `[data-list-filter-target="item"]:not(.${this.filteredClass})`
      )

      if (visibleItems.length === 0) {
        group.classList.add(this.hiddenClass)
      } else {
        group.classList.remove(this.hiddenClass)
      }
    })
  }

  updateResultsCount(count, query) {
    if (count > 0) {
      if (this.hasResultsCountTarget) {
        const text = count === 1 ? this.singularTextValue : this.pluralTextValue
        this.resultsCountTarget.innerHTML = `<span class="highlight">${count}</span> ${text}`
      }
      this.hideNoResults()
    } else {
      if (this.hasResultsCountTarget) {
        this.resultsCountTarget.innerHTML = ""
      }
      this.showNoResults(query)
    }
  }

  clearResultsCount() {
    if (this.hasResultsCountTarget) {
      this.resultsCountTarget.innerHTML = ""
    }
  }

  showNoResults(query) {
    if (this.hasNoResultsTarget) {
      this.noResultsTarget.classList.remove(this.hiddenClass)
    }
    if (this.hasNoResultsTextTarget) {
      this.noResultsTextTarget.textContent = `${this.noMatchTextValue} "${query}"`
    }
  }

  hideNoResults() {
    if (this.hasNoResultsTarget) {
      this.noResultsTarget.classList.add(this.hiddenClass)
    }
  }

  showClearButton() {
    if (this.hasClearTarget) {
      this.clearTarget.classList.add(this.visibleClass)
    }
  }

  hideClearButton() {
    if (this.hasClearTarget) {
      this.clearTarget.classList.remove(this.visibleClass)
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Private: Alphabet Navigation
  // ─────────────────────────────────────────────────────────────

  buildAvailableLetters() {
    this.availableLetters = new Set()
    this.groupTargets.forEach(group => {
      if (group.dataset.letter) {
        this.availableLetters.add(group.dataset.letter)
      }
    })
  }

  disableEmptyLetters() {
    this.alphabetLinkTargets.forEach(link => {
      if (!this.availableLetters.has(link.dataset.letter)) {
        link.classList.add(this.disabledClass)
      }
    })
  }

  updateAlphabetNav() {
    this.alphabetLinkTargets.forEach(link => {
      const letter = link.dataset.letter
      const group = this.groupTargets.find(g => g.dataset.letter === letter)

      if (group && !group.classList.contains(this.hiddenClass)) {
        link.classList.remove(this.disabledClass)
      } else {
        link.classList.add(this.disabledClass)
      }
    })
  }

  resetAlphabetNav() {
    this.alphabetLinkTargets.forEach(link => {
      link.classList.remove(this.disabledClass)
      if (!this.availableLetters.has(link.dataset.letter)) {
        link.classList.add(this.disabledClass)
      }
    })
  }

  // ─────────────────────────────────────────────────────────────
  // Private: Keyboard Shortcuts
  // ─────────────────────────────────────────────────────────────

  bindKeyboardShortcuts() {
    this.handleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.handleKeydown)
  }

  unbindKeyboardShortcuts() {
    document.removeEventListener("keydown", this.handleKeydown)
  }

  handleKeydown(event) {
    // Escape to clear and blur
    if (event.key === "Escape" && this.hasInputTarget && document.activeElement === this.inputTarget) {
      this.clearSearch()
      this.inputTarget.blur()
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Private: Utilities
  // ─────────────────────────────────────────────────────────────

  get camelizedSearchAttribute() {
    // Convert "composer-name" to "composerName" for dataset access
    return this.searchAttributeValue.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())
  }
}
