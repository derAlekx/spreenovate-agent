# Phase 4: AI Agent Executor + Claude API

## Ziel

Der AI Agent Executor: Claude API anbinden, Research per Web Search, Email-Drafts generieren, Agent Memory einbauen. Am Ende: CSV importieren → Items werden automatisch recherchiert und Drafts geschrieben → landen im Review.

## Voraussetzung

Phase 3 ist abgeschlossen. Human Review funktioniert, Items können approved/skipped werden.

## Schritt 1: Claude API Client

Nutze das `anthropic` Ruby Gem oder baue einen einfachen HTTP-Client.

```ruby
# Gemfile
gem "anthropic" # oder: gem "faraday" für eigenen Client
```

```ruby
# app/services/claude_client.rb
class ClaudeClient
  API_URL = "https://api.anthropic.com/v1/messages"

  def initialize(api_key:)
    @api_key = api_key
  end

  def call(model:, system:, prompt:, tools: [], max_tokens: 4096)
    messages = [{ role: "user", content: prompt }]

    body = {
      model: model,
      max_tokens: max_tokens,
      system: system,
      messages: messages
    }

    # Tools hinzufügen wenn vorhanden (z.B. web_search)
    body[:tools] = tools if tools.any?

    response = Faraday.post(API_URL) do |req|
      req.headers["Content-Type"] = "application/json"
      req.headers["x-api-key"] = @api_key
      req.headers["anthropic-version"] = "2023-06-01"
      req.body = body.to_json
    end

    parsed = JSON.parse(response.body)

    if response.status != 200
      raise "Claude API Error: #{parsed['error']&.dig('message') || response.body}"
    end

    # Text aus der Response extrahieren
    text_blocks = parsed["content"]
      .select { |c| c["type"] == "text" }
      .map { |c| c["text"] }
      .join("\n")

    { raw_response: parsed, text: text_blocks }
  end
end
```

## Schritt 2: Agent Memory

```ruby
# app/services/agent_memory.rb
class AgentMemory
  BASE_PATH = Rails.root.join("agent_memory")

  def self.load(pipeline)
    dir = memory_dir(pipeline)
    {
      memory: read_file(dir.join("MEMORY.md")),
      style_guide: read_file(dir.join("STYLE_GUIDE.md")),
      daily_log: read_file(dir.join("memory", "#{Date.current}.md"))
    }
  end

  def self.update_daily_log(pipeline, content)
    dir = memory_dir(pipeline)
    log_dir = dir.join("memory")
    FileUtils.mkdir_p(log_dir)
    File.write(log_dir.join("#{Date.current}.md"), content)
  end

  def self.update_memory(pipeline, content)
    dir = memory_dir(pipeline)
    FileUtils.mkdir_p(dir)
    File.write(dir.join("MEMORY.md"), content)
  end

  private

  def self.memory_dir(pipeline)
    BASE_PATH.join("#{pipeline.project.name.parameterize}--#{pipeline.slug}")
  end

  def self.read_file(path)
    File.exist?(path) ? File.read(path) : ""
  end
end
```

### Initiale Memory Files anlegen

```
agent_memory/
└── spreenovate--cold-emailing/
    ├── MEMORY.md        ← Kopie aus dem aktuellen Workflow
    └── STYLE_GUIDE.md   ← Kopie von prompts/email.md
```

Den Inhalt von `prompts/email.md` und `prompts/research.md` aus dem bestehenden Projekt als Basis nehmen.

## Schritt 3: AI Agent Executor

```ruby
# app/services/step_executors/ai_agent.rb
module StepExecutors
  class AiAgent < Base
    def execute
      item.update!(status: "processing")

      project = item.pipeline.project
      api_key = project.credential_for("ai_api_key")

      raise "Kein API Key für Projekt #{project.name}" unless api_key

      client = ClaudeClient.new(api_key: api_key)
      memory = AgentMemory.load(item.pipeline)

      case step.config["task"]
      when "research"
        execute_research(client, memory)
      when "draft"
        execute_draft(client, memory)
      else
        raise "Unbekannter Task: #{step.config['task']}"
      end

      item.item_events.create!(
        pipeline_step: step,
        event_type: "ai_completed",
        snapshot: item.data
      )

      item.advance_to_next_step!
    end

    private

    def execute_research(client, memory)
      system_prompt = build_system_prompt(memory, "research")

      prompt = <<~PROMPT
        Recherchiere die folgende Person und ihr Unternehmen.

        Name: #{item.data['name']}
        Firma: #{item.data['company']}
        Titel: #{item.data['title']}
        Email: #{item.data['email']}

        #{step.config['prompt_template'].present? ? File.read(Rails.root.join(step.config['prompt_template'])) rescue step.config['prompt_template'] : ''}

        Gib das Ergebnis als strukturierten Text zurück:
        - Was macht die Firma?
        - Welche Rolle hat die Person?
        - Aktuelle News oder Entwicklungen?
        - Mögliche Pain Points bzgl. KI?
        - Konkreter Hook für die Ansprache?
      PROMPT

      tools = build_tools
      result = client.call(
        model: step.config["model"] || "claude-opus-4-6-20250219",
        system: system_prompt,
        prompt: prompt,
        tools: tools
      )

      data = item.data.dup
      data["research"] = {
        "summary" => result[:text],
        "researched_at" => Time.current.iso8601
      }
      item.update!(data: data)
    end

    def execute_draft(client, memory)
      system_prompt = build_system_prompt(memory, "draft")

      prompt = <<~PROMPT
        Schreibe eine personalisierte Cold Email für:

        Name: #{item.data['name']}
        Firma: #{item.data['company']}
        Titel: #{item.data['title']}

        Research-Ergebnis:
        #{item.data.dig('research', 'summary')}

        Gib die Email in diesem Format zurück:
        SUBJECT: [Betreffzeile]
        BODY:
        [Email-Text]
      PROMPT

      result = client.call(
        model: step.config["model"] || "claude-opus-4-6-20250219",
        system: system_prompt,
        prompt: prompt,
        tools: []
      )

      # Subject und Body aus der Antwort parsen
      text = result[:text]
      subject = text.match(/SUBJECT:\s*(.+)/)&.captures&.first&.strip || "Kein Betreff"
      body = text.match(/BODY:\s*(.+)/m)&.captures&.first&.strip || text

      data = item.data.dup
      data["draft"] = {
        "subject" => subject,
        "body" => body,
        "drafted_at" => Time.current.iso8601,
        "version" => (data.dig("draft", "version") || 0) + 1
      }
      item.update!(data: data)
    end

    def build_system_prompt(memory, task)
      parts = []
      parts << "Du bist ein KI-Assistent für Spreenovate, eine KI-Beratung aus Berlin."
      parts << "\n## Memory\n#{memory[:memory]}" if memory[:memory].present?
      parts << "\n## Style Guide\n#{memory[:style_guide]}" if memory[:style_guide].present? && task == "draft"
      parts << "\n## Tagesnotizen\n#{memory[:daily_log]}" if memory[:daily_log].present?
      parts.join("\n")
    end

    def build_tools
      tools = []
      if step.config["enable_web_search"]
        tools << { type: "web_search_20250305" }
      end
      tools
    end
  end
end
```

## Schritt 4: Pipeline Processing

Wenn Items importiert werden, sollen sie automatisch die Pipeline durchlaufen:

```ruby
# Ergänze in StepExecutors::CsvImport#import, nach item.create!:
ProcessItemJob.perform_later(item.id)
```

Der ProcessItemJob (aus Phase 2) ruft den Executor auf. Nach Research → advance_to_next_step! → Status "pending" auf Draft-Step → ProcessItemJob wird erneut getriggert.

```ruby
# In Item#advance_to_next_step! ergänzen:
def advance_to_next_step!
  steps = pipeline.pipeline_steps.order(:position)
  current_index = steps.index(current_step)
  next_step = steps[current_index + 1] if current_index

  if next_step
    update!(current_step: next_step, status: "pending")
    # Automatisch weiterverarbeiten, wenn kein Human Review
    ProcessItemJob.perform_later(id) unless next_step.step_type == "human_review"
  else
    update!(current_step: nil, status: "done")
  end
end
```

Bei `human_review` stoppt die Verarbeitung — das Item wartet auf Approve/Skip in der UI.

## Schritt 5: Credential anlegen

Baue eine einfache Admin-Seite oder lege den API Key per Seeds/Console an:

```ruby
# In rails console oder seeds.rb:
credential = Credential.create!(
  key: "anthropic_api_key",
  value: "sk-ant-...",   # Dein echter Key
  description: "Claude API Key"
)

project = Project.find_by(name: "spreenovate")
project.project_credentials.create!(
  credential: credential,
  role: "ai_api_key"
)
```

## Schritt 6: Rate Limiting / Fehlerbehandlung

```ruby
# app/jobs/process_item_job.rb (erweitern)
class ProcessItemJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  # Maximal 5 parallele AI-Calls (Solid Queue Concurrency)
  limits_concurrency to: 5, key: "ai_processing"

  def perform(item_id)
    # ... wie bisher
  end
end
```

## Wichtig: Keine Tests

Schreibe keine Tests. Keine Model-Tests, keine Controller-Tests, keine System-Tests. Nur lauffähigen Code.

## Fertig wenn:

- [ ] Claude API wird erfolgreich aufgerufen
- [ ] Research-Step füllt `data.research.summary` mit Web-Search-Ergebnissen
- [ ] Draft-Step füllt `data.draft.subject` und `data.draft.body`
- [ ] Items stoppen bei Human Review Step
- [ ] Agent Memory wird geladen und als System Prompt mitgegeben
- [ ] Fehler werden abgefangen (Item → status "failed", Error in ItemEvent)
- [ ] Rate Limiting verhindert API-Überlastung
- [ ] End-to-End: CSV Import → Research → Draft → Review UI zeigt fertigen Draft
