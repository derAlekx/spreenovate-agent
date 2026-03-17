# Architektur: Connectors & Step Executors

## Überblick

Das System hat drei Schichten für externe Integrationen:

```
┌─────────────────────────────────────────────────┐
│  Step Executors          (Pipeline-Bausteine)    │
│  "Was passiert in diesem Pipeline-Schritt?"      │
├─────────────────────────────────────────────────┤
│  Connectors              (API-Logik)             │
│  "Wie rede ich mit dieser externen API?"         │
├─────────────────────────────────────────────────┤
│  Credentials             (Auth & Secrets)        │
│  "Mit welchem API-Key authentifiziere ich mich?" │
└─────────────────────────────────────────────────┘
```

---

## Schicht 1: Credentials (existiert bereits)

Verschlüsselte Zugangsdaten, pro Projekt zugewiesen über Rollen.

- `Credential` — Schlüssel + verschlüsselter Wert (z.B. API-Key, SMTP-Config)
- `ProjectCredential` — Verknüpft Projekt mit Credential über eine Rolle
- Zugriff: `project.credential_for("ai_api_key")` → gibt entschlüsselten Wert zurück

**Bestehende Rollen:**

| Rolle | Wofür | Format |
|-------|-------|--------|
| `ai_api_key` | Claude API | String (API Key) |
| `smtp` | Email-Versand | JSON (host, port, user, password, ...) |
| `crm_api_key` | Apollo.io (geplant) | String (API Key) |

---

## Schicht 2: Connectors

Ein Connector kapselt die Kommunikation mit einer externen REST API. Er weiß:
- Wohin (Base-URL)
- Wie authentifizieren (API-Key Header, Bearer Token, ...)
- Wie Requests/Responses aussehen (JSON encoding/decoding)
- Wie Fehler behandelt werden

### Aufbau eines Connectors

```
app/services/connectors/
├── apollo/
│   ├── client.rb          # HTTP-Transport (Faraday): Auth, Base-URL, Error-Handling
│   ├── contacts.rb        # Resource: Kontakte suchen, erstellen, updaten
│   ├── search.rb          # Resource: People Search
│   └── fields.rb          # Resource: Custom Fields
└── claude/
    └── client.rb          # Bestehender ClaudeClient, umgezogen hierher
```

### Client = HTTP-Transport

Jeder Connector hat einen `Client`, der Faraday konfiguriert:

```ruby
module Connectors::Apollo
  class Client
    BASE_URL = "https://api.apollo.io"

    def initialize(api_key:)
      @conn = Faraday.new(url: BASE_URL) do |f|
        f.request :json
        f.response :json
        f.headers["x-api-key"] = api_key
      end
    end

    def get(path, params = {})  ... end
    def post(path, body = {})   ... end
  end
end
```

### Resources = API-Endpunkte

Resources nutzen den Client und bilden die API-Logik ab:

```ruby
module Connectors::Apollo
  class Search
    def initialize(client)
      @client = client
    end

    def people(query:, page: 1, per_page: 25)
      @client.post("/api/v1/mixed_people/search", {
        q_keywords: query, page: page, per_page: per_page
      })
    end
  end
end
```

### Was KEIN Connector ist

**SMTP / ActionMailer** ist kein Connector. Rails spricht SMTP nativ über ActionMailer — da ist kein HTTP/REST dazwischen. Der `SendEmail`-Executor nutzt ActionMailer direkt. Erst wenn Email-Versand über eine REST API läuft (SendGrid, Postmark, Resend), wäre das ein Connector.

---

## Schicht 3: Step Executors

Step Executors sind Pipeline-Bausteine. Jeder Executor:
- Erbt von `StepExecutors::Base`
- Implementiert `#execute`
- Bekommt `item` und `step` übergeben
- Wird von `ProcessItemJob` aufgerufen

### Verhältnis Connector ↔ Step Executor: 1:n

Ein Connector kann von mehreren Step Executors genutzt werden:

```
Connectors::Apollo::Client             ← 1 Connector
  ├── StepExecutors::ApolloImport      ← People Search → Items erstellen
  ├── StepExecutors::ApolloSync        ← Pipeline-Status → Apollo zurückschreiben
  └── StepExecutors::ApolloEnrich      ← Email/Name → volle Kontaktdaten holen

Connectors::Claude::Client            ← 1 Connector
  └── StepExecutors::AiAgent           ← Research + Draft per Claude API
```

Der Connector ändert sich nicht, wenn ein neuer Step Executor dazukommt.

### Executor-Beispiel mit Connector

```ruby
class StepExecutors::ApolloImport < StepExecutors::Base
  def execute
    api_key = item.pipeline.project.credential_for("crm_api_key")
    client = Connectors::Apollo::Client.new(api_key: api_key)
    search = Connectors::Apollo::Search.new(client)

    results = search.people(query: step.config["search_query"])
    # → Items erstellen aus Ergebnissen
  end
end
```

---

## Bestehende Step Executors (Phase 5, MVP)

| Step Type | Executor | Nutzt | Funktion |
|-----------|----------|-------|----------|
| `csv_import` | `StepExecutors::CsvImport` | — (Ruby CSV) | CSV parsen → Items erstellen |
| `ai_agent` | `StepExecutors::AiAgent` | `ClaudeClient` | Research + Draft per Claude API |
| `human_review` | `StepExecutors::HumanReview` | — (UI-driven) | Status auf "review" setzen, Mensch entscheidet |
| `send_email` | `StepExecutors::SendEmail` | ActionMailer + SMTP | Email verschicken |

**Geplant (noch nicht implementiert):**

| Step Type | Executor | Nutzt | Funktion |
|-----------|----------|-------|----------|
| `api_pull` | `StepExecutors::ApolloImport` | `Connectors::Apollo` | Kontakte aus Apollo importieren |
| — | `StepExecutors::ApolloSync` | `Connectors::Apollo` | Status nach Apollo zurückschreiben |
| — | `StepExecutors::ApolloEnrich` | `Connectors::Apollo` | Kontaktdaten anreichern |

---

## Execution Flow

```
User/Trigger
  → ProcessItemJob (async, max 5 parallel)
    → StepExecutors.for(step_type)     # Factory: step_type → Executor-Klasse
      → Executor.new(item, step)
        → executor.execute
          → Connector (falls API-Call nötig)
            → Credential (API-Key aus DB)
          → item.advance_to_next_step!
```

---

## Dateistruktur (Ziel)

```
app/services/
├── connectors/
│   ├── apollo/
│   │   ├── client.rb
│   │   ├── contacts.rb
│   │   ├── search.rb
│   │   └── fields.rb
│   └── claude/
│       └── client.rb          ← war: app/services/claude_client.rb
│
├── step_executors/
│   ├── base.rb
│   ├── csv_import.rb
│   ├── ai_agent.rb            ← nutzt Connectors::Claude::Client
│   ├── human_review.rb
│   ├── send_email.rb          ← nutzt ActionMailer direkt (kein Connector)
│   ├── apollo_import.rb       ← nutzt Connectors::Apollo
│   ├── apollo_sync.rb         ← nutzt Connectors::Apollo
│   └── apollo_enrich.rb       ← nutzt Connectors::Apollo
│
└── agent_memory.rb

app/models/
├── credential.rb
├── project_credential.rb
└── ...
```

---

## Regeln

1. **Connectors nur für REST APIs.** SMTP, Datei-Importe etc. brauchen keinen Connector.
2. **Ein Client pro API.** Nicht pro Endpoint — pro externer Service.
3. **Resources gruppieren Endpoints.** `Search`, `Contacts`, `Fields` — jeweils eigene Klasse.
4. **Step Executors sind dünn.** Sie holen Credentials, rufen den Connector auf, verarbeiten das Ergebnis, updaten das Item. Keine API-Logik im Executor.
5. **Credentials kommen immer aus der DB.** Nie hardcoded, nie aus ENV direkt im Connector.
