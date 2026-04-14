import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  switch({ params: { index } }) {
    this.panelTargets.forEach((panel, i) => {
      panel.classList.toggle("hidden", i !== index)
    })
    this.tabTargets.forEach((tab, i) => {
      if (i === index) {
        tab.classList.remove("bg-gray-100", "dark:bg-neutral-800", "text-gray-500", "dark:text-neutral-400")
        tab.classList.add("bg-gray-900", "dark:bg-neutral-200", "text-white", "dark:text-neutral-900")
      } else {
        tab.classList.remove("bg-gray-900", "dark:bg-neutral-200", "text-white", "dark:text-neutral-900")
        tab.classList.add("bg-gray-100", "dark:bg-neutral-800", "text-gray-500", "dark:text-neutral-400")
      }
    })
  }

  toggleEdit({ params: { index } }) {
    const panel = this.panelTargets[index]
    const display = panel.querySelector(`[data-variant-tabs-target="display${index}"]`)
    const edit = panel.querySelector(`[data-variant-tabs-target="edit${index}"]`)
    if (display && edit) {
      display.classList.toggle("hidden")
      edit.classList.toggle("hidden")
    }
  }

  cancelEdit({ params: { index } }) {
    const panel = this.panelTargets[index]
    const display = panel.querySelector(`[data-variant-tabs-target="display${index}"]`)
    const edit = panel.querySelector(`[data-variant-tabs-target="edit${index}"]`)
    if (display && edit) {
      display.classList.remove("hidden")
      edit.classList.add("hidden")
    }
  }
}
