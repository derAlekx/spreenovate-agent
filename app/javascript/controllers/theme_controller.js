import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.applyTheme()
    this.mediaQuery = window.matchMedia("(prefers-color-scheme: dark)")
    this.mediaQuery.addEventListener("change", this.onSystemChange)
  }

  disconnect() {
    this.mediaQuery?.removeEventListener("change", this.onSystemChange)
  }

  toggle() {
    const isDark = document.documentElement.classList.contains("dark")
    const newTheme = isDark ? "light" : "dark"
    localStorage.setItem("theme", newTheme)
    this.applyTheme()
  }

  applyTheme() {
    const stored = localStorage.getItem("theme")
    const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches
    const dark = stored ? stored === "dark" : prefersDark

    document.documentElement.classList.toggle("dark", dark)
  }

  onSystemChange = () => {
    if (!localStorage.getItem("theme")) {
      this.applyTheme()
    }
  }
}
