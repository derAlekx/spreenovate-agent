# Spreenovate Agent — Context für Claude

Rails 8 App für AI-gestütztes Cold-Email-Outreach. User = Alexander Kamphorst (Co-Founder Spreenovate, Berlin).

## Arbeitsstil (WICHTIG)

Alexander möchte bei allen Entscheidungen mit Alternativen **Optionen mit Vor/Nachteilen aufgelistet bekommen und dann a/b/c wählen**.

Regel für Eigeninitiative vs. Rückfrage:

| Situation | Verhalten |
|---|---|
| Reiner Bug-Fix ohne Alternativen | Direkt machen |
| Recovery-Action die API-Calls/Geld kostet | **Fragen**, Optionen aufzeigen |
| Follow-up-Änderungen an Architektur/Schema | **Fragen** |
| Kleine Polish-Changes (Typo, Formatierung) | Direkt machen |
| Struktureller Refactor | **Fragen** |

Vor größeren Changes: Subagents für Review nutzen (einer technisch, einer inhaltlich bei Prompt-Themen). Vor strukturellen DB-Änderungen: Backup der SQLite.

## Pipeline-Architektur

```
Import (CSV) → Qualify → Research → Draft (A/B) → Review → Send
```

Modelle pro Step (in `step.config["model"]`):

| Step | Modell | Zweck |
|---|---|---|
| Qualify | `claude-haiku-4-5` | Fit-Score 1-5, Auto-Skip bei <3 |
| Research | `claude-opus-4-6` | mit WebSearch, Fakten über Person/Firma |
| Draft A | `claude-opus-4-7` | Kreative Variante |
| Draft B | `claude-sonnet-4-6` | A/B-Vergleich, 40% günstiger |
| Redraft A | `claude-opus-4-7` (default) | Wie Draft A |
| Redraft B | `claude-sonnet-4-6` (konst.) | Wie Draft B |

**Wichtig:** Opus 4.7+ unterstützt `temperature` NICHT mehr (deprecated). `AiAgent.temperature_deprecated?(model)` filtert das. Wenn neue Modelle mit Adaptive Thinking dazukommen: `temperature_deprecated?` Regex erweitern.

## Batch API + Caching

- Batch-Submit + Poll-Job für Research/Draft (Qualify könnte auch sync, läuft aber per Batch).
- `cache_control: { type: "ephemeral" }` **top-level** im Request, NICHT block-level. Begründung: Minimum 4096 Tokens für Opus, 2048 für Sonnet — statischer Teil allein wäre zu klein, Anthropic muss selbst den longest cacheable prefix wählen.
- Anthropic-Version `2023-06-01`, kein Beta-Header (Caching & Batch sind GA).

## Rolling Few-Shot

- `data["marked_excellent"]=true` + `data["user_comment"]` werden beim Approve gesetzt (nicht beim Send).
- `AiAgent.excellent_examples_for(pipeline)` zieht bis zu 5 (approved OR sent) AND marked-excellent Emails und injiziert sie in den Draft-Prompt als Few-Shot (via `{{excellent_examples}}` im dynamischen Teil).
- "Send + Mark Excellent" Button existiert nicht mehr — Mark läuft im Review.

## Prompts

In `agent_memory/spreenovate-cold-emailing--cold-emailing/`:
- `prompt_qualify.md` — Haiku-Klassifizierung
- `prompt_research.md` — Recherche mit WebSearch
- `prompt_draft.md` — Variante A (Opus)
- `prompt_draft_variant_b.md` — Variante B (Sonnet). Aktuell **identisch** zu A (nur Modell unterscheidet sich). Kann später divergieren.

Beim Verändern von Prompt A meist auch B synchronisieren (mit `cp`).

Prompts nutzen `\n---\n` als Separator zwischen statischem (cached) und dynamischem (`{{name}}` etc.) Teil.

Parser für Output akzeptiert `subject:|Betreff:` und `body:|Body:` (beide Orderings, inline Subject im Body wird rausgefiltert).

## Daily Limits & Konventionen

- Daily Send Limit: 10/Tag (Email-Reputation für junge Domain).
- Email-Stil: Deutsch, formell (Sie), "wie unter klugen Bekannten", kein Em-Dash (verboten).
- Zielgruppe: DACH-Mittelstand-Führungskräfte mit KI-Verantwortung.
- Positionierung: Sparringspartner, NICHT Berater/Agentur. Personal Pain (die Person fühlt sich unsicher), nicht Company-Pain.

## Häufige Commands

```bash
# Pipeline Status
bin/rails runner 'Pipeline.first.pipeline_steps.order(:position).each { |s| puts "#{s.name}: #{Pipeline.first.items.where(current_step_id: s.id).group(:status).count}" }'

# Active Batches prüfen
bin/rails runner 'MessageBatch.where(status: ["pending", "processing"]).each { |mb| puts "#{mb.batch_api_id} | #{mb.pipeline_step.name} | #{mb.request_count} items" }'

# Manual Poll
bin/rails runner 'BatchPollJob.perform_now(MessageBatch.last.id)'
```

## Offene Bereiche / TODOs

- Judge-Modell für A/B-Vorauswahl (noch nicht gebaut, mitlaufen lassen als Option erwogen)
- Closer-Qualität ist beste offene Baustelle, Rolling Few-Shot hilft aber
- Alter Pipeline-State: 450 pending auf Qualify warten auf Processing
