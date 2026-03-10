import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "template", "row", "position"]

  add() {
    const html = this.templateTarget.innerHTML
    this.containerTarget.insertAdjacentHTML("beforeend", html)
    this.renumber()
  }

  remove(event) {
    const row = event.target.closest("[data-pipeline-steps-target='row']")
    if (this.rowTargets.length > 1) {
      row.remove()
      this.renumber()
    }
  }

  renumber() {
    this.rowTargets.forEach((row, index) => {
      const posEl = row.querySelector("[data-pipeline-steps-target='position']")
      if (posEl) posEl.textContent = index + 1
    })
  }
}
