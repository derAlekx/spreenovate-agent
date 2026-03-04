# Spreenovate Agent Platform — Build Plan

## Was ist das?

Eine Rails 8 WebApp, die als generisches Agent-Pipeline-System funktioniert. Jeder Workflow (Cold Emailing, Reddit Monitoring, Blog Writing, ...) wird als Pipeline mit Steps abgebildet. Items durchlaufen Steps — an manchen Steps sitzt eine KI, an manchen ein Mensch.

## Architektur-Referenz

Die vollständige Architektur steht in `BRIEFING-WEBAPP.md`. Dieses Dokument hier ist der **Build Plan** — aufgeteilt in 5 Phasen, die nacheinander gebaut werden.

## Phasen

| Phase | Was | Ergebnis |
|-------|-----|----------|
| 1 | Rails Skeleton + Core Models | App startet, Models + Migrations + Seeds stehen, Scaffold-UI zeigt Daten |
| 2 | CSV Import Executor | CSV hochladen → Items werden erzeugt, erster Executor funktioniert |
| 3 | Human Review UI | Liste mit Items, Approve/Skip/Edit, Status-Bar, Filter-Tabs |
| 4 | AI Agent Executor + Claude API | Research + Draft per Claude API, Web Search, Agent Memory |
| 5 | Email Send + Dashboard | SMTP-Versand, Sidebar-Navigation, Project-Übersicht, Credentials-UI |

## Regeln für jede Phase

1. **Nur das bauen was in der Phase steht.** Nicht vorgreifen.
2. **Am Ende jeder Phase muss die App lauffähig sein.** `bin/dev` → Browser → funktioniert.
3. **Keine Tests.** Keine Model-Tests, keine System-Tests, keine Test-Dateien. Nur lauffähiger Code.
4. **Commit nach jeder Phase.** Sauberer Git-Verlauf.

## Tech Stack (für alle Phasen)

- Rails 8, Ruby 3.3+
- SQLite (default Rails 8 DB)
- Solid Queue (Rails 8 built-in, für Background Jobs)
- Hotwire (Turbo + Stimulus) — kein React, kein Vue
- Tailwind CSS
- Keine externen Dienste in Phase 1-3

## Projektname

```bash
rails new spreenovate-agent --database=sqlite3 --css=tailwind
```
