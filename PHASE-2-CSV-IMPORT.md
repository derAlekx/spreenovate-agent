# Phase 2: CSV Import Executor

## Ziel

Erster funktionierender Executor: CSV hochladen → Items werden in der Pipeline erzeugt. Das beweist, dass das Executor-Pattern funktioniert.

## Voraussetzung

Phase 1 ist abgeschlossen. App startet, Models existieren, Seeds laufen.

## Schritt 1: Executor Base Class

```ruby
# app/services/step_executors/base.rb
module StepExecutors
  class Base
    attr_reader :item, :step

    def initialize(item, step)
      @item = item
      @step = step
    end

    def execute
      raise NotImplementedError, "#{self.class} must implement #execute"
    end
  end

  # Registry: step_type String → Executor Class
  def self.for(step_type)
    {
      "csv_import"    => StepExecutors::CsvImport,
      "ai_agent"      => StepExecutors::AiAgent,
      "human_review"  => StepExecutors::HumanReview,
      "send_email"    => StepExecutors::SendEmail,
      # "api_pull"    => StepExecutors::ApiPull,
      # "webhook"     => StepExecutors::Webhook,
    }.fetch(step_type) { raise "Unknown step_type: #{step_type}" }
  end
end
```

## Schritt 2: CSV Import Executor

```ruby
# app/services/step_executors/csv_import.rb
module StepExecutors
  class CsvImport < Base
    # Dieser Executor wird nicht pro Item aufgerufen, sondern pro Upload.
    # Er erzeugt Items aus CSV-Zeilen.

    def self.import(pipeline:, csv_content:, column_mapping: {})
      require "csv"

      first_step = pipeline.pipeline_steps.order(:position).first
      next_step = pipeline.pipeline_steps.order(:position).second

      imported = 0
      skipped = 0

      CSV.parse(csv_content, headers: true).each do |row|
        data = map_columns(row.to_h, column_mapping)

        # Duplikat-Check per Email
        if data["email"].present? &&
           pipeline.items.by_email(data["email"]).exists?
          skipped += 1
          next
        end

        item = pipeline.items.create!(
          current_step: next_step || first_step,
          status: "pending",
          data: data
        )

        item.item_events.create!(
          pipeline_step: first_step,
          event_type: "created",
          note: "CSV Import"
        )

        imported += 1
      end

      { imported: imported, skipped: skipped }
    end

    private

    def self.map_columns(row_hash, mapping)
      return row_hash if mapping.empty?

      mapped = {}
      mapping.each do |csv_col, internal_col|
        mapped[internal_col] = row_hash[csv_col]
      end
      mapped
    end
  end
end
```

## Schritt 3: Import UI

### Route + Controller

```ruby
# config/routes.rb (ergänzen)
resources :pipelines, only: [:show] do
  member do
    post :import_csv
  end
end
```

```ruby
# app/controllers/pipelines_controller.rb
class PipelinesController < ApplicationController
  def show
    @pipeline = Pipeline.find(params[:id])
    @items = @pipeline.items.includes(:current_step).order(created_at: :desc)
    @steps = @pipeline.pipeline_steps.order(:position)
  end

  def import_csv
    @pipeline = Pipeline.find(params[:id])

    unless params[:csv_file].present?
      redirect_to @pipeline, alert: "Bitte CSV-Datei auswählen."
      return
    end

    csv_content = params[:csv_file].read.force_encoding("UTF-8")

    # Standard-Mapping für Apollo-CSV
    column_mapping = {
      "First Name" => "first_name",
      "Last Name" => "last_name",
      "Title" => "title",
      "Company Name" => "company",
      "Email" => "email"
    }

    # Name zusammenbauen (Apollo hat First/Last getrennt)
    lines = CSV.parse(csv_content, headers: true)
    merged_csv = CSV.generate do |out|
      out << ["name", "email", "company", "title"]
      lines.each do |row|
        name = [row["First Name"], row["Last Name"]].compact.join(" ")
        out << [name, row["Email"], row["Company Name"], row["Title"]]
      end
    end

    result = StepExecutors::CsvImport.import(
      pipeline: @pipeline,
      csv_content: merged_csv
    )

    redirect_to @pipeline,
      notice: "#{result[:imported]} Kontakte importiert, #{result[:skipped]} Duplikate übersprungen."
  end
end
```

### View: Upload-Formular auf Pipeline#show

Auf der Pipeline-Seite ein einfaches Upload-Formular einbauen:

```erb
<%# app/views/pipelines/show.html.erb %>

<div class="max-w-4xl mx-auto p-6">
  <h1 class="text-2xl font-bold mb-2"><%= @pipeline.name %></h1>
  <p class="text-gray-500 mb-6">Projekt: <%= @pipeline.project.name %></p>

  <%# Import-Formular %>
  <div class="bg-gray-50 border rounded-lg p-4 mb-6">
    <h2 class="font-semibold mb-2">CSV Import</h2>
    <%= form_tag import_csv_pipeline_path(@pipeline), multipart: true, class: "flex items-center gap-4" do %>
      <%= file_field_tag :csv_file, accept: ".csv", class: "text-sm" %>
      <%= submit_tag "Importieren", class: "bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 cursor-pointer" %>
    <% end %>
  </div>

  <%# Steps-Übersicht %>
  <div class="flex gap-2 mb-6">
    <% @steps.each do |step| %>
      <div class="bg-white border rounded px-3 py-1 text-sm">
        <span class="font-mono text-gray-400"><%= step.position %>.</span>
        <%= step.name %>
        <span class="text-gray-400 text-xs">(<%= step.step_type %>)</span>
      </div>
    <% end %>
  </div>

  <%# Items-Tabelle %>
  <h2 class="font-semibold mb-2">Items (<%= @items.count %>)</h2>
  <table class="w-full border-collapse">
    <thead>
      <tr class="bg-gray-100 text-left text-sm">
        <th class="p-2 border">Name</th>
        <th class="p-2 border">Company</th>
        <th class="p-2 border">Status</th>
        <th class="p-2 border">Step</th>
      </tr>
    </thead>
    <tbody>
      <% @items.each do |item| %>
        <tr class="hover:bg-gray-50">
          <td class="p-2 border">
            <%= link_to item.data["name"] || "—", item_path(item), class: "text-blue-600 hover:underline" %>
          </td>
          <td class="p-2 border"><%= item.data["company"] || "—" %></td>
          <td class="p-2 border">
            <span class="inline-block px-2 py-0.5 rounded text-xs font-medium
              <%= case item.status
                  when 'pending' then 'bg-gray-200 text-gray-700'
                  when 'processing' then 'bg-yellow-100 text-yellow-800'
                  when 'review' then 'bg-blue-100 text-blue-800'
                  when 'approved' then 'bg-green-100 text-green-800'
                  when 'sent' then 'bg-emerald-100 text-emerald-800'
                  when 'failed' then 'bg-red-100 text-red-800'
                  else 'bg-gray-100'
                  end %>">
              <%= item.status %>
            </span>
          </td>
          <td class="p-2 border text-sm text-gray-500"><%= item.current_step&.name || "—" %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
</div>
```

## Schritt 4: Stub-Executors für die anderen Step Types

Damit nichts crashed, leere Executor-Klassen anlegen:

```ruby
# app/services/step_executors/ai_agent.rb
module StepExecutors
  class AiAgent < Base
    def execute
      # Phase 4
      raise "AiAgent Executor noch nicht implementiert"
    end
  end
end

# app/services/step_executors/human_review.rb
module StepExecutors
  class HumanReview < Base
    def execute
      item.update!(status: "review")
    end
  end
end

# app/services/step_executors/send_email.rb
module StepExecutors
  class SendEmail < Base
    def execute
      # Phase 5
      raise "SendEmail Executor noch nicht implementiert"
    end
  end
end
```

## Schritt 5: ProcessItemJob

```ruby
# app/jobs/process_item_job.rb
class ProcessItemJob < ApplicationJob
  queue_as :default

  def perform(item_id)
    item = Item.find(item_id)
    step = item.current_step

    return unless step  # kein Step mehr = fertig

    executor = StepExecutors.for(step.step_type).new(item, step)
    executor.execute
  rescue => e
    item.update!(status: "failed")
    item.item_events.create!(
      pipeline_step: item.current_step,
      event_type: "error",
      note: e.message
    )
    Rails.logger.error("ProcessItemJob failed for Item##{item_id}: #{e.message}")
  end
end
```

## Wichtig: Keine Tests

Schreibe keine Tests. Keine Model-Tests, keine Controller-Tests, keine System-Tests. Nur lauffähigen Code.

## Fertig wenn:

- [ ] CSV-Upload auf Pipeline#show funktioniert
- [ ] Apollo-CSV (mit First Name / Last Name) wird korrekt importiert
- [ ] Items erscheinen in der Tabelle mit Status "pending"
- [ ] Duplikate (gleiche Email) werden übersprungen
- [ ] ItemEvent "created" wird pro Import angelegt
- [ ] Executor Base Class + Registry funktionieren
- [ ] ProcessItemJob existiert und kann Items verarbeiten
