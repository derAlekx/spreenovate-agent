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

    static_part, dynamic_part = prompt_template.split(StepExecutors::AiAgent::PROMPT_SEPARATOR, 2)

    redraft_addition = <<~ADDITION

      ## Wichtig: Neue Version!

      Die folgende Email wurde bereits geschrieben, aber abgelehnt. Schreibe eine KOMPLETT andere Version mit einem anderen Hook und anderer Perspektive. Nicht nur umformulieren, anders denken.

      Vorherige Email:
      #{previous_email}
    ADDITION

    client = ClaudeClient.new(api_key: api_key)
    model = step.config["model"] || "claude-opus-4-6"

    # Generate 2 variants (A: standard, B: bolder)
    variant_a = generate_variant(client, model, static_part, dynamic_part, item, redraft_addition,
      system: StepExecutors::AiAgent::SYSTEM_PROMPT,
      temperature: StepExecutors::AiAgent::VARIANT_A_TEMPERATURE,
      variant_name: "a")

    variant_b = generate_variant(client, model, static_part, dynamic_part, item, redraft_addition,
      system: StepExecutors::AiAgent::SYSTEM_PROMPT,
      extra_instruction: StepExecutors::AiAgent::VARIANT_B_INSTRUCTION,
      temperature: StepExecutors::AiAgent::VARIANT_B_TEMPERATURE,
      variant_name: "b")

    data = item.data.dup
    version = (data.dig("draft", "version") || 0) + 1

    data["drafts"] = {
      "variants" => [variant_a, variant_b],
      "selected_variant" => nil,
      "selected_at" => nil
    }

    data["draft"] = {
      "subject" => variant_a["subject"],
      "body" => variant_a["body"],
      "drafted_at" => variant_a["drafted_at"],
      "version" => version
    }

    item.update!(data: data, status: "review")

    item.item_events.create!(
      pipeline_step: step,
      event_type: "ai_completed",
      note: "Redraft v#{version} (A/B)"
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

  def generate_variant(client, model, static_part, dynamic_part, item, redraft_addition, system:, temperature:, variant_name:, extra_instruction: nil)
    if dynamic_part
      dynamic_interpolated = StepExecutors::AiAgent.interpolate_template(dynamic_part, item)
      dynamic_content = dynamic_interpolated + redraft_addition
      dynamic_content += extra_instruction if extra_instruction
      result = client.call_with_cache(
        model: model,
        system: system,
        static_prompt: static_part.strip,
        dynamic_prompt: dynamic_content,
        tools: [],
        temperature: temperature
      )
    else
      prompt = StepExecutors::AiAgent.interpolate_template(static_part, item) + redraft_addition
      prompt += extra_instruction if extra_instruction
      result = client.call(
        model: model,
        system: system,
        prompt: prompt,
        tools: [],
        temperature: temperature
      )
    end

    text = result[:text]
    subject = text.match(/subject:\s*(.+)/i)&.captures&.first&.strip || "Kein Betreff"
    body = text.match(/body:\s*(.+)/mi)&.captures&.first&.strip || text

    {
      "variant" => variant_name,
      "subject" => strip_markdown(subject),
      "body" => strip_markdown(body),
      "temperature" => temperature,
      "drafted_at" => Time.current.iso8601
    }
  end

  def strip_markdown(text)
    text
      .gsub(/\*\*(.+?)\*\*/m, '\1')
      .gsub(/^- /, '')
      .strip
  end
end
