module StepExecutors
  class AiAgent < Base
    SYSTEM_PROMPT = "Folge den Anweisungen im Prompt exakt. Sei knapp und präzise! Kürze > Vollständigkeit.".freeze
    PROMPT_SEPARATOR = "\n---\n".freeze

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

      result = if dynamic_part
        client.call_with_cache(
          model: step.config["model"] || "claude-opus-4-6",
          system: SYSTEM_PROMPT,
          static_prompt: static_part,
          dynamic_prompt: interpolate_text(dynamic_part),
          tools: build_tools
        )
      else
        # No separator found, fall back to regular call
        client.call(
          model: step.config["model"] || "claude-opus-4-6",
          system: SYSTEM_PROMPT,
          prompt: interpolate_text(static_part),
          tools: build_tools
        )
      end

      send(:"parse_#{task}_response", result[:text])

      item.item_events.create!(
        pipeline_step: step,
        event_type: "ai_completed",
        snapshot: item.data
      )

      item.advance_to_next_step!
    end

    # Build a single batch request object for this item
    # Returns hash suitable for Batch API requests array
    def self.build_batch_request(item, step)
      task = step.config["task"]
      prompt_template = AgentMemory.load_prompt(item.pipeline, task)
      raise "Kein Prompt gefunden für Task '#{task}'" if prompt_template.blank?

      static_part, dynamic_part = split_prompt_template(prompt_template)
      dynamic_interpolated = interpolate_template(dynamic_part || "", item)

      messages = if dynamic_part
        [{
          role: "user",
          content: [
            { type: "text", text: static_part, cache_control: { type: "ephemeral" } },
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
        system: SYSTEM_PROMPT,
        messages: messages
      }
      params[:tools] = tools if tools.any?

      { custom_id: item.id.to_s, params: params }
    end

    # Apply a batch result to an item (idempotent — safe to call twice)
    def self.apply_batch_result(item, step, result)
      # Guard: skip if item was already advanced (e.g., job retry after partial crash)
      return if item.current_step_id != step.id

      if result["result"]["type"] == "succeeded"
        text = result["result"]["message"]["content"]
          .select { |c| c["type"] == "text" }
          .map { |c| c["text"] }
          .join("\n")

        task = step.config["task"]
        instance = new(item, step)
        instance.send(:"parse_#{task}_response", text)

        item.item_events.create!(
          pipeline_step: step,
          event_type: "ai_completed",
          snapshot: item.data
        )

        item.advance_to_next_step!(batch_mode: true)
      else
        error_msg = result.dig("result", "error", "message") || "Batch request failed"
        item.update!(status: "failed")
        item.item_events.create!(
          pipeline_step: step,
          event_type: "error",
          note: "Batch error: #{error_msg}"
        )
      end
    end

    private

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
