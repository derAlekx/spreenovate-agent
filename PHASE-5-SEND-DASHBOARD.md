# Phase 5: Email Send + Dashboard + Credentials UI

## Ziel

Die App komplett machen: Emails versenden, Sidebar-Navigation mit Projects/Pipelines, Credentials-Verwaltung, Dashboard. Am Ende ist die App produktionsbereit.

## Voraussetzung

Phase 4 ist abgeschlossen. End-to-End Flow funktioniert: Import → Research → Draft → Review.

---

## Teil A: Email Send Executor

### Schritt 1: ActionMailer Setup

```ruby
# app/mailers/outbound_mailer.rb
class OutboundMailer < ApplicationMailer
  def cold_email(to:, subject:, body:, from_name:, from_address:, bcc: nil, signature: nil)
    @body = body
    @signature = signature

    mail(
      to: to,
      from: "#{from_name} <#{from_address}>",
      subject: subject,
      bcc: bcc
    )
  end
end
```

```erb
<%# app/views/outbound_mailer/cold_email.text.erb %>
<%= @body %>
<% if @signature.present? %>


---

<%= @signature %>
<% end %>
```

### Schritt 2: SMTP Credentials aus Project laden

```ruby
# app/services/step_executors/send_email.rb
module StepExecutors
  class SendEmail < Base
    def execute
      project = item.pipeline.project

      # SMTP-Config aus Credentials laden
      smtp_config = JSON.parse(project.credential_for("smtp") || "{}")

      raise "Keine SMTP-Credentials für #{project.name}" if smtp_config.empty?

      to = item.data["email"]
      subject = item.data.dig("draft", "subject")
      body = item.data.dig("draft", "body")
      from_name = step.config["from_name"] || "Alexander Kamphorst"
      from_address = step.config["from_address"] || smtp_config["from_address"]
      bcc = step.config["bcc"]
      signature = step.config["signature"]

      raise "Keine Email-Adresse für Item##{item.id}" unless to.present?
      raise "Kein Draft für Item##{item.id}" unless subject.present? && body.present?

      # SMTP dynamisch konfigurieren
      delivery_settings = {
        address: smtp_config["host"],
        port: smtp_config["port"].to_i,
        user_name: smtp_config["user"],
        password: smtp_config["password"],
        authentication: :login,
        enable_starttls_auto: smtp_config["port"].to_i != 465,
        ssl: smtp_config["port"].to_i == 465
      }

      OutboundMailer.cold_email(
        to: to,
        subject: subject,
        body: body,
        from_name: from_name,
        from_address: from_address,
        bcc: bcc,
        signature: signature
      ).delivery_method(:smtp, delivery_settings).deliver_now

      data = item.data.dup
      data["sent_at"] = Time.current.iso8601
      item.update!(data: data, status: "sent")

      item.item_events.create!(
        pipeline_step: step,
        event_type: "sent",
        note: "Email gesendet an #{to}"
      )
    end
  end
end
```

### Schritt 3: SMTP Credential als JSON

SMTP-Credentials werden als JSON-String in der Credential-Tabelle gespeichert:

```json
{
  "host": "premium60.web-hosting.com",
  "port": 465,
  "user": "alexander.kamphorst@spreenovate.de",
  "password": "...",
  "from_address": "alexander.kamphorst@spreenovate.de"
}
```

### Schritt 4: Send-Button in Review UI

Approved Items bekommen einen "Senden" Button. Alternativ: Bulk-Send für alle approved Items.

```ruby
# In pipeline_items_controller.rb ergänzen:
def send_email
  @item = @pipeline.items.find(params[:id])

  unless @item.status == "approved"
    redirect_to pipeline_path(@pipeline), alert: "Nur approved Items können gesendet werden."
    return
  end

  send_step = @pipeline.pipeline_steps.find_by(step_type: "send_email")
  @item.update!(current_step: send_step)
  ProcessItemJob.perform_later(@item.id)

  respond_to do |format|
    format.turbo_stream
    format.html { redirect_to pipeline_path(@pipeline), notice: "Email wird gesendet..." }
  end
end

# Bulk Send
def bulk_send
  send_step = @pipeline.pipeline_steps.find_by(step_type: "send_email")
  items = @pipeline.items.where(status: "approved")

  items.each do |item|
    item.update!(current_step: send_step)
    ProcessItemJob.perform_later(item.id)
  end

  redirect_to pipeline_path(@pipeline),
    notice: "#{items.count} Emails werden gesendet..."
end
```

### Schritt 5: Testmail-Funktion

Ein Button um eine Testmail an sich selbst zu schicken, bevor man den Batch loslässt:

```ruby
def test_send
  # Nimmt das erste approved Item und schickt es an die eigene Adresse
  @item = @pipeline.items.where(status: "approved").first
  # ... Sendet an config test_email statt an item.data["email"]
end
```

---

## Teil B: Dashboard + Sidebar

### Schritt 1: Layout mit Sidebar

```erb
<%# app/views/layouts/application.html.erb %>
<body class="bg-gray-50 min-h-screen flex">
  <%# Sidebar %>
  <nav class="w-56 bg-white border-r min-h-screen p-4 flex-shrink-0">
    <div class="font-bold text-lg mb-6">Spreenovate</div>

    <% Project.all.each do |project| %>
      <div class="mb-4">
        <div class="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-1">
          <%= project.name %>
        </div>
        <% project.pipelines.each do |pipeline| %>
          <%= link_to pipeline.name,
              pipeline_path(pipeline),
              class: "block py-1 px-2 rounded text-sm #{pipeline.id == @pipeline&.id ? 'bg-blue-50 text-blue-700 font-medium' : 'text-gray-700 hover:bg-gray-50'}" %>
        <% end %>
      </div>
    <% end %>

    <div class="mt-8 pt-4 border-t">
      <%= link_to "Credentials", credentials_path, class: "block py-1 px-2 text-sm text-gray-500 hover:text-gray-700" %>
      <%= link_to "Projects", projects_path, class: "block py-1 px-2 text-sm text-gray-500 hover:text-gray-700" %>
    </div>
  </nav>

  <%# Main Content %>
  <main class="flex-1 p-6">
    <% if notice %><div class="bg-green-50 border-green-200 border rounded p-3 mb-4 text-green-800"><%= notice %></div><% end %>
    <% if alert %><div class="bg-red-50 border-red-200 border rounded p-3 mb-4 text-red-800"><%= alert %></div><% end %>
    <%= yield %>
  </main>
</body>
```

### Schritt 2: Dashboard (Root Page)

```ruby
# config/routes.rb
root "dashboard#index"
```

```ruby
# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  def index
    @projects = Project.all.includes(pipelines: :items)
  end
end
```

```erb
<%# app/views/dashboard/index.html.erb %>
<h1 class="text-2xl font-bold mb-6">Dashboard</h1>

<div class="grid grid-cols-1 md:grid-cols-2 gap-4">
  <% @projects.each do |project| %>
    <% project.pipelines.each do |pipeline| %>
      <div class="bg-white border rounded-lg p-4">
        <div class="text-sm text-gray-500"><%= project.name %></div>
        <h2 class="font-semibold text-lg mb-2">
          <%= link_to pipeline.name, pipeline_path(pipeline), class: "hover:text-blue-600" %>
        </h2>
        <div class="flex gap-4 text-sm">
          <span><%= pipeline.items.count %> total</span>
          <span class="text-blue-600"><%= pipeline.items.where(status: "review").count %> review</span>
          <span class="text-green-600"><%= pipeline.items.where(status: "approved").count %> approved</span>
          <span class="text-emerald-600"><%= pipeline.items.where(status: "sent").count %> sent</span>
          <span class="text-red-600"><%= pipeline.items.where(status: "failed").count %> failed</span>
        </div>
      </div>
    <% end %>
  <% end %>
</div>
```

---

## Teil C: Credentials UI

### Schritt 1: CRUD für Credentials

```ruby
# config/routes.rb
resources :credentials
```

```ruby
# app/controllers/credentials_controller.rb
class CredentialsController < ApplicationController
  def index
    @credentials = Credential.all.order(:key)
  end

  def new
    @credential = Credential.new
  end

  def create
    @credential = Credential.new(credential_params)
    if @credential.save
      redirect_to credentials_path, notice: "Credential erstellt."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @credential = Credential.find(params[:id])
  end

  def update
    @credential = Credential.find(params[:id])
    if @credential.update(credential_params)
      redirect_to credentials_path, notice: "Credential aktualisiert."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @credential = Credential.find(params[:id])
    @credential.destroy
    redirect_to credentials_path, notice: "Credential gelöscht."
  end

  private

  def credential_params
    params.require(:credential).permit(:key, :value, :description)
  end
end
```

### Schritt 2: Credential-Zuordnung pro Project

Auf der Project-Edit-Seite: Dropdown pro Rolle, das ein globales Credential auswählt.

```
┌─────────────────────────────────────────────────────────┐
│ Project: spreenovate — Credentials                       │
├─────────────────────────────────────────────────────────┤
│ AI API Key:      [anthropic_api_key ▾]                  │
│ Search API Key:  [— nicht zugewiesen — ▾]               │
│ SMTP:            [smtp_spreenovate ▾]                   │
└─────────────────────────────────────────────────────────┘
```

---

## Teil D: Deployment-Vorbereitung

### Schritt 1: Procfile + Solid Queue Config

```yaml
# Procfile.dev
web: bin/rails server -p 3000
jobs: bin/jobs
css: bin/rails tailwindcss:watch
```

```yaml
# config/queue.yml
production:
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: "*"
      threads: 3
      processes: 1
      polling_interval: 0.1
```

### Schritt 2: Production Config

```ruby
# config/environments/production.rb
config.active_record.encryption.primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]
config.active_record.encryption.deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"]
config.active_record.encryption.key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]
```

---

## Wichtig: Keine Tests

Schreibe keine Tests. Keine Model-Tests, keine Controller-Tests, keine System-Tests. Nur lauffähigen Code.

## Fertig wenn:

- [ ] Approved Items können per Button gesendet werden
- [ ] Bulk-Send für alle approved Items funktioniert
- [ ] Emails kommen an (Test mit eigener Adresse)
- [ ] SMTP-Credentials kommen aus der DB (nicht hardcoded)
- [ ] Sidebar zeigt alle Projects + Pipelines
- [ ] Dashboard zeigt Übersicht mit Counts
- [ ] Credentials CRUD funktioniert
- [ ] Credential-Zuordnung pro Project funktioniert
- [ ] Testmail-Funktion existiert
- [ ] App ist bereit für Hetzner-Deployment
