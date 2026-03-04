# Phase 3: Human Review UI

## Ziel

Das Kern-Feature: Eine Review-Seite auf der man Items durchgehen, Research lesen, Drafts prüfen und Approve/Skip/Edit klicken kann. Status-Bar zeigt Übersicht, Filter-Tabs erlauben fokussiertes Arbeiten. Alles reaktiv per Turbo Frames.

## Voraussetzung

Phase 2 ist abgeschlossen. CSV Import funktioniert, Items existieren in der DB.

## Schritt 1: Pipeline Review Controller

```ruby
# config/routes.rb (ergänzen)
resources :pipelines, only: [:show] do
  member do
    post :import_csv
  end
  resources :items, only: [:show, :update], controller: "pipeline_items" do
    member do
      post :approve
      post :skip
      post :reset
    end
  end
end
```

```ruby
# app/controllers/pipeline_items_controller.rb
class PipelineItemsController < ApplicationController
  before_action :set_pipeline
  before_action :set_item, only: [:show, :update, :approve, :skip, :reset]

  def approve
    review_step = @item.current_step
    @item.update!(status: "approved")
    @item.item_events.create!(
      pipeline_step: review_step,
      event_type: "human_approved"
    )
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to pipeline_path(@pipeline) }
    end
  end

  def skip
    review_step = @item.current_step
    @item.update!(status: "rejected")
    @item.item_events.create!(
      pipeline_step: review_step,
      event_type: "human_rejected",
      note: params[:reason]
    )
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to pipeline_path(@pipeline) }
    end
  end

  def reset
    @item.update!(status: "review")
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to pipeline_path(@pipeline) }
    end
  end

  def update
    # Inline-Edit von Subject + Body
    data = @item.data.dup
    data["draft"] ||= {}
    data["draft"]["subject"] = params[:subject] if params[:subject]
    data["draft"]["body"] = params[:body] if params[:body]
    @item.update!(data: data)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to pipeline_path(@pipeline) }
    end
  end

  private

  def set_pipeline
    @pipeline = Pipeline.find(params[:pipeline_id])
  end

  def set_item
    @item = @pipeline.items.find(params[:id])
  end
end
```

## Schritt 2: Review-Ansicht auf Pipeline#show

Ersetze die einfache Items-Tabelle aus Phase 2 durch die volle Review-UI.

### Layout-Struktur

```
┌─────────────────────────────────────────────────────────────────┐
│  Cold Emailing — spreenovate                     [Import CSV]   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ 25 total  │  8 approved  │  2 skipped  │  15 review     │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  [Alle] [Review] [Approved] [Skipped] [Sent]                    │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Klaus Haddick · DNLA GmbH · Managing Director           │   │
│  │ ▸ Research anzeigen                                      │   │
│  │                                                          │   │
│  │ Betreff: Wenn KI Sozialkompetenz misst — ...             │   │
│  │                                                          │   │
│  │ Hallo Herr Haddick,                                      │   │
│  │ Sie verkaufen mit DNLA ein Verfahren...                  │   │
│  │                                                          │   │
│  │           [Approve]  [Skip]  [Edit]                      │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Nächste Card ...                                         │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Wichtige UI-Elemente

**Status-Bar:** Zeigt Counts pro Status. Aktualisiert sich per Turbo Frame nach jeder Aktion.

**Filter-Tabs:** Query-Parameter `?filter=review`, `?filter=approved` etc. Default: `review` (zeigt nur Items die reviewed werden müssen).

**Item-Card:**
- Header: Name, Firma, Titel, Email
- Research-Summary: Aufklappbar (default: zu). Nutze `<details>` / `<summary>` oder Stimulus Controller.
- Draft: Subject (fett) + Body (pre-formatted, Zeilenumbrüche erhalten)
- Buttons: Approve (grün), Skip (grau), Edit (blau)
- Status-Badge: Farbig wie in Phase 2

**Edit-Modus:**
- Click auf "Edit" → Subject wird zum Input-Feld, Body wird zur Textarea
- "Speichern" Button sendet PATCH an `pipeline_items#update`
- Danach zurück zur normalen Card-Ansicht

### Turbo Frames

Jede Item-Card in einem eigenen Turbo Frame:

```erb
<%= turbo_frame_tag dom_id(item) do %>
  <%# Card-Inhalt %>
<% end %>
```

Status-Bar in eigenem Turbo Frame:

```erb
<%= turbo_frame_tag "status_bar" do %>
  <%# Counts %>
<% end %>
```

Approve/Skip/Reset Aktionen rendern Turbo Stream Responses:

```erb
<%# app/views/pipeline_items/approve.turbo_stream.erb %>
<%= turbo_stream.replace dom_id(@item) do %>
  <%= render partial: "pipeline_items/item_card", locals: { item: @item, pipeline: @pipeline } %>
<% end %>

<%= turbo_stream.replace "status_bar" do %>
  <%= render partial: "pipelines/status_bar", locals: { pipeline: @pipeline } %>
<% end %>
```

## Schritt 3: Bulk Actions

Zwei Buttons über der Liste:

- **"Alle approven"** → POST an `pipeline_items#bulk_approve` (nur Items mit Status "review")
- **"Alle zurücksetzen"** → POST an `pipeline_items#bulk_reset`

```ruby
# In routes.rb, innerhalb des pipelines-Blocks:
collection do
  post :bulk_approve
  post :bulk_reset
end
```

## Schritt 4: Styling mit Tailwind

Halte dich an ein einfaches, sauberes Design:
- Hintergrund: `bg-gray-50`
- Cards: `bg-white border rounded-lg shadow-sm p-4`
- Approve-Button: `bg-green-600 text-white hover:bg-green-700`
- Skip-Button: `bg-gray-200 text-gray-700 hover:bg-gray-300`
- Edit-Button: `bg-blue-100 text-blue-700 hover:bg-blue-200`
- Status-Badges: Farbig (siehe Phase 2)

## Wichtig: Keine Tests

Schreibe keine Tests. Keine Model-Tests, keine Controller-Tests, keine System-Tests. Nur lauffähigen Code.

## Fertig wenn:

- [ ] Pipeline#show zeigt Status-Bar mit korrekten Counts
- [ ] Filter-Tabs funktionieren (Alle / Review / Approved / Skipped / Sent)
- [ ] Item-Cards zeigen Name, Firma, Titel, Research (aufklappbar), Draft
- [ ] Approve setzt Status auf "approved", erstellt ItemEvent, Card aktualisiert sich
- [ ] Skip setzt Status auf "rejected", erstellt ItemEvent, Card aktualisiert sich
- [ ] Edit ermöglicht Inline-Bearbeitung von Subject + Body
- [ ] Status-Bar aktualisiert sich nach jeder Aktion (Turbo)
- [ ] Bulk Approve funktioniert
- [ ] Alles ohne Page Reload (Turbo Frames/Streams)
