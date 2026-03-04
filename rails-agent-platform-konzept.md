# Spreenovate Agent Platform — Architektur-Konzept

## Kontext

Aktuell läuft der Cold-Email-Workflow über OpenClaw/Claude CoWork (siehe `cold-email-workflow-openclaw.md`): CSV-Import, Opus-Subagent recherchiert, Draft schreiben, manuell approven, senden. Funktioniert, ist aber an einen einzigen Workflow und ein CLI-Tool gebunden.

Ziel: Eine eigene Rails-WebApp, die als **generisches Agent-Pipeline-System** funktioniert. Jeder Workflow (Cold Emailing, Reddit Monitoring, Blog Writing, Landingpage-Optimierung, ...) wird als Pipeline mit Steps abgebildet. Neue Workflows brauchen keine Code-Änderungen — nur Konfiguration.

---

## Tech Stack

| Komponente | Technologie | Warum |
|---|---|---|
| Framework | **Rails 8** | Convention over Configuration, Solid Queue built-in, schnelle Entwicklung |
| Datenbank | **SQLite + JSON** | Kein Setup, ein File, Rails 8 first-class. Reicht für 100K+ Items |
| Background Jobs | **Solid Queue** (Rails 8 built-in) | Läuft auf SQLite, kein Redis nötig |
| AI | **Claude Opus 4.6 API** | Research + Drafting. ~$0,23 pro Kontakt |
| Agent Memory | **.md Files** im Filesystem | Human-readable, git-versioniert, Agent liest/schreibt direkt |
| Frontend | **Hotwire (Turbo + Stimulus)** | Kein JavaScript-Framework nötig, trotzdem reaktiv |
| CSS | **Tailwind CSS** | Konsistent mit bestehendem spreenovate.de Design |
| Deployment | **Hetzner VPS + Tailscale** | Günstig, privat, kein öffentliches Internet nötig |

---

## Datenmodell

### Kernidee

Jeder Workflow folgt dem gleichen Muster: Items kommen rein, durchlaufen Steps, an manchen Steps sitzt eine KI, an manchen ein Mensch. Die item-spezifischen Daten leben in einer JSON-Spalte — egal ob es ein Kontakt, ein Reddit-Post oder ein Blog-Entwurf ist. Keine Schema-Änderung bei neuem Workflow.

### Tabellen

```ruby
# 0. Credentials — Globaler Credential Store (projektübergreifend)
create_table :credentials do |t|
  t.string :key, null: false             # "anthropic_api_key", "brave_search_key", "smtp_sendgrid"
  t.text   :value, null: false           # Verschlüsselt (Rails ActiveRecord Encryption)
  t.string :description                  # "Claude API Key (Hauptaccount)", "Brave Search API"
  t.timestamps
end

add_index :credentials, :key, unique: true

# 1. Projects — Brand / Kunde / Mandant
create_table :projects do |t|
  t.string :name, null: false            # "spreenovate", "andere Marke"
  t.json   :settings                     # Unkritische Settings (From-Adresse, Timezone, etc.)
  t.text   :secrets                      # Verschlüsselt: projekt-spezifische Overrides (z.B. eigener SMTP)
  t.timestamps
end

# 1b. Project Credentials — Welche globalen Credentials nutzt ein Projekt?
create_table :project_credentials do |t|
  t.references :project, null: false, foreign_key: true
  t.references :credential, null: false, foreign_key: true
  t.string     :role, null: false        # "ai_api_key", "search_api_key", "smtp", "crm_api_key"
  t.timestamps
end

add_index :project_credentials, [:project_id, :role], unique: true

# 2. Pipelines — Workflow-Typ innerhalb eines Projekts
create_table :pipelines do |t|
  t.references :project, null: false, foreign_key: true
  t.string     :name, null: false        # "Cold Emailing", "Reddit Monitoring"
  t.string     :slug, null: false        # "cold-emailing", "reddit-monitoring"
  t.json       :config                   # Pipeline-spezifische Config
  t.timestamps
end

# 3. Pipeline Steps — Die einzelnen Schritte
create_table :pipeline_steps do |t|
  t.references :pipeline, null: false, foreign_key: true
  t.string     :name, null: false        # "Import", "Research", "Draft", "Review", "Send"
  t.string     :step_type, null: false   # "csv_import", "ai_agent", "human_review", "send_email", "webhook"
  t.integer    :position, null: false    # Reihenfolge
  t.json       :config                   # Prompt-Template, Model, API-Config, etc.
  t.timestamps
end

# 4. Items — Das Herzstück. Ein Item = ein Kontakt / Post / Blog / was auch immer.
create_table :items do |t|
  t.references :pipeline, null: false, foreign_key: true
  t.references :current_step, foreign_key: { to_table: :pipeline_steps }
  t.string     :status, null: false, default: "pending"  # pending, processing, done, approved, rejected, failed, sent
  t.json       :data, null: false, default: {}            # ALLE item-spezifischen Daten
  t.timestamps
end

# 5. Item Events — History: Was ist bei jedem Step passiert
create_table :item_events do |t|
  t.references :item, null: false, foreign_key: true
  t.references :pipeline_step, foreign_key: true
  t.string     :event_type, null: false  # "created", "ai_completed", "human_approved", "human_rejected", "sent", "error"
  t.json       :snapshot                 # Data-Snapshot zum Zeitpunkt des Events
  t.text       :note                     # Optionaler Kommentar (z.B. Reject-Grund)
  t.timestamps
end
```

### JSON Indexes (SQLite)

```sql
-- Duplikat-Check für Emails (Cold Email Pipeline)
CREATE UNIQUE INDEX idx_items_pipeline_email
  ON items(pipeline_id, json_extract(data, '$.email'))
  WHERE json_extract(data, '$.email') IS NOT NULL;

-- Filtern nach Firma
CREATE INDEX idx_items_company
  ON items(json_extract(data, '$.company'))
  WHERE json_extract(data, '$.company') IS NOT NULL;

-- Status + Pipeline (häufigstes Query: "alle pending Items einer Pipeline")
CREATE INDEX idx_items_pipeline_status
  ON items(pipeline_id, status);
```

Wichtig: JSON Indexes werden in Migrations mit `execute` erstellt. Queries müssen exakt `json_extract(data, '$.email')` verwenden damit der Index greift. Dafür Scopes im Model definieren:

```ruby
class Item < ApplicationRecord
  scope :by_email, ->(email) { where("json_extract(data, '$.email') = ?", email) }
  scope :by_company, ->(company) { where("json_extract(data, '$.company') = ?", company) }
  scope :pending, -> { where(status: "pending") }
  scope :for_review, -> { where(status: "review") }
end
```

### Credentials & Secrets

Sensible Daten (API Keys, Passwörter) werden **nicht** in JSON-Config-Spalten gespeichert, sondern in verschlüsselten Spalten mit Rails ActiveRecord Encryption.

#### Architektur: Global vs. Projekt-spezifisch

```
┌──────────────────────────────────────────────────────────────────┐
│  Credentials (global, verschlüsselt)                            │
│                                                                  │
│  key: "anthropic_api_key"    value: "sk-ant-..."                │
│  key: "brave_search_key"     value: "BSA..."                    │
│  key: "smtp_sendgrid"        value: "SG.xxxxx"                  │
│  key: "smtp_mailgun_brandx"  value: "mg-xxxxx"                  │
└──────────┬──────────────────────────┬────────────────────────────┘
           │                          │
    ┌──────▼───────┐          ┌───────▼──────┐
    │ Project:     │          │ Project:     │
    │ spreenovate  │          │ brand-x      │
    │              │          │              │
    │ Rollen:      │          │ Rollen:      │
    │  ai_api_key  │──┐      │  ai_api_key  │──┐
    │  search_key  │──┤      │  search_key  │──┤  (gleiche Credentials,
    │  smtp        │──┤      │  smtp        │──┘   andere Rolle-Zuordnung)
    └──────────────┘  │      └──────────────┘
                      │
              Alle zeigen auf
              denselben Claude Key
```

Jedes Projekt referenziert globale Credentials über eine **Rollen-Zuordnung** (`project_credentials`). So nutzen beide Projekte denselben Claude API Key, können aber unterschiedliche SMTP-Server haben.

#### Models

```ruby
class Credential < ApplicationRecord
  encrypts :value  # verschlüsselt at rest in SQLite

  has_many :project_credentials, dependent: :restrict_with_error
  has_many :projects, through: :project_credentials
end

class ProjectCredential < ApplicationRecord
  belongs_to :project
  belongs_to :credential

  # role: "ai_api_key", "search_api_key", "smtp", "crm_api_key"
end

class Project < ApplicationRecord
  has_many :project_credentials, dependent: :destroy
  has_many :credentials, through: :project_credentials

  encrypts :secrets  # projekt-spezifische Overrides (selten gebraucht)

  def credential_for(role)
    project_credentials.find_by(role: role)&.credential&.value
  end
end
```

#### Nutzung in Step Executors

```ruby
class StepExecutors::AiAgent < StepExecutors::Base
  def execute
    project = item.pipeline.project
    api_key = project.credential_for("ai_api_key")

    result = ClaudeClient.call(
      api_key: api_key,
      model: step.config["model"],
      prompt: build_prompt
    )
    item.update!(data: item.data.merge(result))
    item.advance_to_next_step!
  end
end
```

#### Admin-UI

```
┌─────────────────────────────────────────────────────────────────────┐
│ Credentials (global)                                     [+ Neu]   │
├─────────────────────────────────────────────────────────────────────┤
│ anthropic_api_key    │ sk-ant-•••••••••  │ Claude API Key     [Edit]│
│ brave_search_key     │ BSA-•••••••••     │ Brave Search       [Edit]│
│ smtp_sendgrid        │ SG.•••••••••      │ Sendgrid           [Edit]│
│ smtp_mailgun_brandx  │ mg-•••••••••      │ Mailgun Brand X    [Edit]│
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ Project: spreenovate — Credential-Zuordnung                        │
├─────────────────────────────────────────────────────────────────────┤
│ Rolle           │ Credential             │                         │
│ ai_api_key      │ [anthropic_api_key ▾]  │  ← Dropdown aller Keys │
│ search_api_key  │ [brave_search_key  ▾]  │                         │
│ smtp            │ [smtp_sendgrid     ▾]  │                         │
└─────────────────────────────────────────────────────────────────────┘
```

Neuer API Key? → Credential anlegen → Projekten zuordnen → fertig. Kein Deploy.
Gleicher Key für 5 Projekte? → Alle zeigen auf dasselbe Credential.
Key rotieren? → Ein Credential updaten → alle Projekte die es nutzen haben sofort den neuen Key.

#### Setup (einmalig)

```bash
# Rails Encryption initialisieren
bin/rails db:encryption:init

# Generiert 3 Werte die als Env Vars auf den Server müssen:
# RAILS_MASTER_KEY (oder config/credentials/production.key)
# ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
# ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
# ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
```

Diese 3-4 Env Vars sind das einzige was auf dem Hetzner Server als Environment konfiguriert werden muss. Alles andere lebt verschlüsselt in der DB.

### Beispiel-Daten im JSON

**Cold Email Item:**
```json
{
  "name": "Klaus Haddick",
  "email": "haddick@dnla.de",
  "company": "DNLA GmbH",
  "title": "Managing Director",
  "website": "dnla.de",
  "source": "apollo_csv",
  "research": {
    "summary": "DNLA GmbH entwickelt Personaldiagnostik-Tools...",
    "pain_points": ["KI-basierte Assessment-Konkurrenz", "..."],
    "hook_angle": "Sein eigenes Produkt vs. KI-Assessments"
  },
  "draft": {
    "subject": "Wenn KI Sozialkompetenz misst — Konkurrenz oder Ergänzung?",
    "body": "Hallo Herr Haddick, ...",
    "version": 1
  },
  "sent_at": null
}
```

**Reddit Monitoring Item:**
```json
{
  "subreddit": "r/smallbusiness",
  "post_url": "https://reddit.com/r/smallbusiness/...",
  "post_title": "How do you actually use AI in your business?",
  "post_author": "u/startup_mike",
  "post_score": 142,
  "relevance_score": 0.87,
  "draft_response": "Great question. We've found that...",
  "posted_at": null
}
```

**Blog Item:**
```json
{
  "topic": "5 KI-Workflows die jedes KMU sofort nutzen kann",
  "target_keywords": ["KI KMU", "AI Workflow Mittelstand"],
  "outline": ["Intro", "Rechnungsablage", "Support-Triage", "..."],
  "draft_markdown": "# 5 KI-Workflows...",
  "word_count": 1200,
  "published_at": null
}
```

Eine Tabelle, ein Model, unendliche Flexibilität.

---

## Agent Memory System

Neben der Datenbank (operative Daten) gibt es .md-basierte Memory Files (Agent-Intelligenz). Diese machen den Agenten über Zeit besser.

### Verzeichnisstruktur

```
agent_memory/
├── global/
│   └── MEMORY.md                          # Übergreifende Regeln
│
├── spreenovate--cold-emailing/
│   ├── MEMORY.md                          # Pipeline-spezifisches Wissen
│   ├── STYLE_GUIDE.md                     # Tonalität (= cold-email-konzept.md)
│   └── memory/
│       ├── 2026-03-03.md                  # Tagesnotizen
│       └── 2026-03-04.md
│
├── spreenovate--reddit-monitoring/
│   ├── MEMORY.md
│   └── memory/
│
└── other-brand--cold-emailing/
    ├── MEMORY.md                          # Andere Tonalität, anderer Style
    ├── STYLE_GUIDE.md
    └── memory/
```

### Was wo gespeichert wird

| Datentyp | Speicherort | Beispiel |
|---|---|---|
| Kontakt, Draft, Status | **SQLite (items.data)** | `{"name": "Klaus", "email": "...", "draft": {...}}` |
| Tonalität, Muster, Learnings | **MEMORY.md** | "FOMO-Angle funktioniert besser als Workflow-Pitch" |
| Tagesereignisse, Feedback | **memory/YYYY-MM-DD.md** | "8/10 Drafts approved, 2 rejected weil zu generisch" |
| Style Guide, Prompt-Templates | **STYLE_GUIDE.md** | Aufbau, Checkliste, Beispiel-Email |

### Memory-Flow bei einem Batch

```
1. Agent startet Batch (10 Kontakte)
2. Lädt: MEMORY.md + STYLE_GUIDE.md + heutige Tagesnotiz
3. Pro Kontakt: Research → Draft (mit Memory als Kontext)
4. Nach Batch: Schreibt Tagesnotiz (was passiert ist)
5. Nach Human Review: Updated MEMORY.md (was approved/rejected wurde und warum)
```

Token-Budget pro Agent Call:
- MEMORY.md: ~2.000 Tokens (max. 3.000, regelmäßig kürzen)
- STYLE_GUIDE.md: ~1.500 Tokens
- Tagesnotiz: ~500 Tokens
- Kontakt-Daten: ~200 Tokens
- **Gesamt Kontext: ~4.200 Tokens** — kein Context-Window-Problem

---

## Pipeline Execution Engine

### Step Types

Jeder Pipeline Step hat einen `step_type` der bestimmt, was passiert:

```ruby
# app/services/step_executors/base.rb
class StepExecutors::Base
  def initialize(item, step)
    @item = item
    @step = step
  end

  def execute
    raise NotImplementedError
  end
end

# app/services/step_executors/ai_agent.rb
class StepExecutors::AiAgent < StepExecutors::Base
  def execute
    memory = AgentMemory.load(item.pipeline)
    prompt = build_prompt(item, step.config, memory)
    result = ClaudeClient.call(model: "claude-opus-4-6-20250219", prompt: prompt)
    item.update!(data: item.data.merge(result))
    item.advance_to_next_step!
  end
end

# app/services/step_executors/human_review.rb
class StepExecutors::HumanReview < StepExecutors::Base
  def execute
    item.update!(status: "review")
    # Wartet auf menschliche Aktion im UI
    # UI zeigt Draft, Approve/Reject/Edit Buttons
  end
end

# app/services/step_executors/send_email.rb
class StepExecutors::SendEmail < StepExecutors::Base
  def execute
    OutboundMailer.cold_email(
      to: item.data["email"],
      subject: item.data.dig("draft", "subject"),
      body: item.data.dig("draft", "body"),
      from: step.config["from_address"]
    ).deliver_later
    item.update!(data: item.data.merge("sent_at" => Time.current.iso8601))
    item.advance_to_next_step!
  end
end

# app/services/step_executors/csv_import.rb
# app/services/step_executors/webhook.rb
# app/services/step_executors/api_pull.rb (Reddit, Apollo, etc.)
```

### Item Lifecycle

```
                    ┌─────────┐
                    │ pending │ (nach Import)
                    └────┬────┘
                         │ Solid Queue Job
                    ┌────▼─────┐
                    │processing│ (AI Research läuft)
                    └────┬─────┘
                         │ AI fertig
                    ┌────▼────┐
                    │ review  │ (Draft wartet auf Mensch)
                    └──┬───┬──┘
              Approve  │   │  Reject
                 ┌─────▼┐ ┌▼──────┐
                 │ done  │ │pending│ (zurück in Queue, neuer Draft)
                 └───┬───┘ └──────┘
                     │ Send Job
                 ┌───▼──┐
                 │ sent  │
                 └──────┘
```

### Background Jobs (Solid Queue)

```ruby
# app/jobs/process_item_job.rb
class ProcessItemJob < ApplicationJob
  queue_as :default

  def perform(item_id)
    item = Item.find(item_id)
    step = item.current_step
    executor = StepExecutors.for(step.step_type).new(item, step)
    executor.execute
  rescue => e
    item.update!(status: "failed")
    item.item_events.create!(event_type: "error", note: e.message)
  end
end

# app/jobs/batch_import_job.rb
class BatchImportJob < ApplicationJob
  queue_as :default

  def perform(pipeline_id, csv_content)
    pipeline = Pipeline.find(pipeline_id)
    first_step = pipeline.pipeline_steps.order(:position).first

    CSV.parse(csv_content, headers: true).each do |row|
      next if Item.where(pipeline: pipeline)
               .where("json_extract(data, '$.email') = ?", row["email"])
               .exists?

      item = Item.create!(
        pipeline: pipeline,
        current_step: first_step,
        status: "pending",
        data: row.to_h
      )
      ProcessItemJob.perform_later(item.id)
    end
  end
end

# app/jobs/memory_update_job.rb
class MemoryUpdateJob < ApplicationJob
  queue_as :low

  def perform(pipeline_id, batch_results)
    pipeline = Pipeline.find(pipeline_id)
    AgentMemory.update_daily_log(pipeline, batch_results)
    # Nach Reviews auch MEMORY.md updaten mit approve/reject Patterns
  end
end
```

---

## UI (Kanban-Style)

Jede Pipeline wird als Kanban-Board dargestellt. Spalten = Steps, Karten = Items.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Cold Emailing — spreenovate                                    [Import CSV] │
├─────────────┬──────────────┬──────────────┬─────────────┬──────────────────┤
│  Imported   │  Researched  │   Review     │   Approved  │      Sent        │
│  (pending)  │  (processed) │  (review)    │   (done)    │     (sent)       │
├─────────────┼──────────────┼──────────────┼─────────────┼──────────────────┤
│ ┌─────────┐ │              │ ┌──────────┐ │             │ ┌──────────────┐ │
│ │ Thomas  │ │              │ │ Klaus    │ │             │ │ Stefan       │ │
│ │ Startup │ │              │ │ DNLA     │ │             │ │ Digital Vik. │ │
│ │ .io     │ │              │ │ [✓] [✗]  │ │             │ │ 03.03. 08:12 │ │
│ └─────────┘ │              │ │ [Edit]   │ │             │ └──────────────┘ │
│ ┌─────────┐ │              │ └──────────┘ │             │ ┌──────────────┐ │
│ │ Anna    │ │              │ ┌──────────┐ │             │ │ Lisa         │ │
│ │ SaaS AG │ │              │ │ Maria    │ │             │ │ E-Commerce   │ │
│ │         │ │              │ │ HR Tools │ │             │ │ 03.03. 08:14 │ │
│ └─────────┘ │              │ │ [✓] [✗]  │ │             │ └──────────────┘ │
│             │              │ │ [Edit]   │ │             │                  │
│             │              │ └──────────┘ │             │                  │
└─────────────┴──────────────┴──────────────┴─────────────┴──────────────────┘
```

Die Review-Karte zeigt:
- Kontakt-Info (Name, Firma, Titel)
- Research-Summary (klappbar)
- Email-Draft (Subject + Body)
- Approve / Reject / Edit Buttons
- Bei Edit: Inline-Editor, danach Approve

Turbo Frames machen das reaktiv ohne Page Reload. Approve klicken → Karte wandert nach rechts → nächster Draft erscheint.

---

## Erste Pipeline: Cold Emailing

### Step-Konfiguration

```ruby
# db/seeds.rb oder Admin-UI

project = Project.create!(name: "spreenovate")

pipeline = project.pipelines.create!(
  name: "Cold Emailing",
  slug: "cold-emailing"
)

pipeline.pipeline_steps.create!([
  {
    name: "Import",
    step_type: "csv_import",
    position: 1,
    config: {}
  },
  {
    name: "Research",
    step_type: "ai_agent",
    position: 2,
    config: {
      model: "claude-opus-4-6-20250219",
      task: "research",
      prompt_template: "Recherchiere die Person und das Unternehmen. Finde: 1) Was macht das Unternehmen genau? 2) Was ist die Rolle der Person? 3) Gibt es einen KI-Bezug? 4) Was ist der wahrscheinlichste Pain Point in Bezug auf KI?"
    }
  },
  {
    name: "Draft",
    step_type: "ai_agent",
    position: 3,
    config: {
      model: "claude-opus-4-6-20250219",
      task: "draft",
      prompt_template: "Schreibe eine personalisierte Cold Email auf Deutsch. Nutze den Style Guide und die Research-Ergebnisse. Max. 120 Wörter Body.",
      uses_memory: true,
      uses_style_guide: true
    }
  },
  {
    name: "Review",
    step_type: "human_review",
    position: 4,
    config: {}
  },
  {
    name: "Send",
    step_type: "send_email",
    position: 5,
    config: {
      from_address: "alexander@spreenovate.de",
      signature: "Beste Grüße\nAlexander Kamphorst"
    }
  }
])
```

### Migration vom aktuellen OpenClaw-Workflow

Der Style Guide (`cold-email-konzept.md`) wird 1:1 als `STYLE_GUIDE.md` in die Agent Memory übernommen. Die bestehenden CSV-Kontakte werden einmalig importiert. Der Ablauf bleibt gleich — nur mit UI statt Slack.

---

## Neue Pipeline anlegen (Beispiel: Reddit Monitoring)

Keine Migration, kein neues Model, kein neuer Controller. Nur Konfiguration:

```ruby
pipeline = project.pipelines.create!(
  name: "Reddit Monitoring",
  slug: "reddit-monitoring"
)

pipeline.pipeline_steps.create!([
  {
    name: "Fetch Posts",
    step_type: "api_pull",
    position: 1,
    config: {
      source: "reddit",
      subreddits: ["smallbusiness", "entrepreneur", "artificialintelligence"],
      keywords: ["AI consulting", "KI Beratung", "AI workflow"],
      schedule: "daily"
    }
  },
  {
    name: "Relevanz-Check",
    step_type: "ai_agent",
    position: 2,
    config: {
      model: "claude-opus-4-6-20250219",
      task: "score_relevance",
      prompt_template: "Bewerte den Post auf Relevanz für spreenovate (0-1). Nur Posts mit Score > 0.7 weitergeben.",
      auto_advance_if: "relevance_score > 0.7"
    }
  },
  {
    name: "Draft Response",
    step_type: "ai_agent",
    position: 3,
    config: {
      model: "claude-opus-4-6-20250219",
      task: "draft",
      prompt_template: "Schreibe eine hilfreiche, nicht-werbliche Antwort auf den Reddit-Post."
    }
  },
  {
    name: "Review",
    step_type: "human_review",
    position: 4,
    config: {}
  },
  {
    name: "Post",
    step_type: "webhook",
    position: 5,
    config: { url: "reddit_api", action: "comment" }
  }
])
```

Gleiches UI, gleiches Kanban-Board, gleiche Approve/Reject Buttons. Nur die Daten im JSON sind andere.

---

## Kosten

### Claude API (Opus 4.6)

| | Input | Output |
|---|---|---|
| Preis pro Million Tokens | $5 | $25 |
| Cache Hits | $0,50/MTok | — |

### Pro Cold-Email-Kontakt

| Step | Input Tokens | Output Tokens | Kosten |
|---|---|---|---|
| Research (3-4 Web-Searches) | ~18.000 | ~4.000 | $0,19 |
| Draft | ~6.000 | ~400 | $0,04 |
| Memory Update (÷10) | ~400 | ~80 | $0,004 |
| **Total** | **~24.400** | **~4.480** | **~$0,23** |

### Monatliche Kosten

| Szenario | API-Kosten | Hetzner VPS | Total |
|---|---|---|---|
| 10 Kontakte/Tag | ~$46/Monat | €4,50/Monat | **~$51/Monat** |
| 5 Kontakte/Tag | ~$23/Monat | €4,50/Monat | **~$28/Monat** |

Mit Prompt Caching (System-Prompt + Memory cached über Batch): ~15% günstiger.

---

## Deployment

### Phase 1: Lokal (Entwicklung)

```bash
rails new spreenovate-agent --database=sqlite3
cd spreenovate-agent
bin/rails db:create db:migrate db:seed
bin/dev
```

SQLite File liegt in `db/development.sqlite3`. Alles lokal, kein externer Service.

### Phase 2: Hetzner + Tailscale (Produktion)

```
┌──────────────────────────────────┐
│  Hetzner VPS (CX22, €4,50/Mo)   │
│                                  │
│  ┌────────────────────────────┐  │
│  │  Rails 8 App (Puma)       │  │
│  │  Solid Queue (Background) │  │
│  │  SQLite DB                │  │
│  │  Agent Memory (.md Files) │  │
│  └────────────────────────────┘  │
│                                  │
│  Tailscale IP: 100.x.x.x        │
│  Nicht öffentlich erreichbar     │
└──────────────────────────────────┘
         │
         │ Tailscale VPN
         │
┌────────▼─────────┐
│  Dein Laptop     │
│  Browser →       │
│  100.x.x.x:3000  │
└──────────────────┘
```

- Kein Nginx nötig (Tailscale verschlüsselt)
- Kein SSL-Zertifikat nötig (privates Netzwerk)
- Backup = `scp` der SQLite-Datei + `git push` der Memory Files
- Deploy = `git pull && bin/rails db:migrate && systemctl restart spreenovate`

---

## Zusammenfassung

| Was | Wie |
|---|---|
| Datenbank | SQLite mit JSON-Spalte auf Items. Ein Model für alles. |
| Neue Workflows | Pipeline + Steps konfigurieren, kein Code-Change. |
| Neue Brands | Neues Project anlegen, eigene Pipelines. |
| Credentials | Globaler verschlüsselter Credential Store. Projekte referenzieren per Rolle. Key rotieren = 1x ändern, überall aktiv. Kein Deploy. |
| Agent-Intelligenz | .md Memory Files pro Pipeline. Lernt über Zeit. |
| UI | Kanban-Board pro Pipeline. Turbo Frames für reaktive Updates. |
| Background Jobs | Solid Queue (Rails 8 built-in, läuft auf SQLite). |
| Deployment | Hetzner VPS + Tailscale. Eine Datei, ein Server. |
| Kosten | ~$0,23 pro Kontakt (Opus 4.6) + €4,50/Monat Hosting. |

---

*Erstellt: 03.03.2026*
*Basiert auf: cold-email-workflow-openclaw.md, cold-email-konzept.md*
