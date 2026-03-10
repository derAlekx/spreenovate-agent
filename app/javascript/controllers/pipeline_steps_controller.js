import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "template", "row", "position", "pipelineName", "config"]

  static values = {
    templates: { type: Object, default: {} }
  }

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

  applyTemplate(event) {
    const key = event.target.value
    if (!key || !this.templatesValue[key]) return

    const tpl = this.templatesValue[key]

    // Pipeline-Name setzen
    if (this.hasPipelineNameTarget) {
      this.pipelineNameTarget.value = tpl.name
    }

    // Alle bestehenden Rows entfernen
    this.rowTargets.forEach(row => row.remove())

    // Steps aus Template einfügen
    tpl.steps.forEach(step => {
      const html = this.templateTarget.innerHTML
      this.containerTarget.insertAdjacentHTML("beforeend", html)
      const newRow = this.containerTarget.lastElementChild
      newRow.querySelector("input[name='steps[][name]']").value = step.name
      newRow.querySelector("select[name='steps[][step_type]']").value = step.type
      const configInput = newRow.querySelector("input[name='steps[][config]']")
      if (configInput) configInput.value = JSON.stringify(step.config || {})
    })

    this.renumber()
    // Reset dropdown
    event.target.value = ""
  }
}
