import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "template", "row"]

  add() {
    const html = this.templateTarget.innerHTML
    this.containerTarget.insertAdjacentHTML("beforeend", html)
  }

  remove(event) {
    const row = event.target.closest("[data-credential-rows-target='row']")
    if (this.rowTargets.length > 1) {
      row.remove()
    }
  }
}
