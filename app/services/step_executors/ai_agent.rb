module StepExecutors
  class AiAgent < Base
    SYSTEM_PROMPT = "Folge den Anweisungen im Prompt exakt. Sei knapp und präzise! Kürze > Vollständigkeit.".freeze
    VARIANT_B_INSTRUCTION = "\n\n## Stil-Anweisung für diese Variante\n\nSei unkonventioneller. Überrasche. Wähle einen unerwarteten Einstieg.".freeze
    PROMPT_SEPARATOR = "\n---\n".freeze

    VARIANT_A_TEMPERATURE = 0.7
    VARIANT_B_TEMPERATURE = 0.95

    # Single item execution (with prompt caching)
    def execute
      item.update!(status: "processing")

      project = item.pipeline.project
      api_key = project.credential_for("ai_api_key")
      raise "Kein API Key für Projekt #{project.name}" unless api_key

      task = step.config["task"]
      raise "Unbekannter Task: #{task}" unless %w[research draft].include?(task)

      prompt_template = AgentMemory.load_prompt(item.pipeline, task)
      raise "Kein Prompt gefunden für Task '#{task}'" if prompt_template.blank?

      client = ClaudeClient.new(api_key: api_key)
      static_part, dynamic_part = split_prompt(prompt_template)

      if task == "draft"
        # Generate 2 variants for draft
        execute_draft_variants(client, static_part, dynamic_part)
      else
        # Research: single call
        result = call_with_prompt(client, static_part, dynamic_part)
        parse_research_response(result[:text])
      end

      item.item_events.create!(
        pipeline_step: step,
        event_type: "ai_completed",
        snapshot: item.data
      )

      item.advance_to_next_step!
    end

    # Build batch request(s) for this item
    # Returns ARRAY: 1 request for research, 2 requests for draft (A/B)
    def self.build_batch_requests(item, step)
      task = step.config["task"]
      prompt_template = AgentMemory.load_prompt(item.pipeline, task)
      raise "Kein Prompt gefunden für Task '#{task}'" if prompt_template.blank?

      static_part, dynamic_part = split_prompt_template(prompt_template)
      dynamic_interpolated = interpolate_template(dynamic_part || "", item)

      if task == "draft"
        # Two requests: variant A and B (same system prompt for caching, B gets extra instruction in dynamic part)
        [
          build_single_request(item, step, static_part, dynamic_interpolated, "#{item.id}_a", SYSTEM_PROMPT, VARIANT_A_TEMPERATURE),
          build_single_request(item, step, static_part, dynamic_interpolated + VARIANT_B_INSTRUCTION, "#{item.id}_b", SYSTEM_PROMPT, VARIANT_B_TEMPERATURE)
        ]
      else
        # Research: single request
        [build_single_request(item, step, static_part, dynamic_interpolated, item.id.to_s, SYSTEM_PROMPT, nil)]
      end
    end

    # Apply batch result(s) to an item
    # For research: single result. For draft: expects both variants as array.
    def self.apply_batch_result(item, step, result)
      return if item.current_step_id != step.id

      task = step.config["task"]

      if task == "draft"
        apply_draft_variants_result(item, step, result)
      else
        apply_single_result(item, step, result)
      end
    end

    private

    def execute_draft_variants(client, static_part, dynamic_part)
      model = step.config["model"] || "claude-opus-4-6"

      # Variant A: standard temperature
      result_a = call_with_prompt(client, static_part, dynamic_part, temperature: VARIANT_A_TEMPERATURE)
      variant_a = parse_variant(result_a[:text], "a", VARIANT_A_TEMPERATURE)

      # Variant B: higher temperature, extra instruction appended to dynamic part
      result_b = call_with_prompt(client, static_part, dynamic_part, temperature: VARIANT_B_TEMPERATURE, extra_instruction: VARIANT_B_INSTRUCTION)
      variant_b = parse_variant(result_b[:text], "b", VARIANT_B_TEMPERATURE)

      save_draft_variants(variant_a, variant_b)
    end

    def call_with_prompt(client, static_part, dynamic_part, temperature: nil, extra_instruction: nil)
      model = step.config["model"] || "claude-opus-4-6"
      dynamic_content = dynamic_part ? interpolate_text(dynamic_part) : nil
      dynamic_content = "#{dynamic_content}#{extra_instruction}" if extra_instruction && dynamic_content

      if dynamic_content
        client.call_with_cache(
          model: model,
          system: SYSTEM_PROMPT,
          static_prompt: static_part,
          dynamic_prompt: dynamic_content,
          tools: build_tools,
          temperature: temperature
        )
      else
        prompt = interpolate_text(static_part)
        prompt = "#{prompt}#{extra_instruction}" if extra_instruction
        client.call(
          model: model,
          system: SYSTEM_PROMPT,
          prompt: prompt,
          tools: build_tools,
          temperature: temperature
        )
      end
    end

    def parse_variant(text, variant_name, temperature)
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

    def save_draft_variants(variant_a, variant_b)
      data = item.data.dup
      version = (data.dig("draft", "version") || 0) + 1

      data["drafts"] = {
        "variants" => [variant_a, variant_b],
        "selected_variant" => nil,
        "selected_at" => nil
      }

      # Default to variant A as active draft
      data["draft"] = {
        "subject" => variant_a["subject"],
        "body" => variant_a["body"],
        "drafted_at" => variant_a["drafted_at"],
        "version" => version
      }

      item.update!(data: data)
    end

    # Class methods for batch processing

    def self.build_single_request(item, step, static_part, dynamic_interpolated, custom_id, system_prompt, temperature)
      messages = if static_part && dynamic_interpolated.present?
        [{
          role: "user",
          content: [
            { type: "text", text: static_part },
            { type: "text", text: dynamic_interpolated }
          ]
        }]
      else
        [{ role: "user", content: interpolate_template(static_part, item) }]
      end

      tools = []
      if step.config["enable_web_search"]
        tools << { type: "web_search_20250305", name: "web_search", max_uses: 5 }
      end

      params = {
        model: step.config["model"] || "claude-opus-4-6",
        max_tokens: 4096,
        system: system_prompt,
        messages: messages,
        cache_control: { type: "ephemeral" }
      }
      params[:tools] = tools if tools.any?
      params[:temperature] = temperature if temperature

      { custom_id: custom_id.to_s, params: params }
    end

    def self.apply_single_result(item, step, result)
      if result["result"]["type"] == "succeeded"
        text = extract_text(result)
        instance = new(item, step)
        instance.send(:parse_research_response, text)

        item.item_events.create!(
          pipeline_step: step,
          event_type: "ai_completed",
          snapshot: item.data
        )

        item.advance_to_next_step!(batch_mode: true)
      else
        mark_failed(item, step, result)
      end
    end

    # Expects an array of 2 results [{variant: "a", result: ...}, {variant: "b", result: ...}]
    def self.apply_draft_variants_result(item, step, variant_results)
      variants = []
      variant_results.each do |vr|
        if vr["result"]["type"] == "succeeded"
          text = extract_text(vr)
          instance = new(item, step)
          parsed = instance.send(:parse_variant, text, vr["variant"], vr["temperature"])
          variants << parsed
        end
      end

      if variants.empty?
        mark_failed(item, step, variant_results.first)
        return
      end

      data = item.data.dup
      version = (data.dig("draft", "version") || 0) + 1

      data["drafts"] = {
        "variants" => variants,
        "selected_variant" => nil,
        "selected_at" => nil
      }

      # Default to first successful variant as active draft
      data["draft"] = {
        "subject" => variants.first["subject"],
        "body" => variants.first["body"],
        "drafted_at" => variants.first["drafted_at"],
        "version" => version
      }

      item.update!(data: data)

      item.item_events.create!(
        pipeline_step: step,
        event_type: "ai_completed",
        snapshot: item.data
      )

      item.advance_to_next_step!(batch_mode: true)
    end

    def self.extract_text(result)
      result["result"]["message"]["content"]
        .select { |c| c["type"] == "text" }
        .map { |c| c["text"] }
        .join("\n")
    end

    def self.mark_failed(item, step, result)
      error_msg = result&.dig("result", "error", "message") || "Batch request failed"
      item.update!(status: "failed")
      item.item_events.create!(
        pipeline_step: step,
        event_type: "error",
        note: "Batch error: #{error_msg}"
      )
    end

    def split_prompt(template)
      self.class.split_prompt_template(template)
    end

    def self.split_prompt_template(template)
      if template.include?(PROMPT_SEPARATOR)
        parts = template.split(PROMPT_SEPARATOR, 2)
        [parts[0].strip, parts[1].strip]
      else
        [template, nil]
      end
    end

    def interpolate_text(text)
      self.class.interpolate_template(text, item)
    end

    def self.interpolate_template(template, item)
      research = item.data["research"] || {}

      two_months_ago = 2.months.ago.strftime("%B %Y")
      current_date = Date.current.strftime("%B %Y")

      template
        .gsub("{{name}}", item.data["name"].to_s)
        .gsub("{{title}}", item.data["title"].to_s)
        .gsub("{{company}}", item.data["company"].to_s)
        .gsub("{{email}}", item.data["email"].to_s)
        .gsub("{{website}}", item.data["website"].to_s)
        .gsub("{{research_summary}}", research["summary"].to_s)
        .gsub("{{current_date}}", current_date)
        .gsub("{{min_date}}", two_months_ago)
    end

    def parse_research_response(text)
      data = item.data.dup
      data["research"] = {
        "summary" => text.strip,
        "researched_at" => Time.current.iso8601
      }
      item.update!(data: data)
    end

    def parse_draft_response(text)
      # Legacy single-draft parsing (used by non-variant paths if needed)
      subject = text.match(/subject:\s*(.+)/i)&.captures&.first&.strip || "Kein Betreff"
      body = text.match(/body:\s*(.+)/mi)&.captures&.first&.strip || text

      data = item.data.dup
      data["draft"] = {
        "subject" => strip_markdown(subject),
        "body" => strip_markdown(body),
        "drafted_at" => Time.current.iso8601,
        "version" => (data.dig("draft", "version") || 0) + 1
      }
      item.update!(data: data)
    end

    def strip_markdown(text)
      text
        .gsub(/\*\*(.+?)\*\*/m, '\1')
        .gsub(/^- /, '')
        .strip
    end

    def build_tools
      tools = []
      if step.config["enable_web_search"]
        tools << {
          type: "web_search_20250305",
          name: "web_search",
          max_uses: 5
        }
      end
      tools
    end
  end
end
