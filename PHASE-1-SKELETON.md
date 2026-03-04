# Phase 1: Rails Skeleton + Core Models

## Ziel

Rails App aufsetzen mit allen Core Models, Migrations, Validierungen und einem einfachen Scaffold-UI. Am Ende: App startet, man kann im Browser Projects, Pipelines, Steps und Items sehen und anlegen.

## Schritt 1: Rails App erstellen

```bash
rails new spreenovate-agent --database=sqlite3 --css=tailwind
cd spreenovate-agent
```

## Schritt 2: Models + Migrations

Erstelle diese Models mit den folgenden Migrations. **Wichtig:** Die `data`-Spalte auf Items ist JSON — das ist das Herzstück des Systems. Jedes Item speichert seine Daten (egal ob Kontakt, Reddit-Post, Blog-Entwurf) in diesem JSON-Feld.

### Credential

```ruby
create_table :credentials do |t|
  t.string :key, null: false             # "anthropic_api_key", "brave_search_key", "smtp_sendgrid"
  t.text   :value, null: false           # Verschlüsselt (Rails ActiveRecord Encryption)
  t.string :description                  # "Claude API Key (Hauptaccount)"
  t.timestamps
end

add_index :credentials, :key, unique: true
```

### Project

```ruby
create_table :projects do |t|
  t.string :name, null: false            # "spreenovate", "brand-x"
  t.json   :settings                     # Unkritische Settings
  t.timestamps
end
```

### ProjectCredential (Join-Table)

```ruby
create_table :project_credentials do |t|
  t.references :project, null: false, foreign_key: true
  t.references :credential, null: false, foreign_key: true
  t.string     :role, null: false        # "ai_api_key", "search_api_key", "smtp"
  t.timestamps
end

add_index :project_credentials, [:project_id, :role], unique: true
```

### Pipeline

```ruby
create_table :pipelines do |t|
  t.references :project, null: false, foreign_key: true
  t.string     :name, null: false        # "Cold Emailing"
  t.string     :slug, null: false        # "cold-emailing"
  t.json       :config
  t.timestamps
end
```

### PipelineStep

```ruby
create_table :pipeline_steps do |t|
  t.references :pipeline, null: false, foreign_key: true
  t.string     :name, null: false        # "Import", "Research", "Draft", "Review", "Send"
  t.string     :step_type, null: false   # "csv_import", "ai_agent", "human_review", "send_email", "webhook"
  t.integer    :position, null: false
  t.json       :config                   # Step-spezifische Config (Prompt, Model, etc.)
  t.timestamps
end
```

### Item

```ruby
create_table :items do |t|
  t.references :pipeline, null: false, foreign_key: true
  t.references :current_step, foreign_key: { to_table: :pipeline_steps }
  t.string     :status, null: false, default: "pending"
  t.json       :data, null: false, default: {}
  t.timestamps
end
```

### ItemEvent

```ruby
create_table :item_events do |t|
  t.references :item, null: false, foreign_key: true
  t.references :pipeline_step, foreign_key: true
  t.string     :event_type, null: false  # "created", "ai_completed", "human_approved", "human_rejected", "sent", "error"
  t.json       :snapshot
  t.text       :note
  t.timestamps
end
```

### JSON Indexes (in einer separaten Migration mit `execute`)

```sql
CREATE UNIQUE INDEX idx_items_pipeline_email
  ON items(pipeline_id, json_extract(data, '$.email'))
  WHERE json_extract(data, '$.email') IS NOT NULL;

CREATE INDEX idx_items_company
  ON items(json_extract(data, '$.company'))
  WHERE json_extract(data, '$.company') IS NOT NULL;

CREATE INDEX idx_items_pipeline_status
  ON items(pipeline_id, status);
```

## Schritt 3: Model-Code

### Associations + Validierungen

```ruby
class Credential < ApplicationRecord
  encrypts :value
  validates :key, presence: true, uniqueness: true
  validates :value, presence: true

  has_many :project_credentials, dependent: :restrict_with_error
  has_many :projects, through: :project_credentials
end

class Project < ApplicationRecord
  validates :name, presence: true

  has_many :project_credentials, dependent: :destroy
  has_many :credentials, through: :project_credentials
  has_many :pipelines, dependent: :destroy

  def credential_for(role)
    project_credentials.find_by(role: role)&.credential&.value
  end
end

class ProjectCredential < ApplicationRecord
  belongs_to :project
  belongs_to :credential
  validates :role, presence: true, uniqueness: { scope: :project_id }
end

class Pipeline < ApplicationRecord
  belongs_to :project
  has_many :pipeline_steps, -> { order(:position) }, dependent: :destroy
  has_many :items, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true

  before_validation :generate_slug, if: -> { slug.blank? && name.present? }

  private

  def generate_slug
    self.slug = name.parameterize
  end
end

class PipelineStep < ApplicationRecord
  belongs_to :pipeline
  has_many :items, foreign_key: :current_step_id
  has_many :item_events

  validates :name, presence: true
  validates :step_type, presence: true
  validates :position, presence: true, numericality: { only_integer: true }

  VALID_STEP_TYPES = %w[csv_import ai_agent human_review send_email api_pull webhook].freeze
  validates :step_type, inclusion: { in: VALID_STEP_TYPES }
end

class Item < ApplicationRecord
  belongs_to :pipeline
  belongs_to :current_step, class_name: "PipelineStep", optional: true
  has_many :item_events, dependent: :destroy

  validates :status, presence: true

  VALID_STATUSES = %w[pending processing review done approved rejected failed sent].freeze
  validates :status, inclusion: { in: VALID_STATUSES }

  scope :by_email, ->(email) { where("json_extract(data, '$.email') = ?", email) }
  scope :by_company, ->(company) { where("json_extract(data, '$.company') = ?", company) }
  scope :pending, -> { where(status: "pending") }
  scope :for_review, -> { where(status: "review") }
  scope :approved, -> { where(status: "approved") }

  def advance_to_next_step!
    steps = pipeline.pipeline_steps.order(:position)
    current_index = steps.index(current_step)
    next_step = steps[current_index + 1] if current_index
    if next_step
      update!(current_step: next_step, status: "pending")
    else
      update!(current_step: nil, status: "done")
    end
  end
end

class ItemEvent < ApplicationRecord
  belongs_to :item
  belongs_to :pipeline_step, optional: true

  validates :event_type, presence: true
end
```

## Schritt 4: Seeds (Cold Emailing Pipeline)

```ruby
# db/seeds.rb

project = Project.create!(name: "spreenovate", settings: { timezone: "Europe/Berlin" })

pipeline = project.pipelines.create!(name: "Cold Emailing", slug: "cold-emailing")

pipeline.pipeline_steps.create!([
  { name: "Import",   step_type: "csv_import",    position: 1, config: {} },
  { name: "Research", step_type: "ai_agent",      position: 2, config: { "model" => "claude-opus-4-6-20250219", "task" => "research", "enable_web_search" => true } },
  { name: "Draft",    step_type: "ai_agent",      position: 3, config: { "model" => "claude-opus-4-6-20250219", "task" => "draft", "uses_memory" => true } },
  { name: "Review",   step_type: "human_review",  position: 4, config: {} },
  { name: "Send",     step_type: "send_email",    position: 5, config: { "from_address" => "alexander@spreenovate.de" } }
])

# Ein paar Test-Items damit die UI nicht leer ist
import_step = pipeline.pipeline_steps.find_by(position: 1)
review_step = pipeline.pipeline_steps.find_by(position: 4)

pipeline.items.create!([
  {
    current_step: review_step,
    status: "review",
    data: {
      "name" => "Klaus Haddick",
      "email" => "haddick@dnla.de",
      "company" => "DNLA GmbH",
      "title" => "Managing Director",
      "research" => { "summary" => "DNLA entwickelt Personaldiagnostik-Tools..." },
      "draft" => { "subject" => "Wenn KI Sozialkompetenz misst", "body" => "Hallo Herr Haddick, ..." }
    }
  },
  {
    current_step: import_step,
    status: "pending",
    data: {
      "name" => "Badr Derbali",
      "email" => "badr.derbali@k-recruiting.com",
      "company" => "K-Recruiting Life Sciences",
      "title" => "Senior Recruiting Manager"
    }
  }
])
```

## Schritt 5: Einfaches Scaffold-UI

Baue einfache Scaffold-Views (kein fancy UI nötig, das kommt in Phase 3):

- `GET /projects` — Liste aller Projects
- `GET /projects/:id` — Project-Detail mit seinen Pipelines
- `GET /pipelines/:id` — Pipeline-Detail mit Steps und Items-Tabelle
- `GET /items/:id` — Item-Detail mit JSON-Daten und Events

Root-Route auf `projects#index` setzen.

## Schritt 6: ActiveRecord Encryption einrichten

```bash
bin/rails db:encryption:init
```

Die generierten Keys in `config/credentials.yml.enc` speichern (oder als ENV Vars).

## Wichtig: Keine Tests

Schreibe keine Tests. Keine Model-Tests, keine Controller-Tests, keine System-Tests. Nur lauffähigen Code.

## Fertig wenn:

- [ ] `bin/dev` startet die App ohne Fehler
- [ ] `bin/rails db:migrate db:seed` läuft durch
- [ ] Browser zeigt Projects, Pipelines, Steps, Items
- [ ] Item-Detail zeigt JSON-Daten
- [ ] `Item#advance_to_next_step!` funktioniert (manuell in `rails console` prüfen)
