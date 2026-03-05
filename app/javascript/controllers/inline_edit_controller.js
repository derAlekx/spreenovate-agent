import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display", "form"]

  toggle() {
    this.displayTarget.classList.toggle("hidden")
    this.formTarget.classList.toggle("hidden")
  }

  cancel() {
    this.displayTarget.classList.remove("hidden")
    this.formTarget.classList.add("hidden")
  }
}
