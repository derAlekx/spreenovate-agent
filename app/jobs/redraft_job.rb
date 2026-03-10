class RedraftJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 5, key: "ai_processing"

  def perform(item_id)
    item = Item.find(item_id)
    step = item.current_step

    project = item.pipeline.project
    api_key = project.credential_for("ai_api_key")

    raise "Kein API Key für Projekt #{project.name}" unless api_key

    prompt_template = AgentMemory.load_prompt(item.pipeline, "draft")
    raise "Kein Draft-Prompt gefunden" if prompt_template.blank?

    old_draft = item.data["draft"] || {}
    previous_email = "subject: #{old_draft['subject']}\nbody: #{old_draft['body']}"

    prompt = StepExecutors::AiAgent.interpolate_template(prompt_template, item)
    prompt += <<~ADDITION

      ## Wichtig: Neue Version!

      Die folgende Email wurde bereits geschrieben, aber abgelehnt. Schreibe eine KOMPLETT andere Version mit einem anderen Hook und anderer Perspektive. Nicht nur umformulieren — anders denken.

      Vorherige Email:
      #{previous_email}
    ADDITION

    client = ClaudeClient.new(api_key: api_key)
    result = client.call(
      model: step.config["model"] || "claude-opus-4-6",
      system: "Folge den Anweisungen im Prompt exakt. Sei knapp und präzise! Kürze > Vollständigkeit.",
      prompt: prompt,
      tools: []
    )

    text = result[:text]
    subject = text.match(/subject:\s*(.+)/i)&.captures&.first&.strip || "Kein Betreff"
    body = text.match(/body:\s*(.+)/mi)&.captures&.first&.strip || text

    data = item.data.dup
    data["draft"] = {
      "subject" => strip_markdown(subject),
      "body" => strip_markdown(body),
      "drafted_at" => Time.current.iso8601,
      "version" => (data.dig("draft", "version") || 0) + 1
    }
    item.update!(data: data, status: "review")

    item.item_events.create!(
      pipeline_step: step,
      event_type: "ai_completed",
      note: "Redraft v#{data['draft']['version']}"
    )
  rescue => e
    item.update!(status: "review")
    item.item_events.create!(
      pipeline_step: item.current_step,
      event_type: "error",
      note: "Redraft fehlgeschlagen: #{e.class}: #{e.message}"
    )
    Rails.logger.error("RedraftJob failed for Item##{item_id}: #{e.class}: #{e.message}")
  end

  private

  def strip_markdown(text)
    text
      .gsub(/\*\*(.+?)\*\*/m, '\1')
      .gsub(/^- /, '')
      .strip
  end
end
