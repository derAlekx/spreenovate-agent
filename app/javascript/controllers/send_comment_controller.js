import { Controller } from "@hotwired/stimulus"

// Keeps the textarea value synced into both Send forms' hidden fields
// so either button submits with the same user_comment.
export default class extends Controller {
  static targets = ["input", "hidden"]

  connect() {
    this.sync()
    this.inputTarget.addEventListener("input", () => this.sync())
  }

  sync() {
    const value = this.inputTarget.value
    this.hiddenTargets.forEach((h) => { h.value = value })
  }
}
