module StepExecutors
  class AiAgent < Base
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
      prompt = interpolate(prompt_template)

      result = client.call(
        model: step.config["model"] || "claude-opus-4-6",
        system: "Folge den Anweisungen im Prompt exakt.",
        prompt: prompt,
        tools: build_tools
      )

      send(:"parse_#{task}_response", result[:text])

      item.item_events.create!(
        pipeline_step: step,
        event_type: "ai_completed",
        snapshot: item.data
      )

      item.advance_to_next_step!
    end

    private

    def interpolate(template)
      research = item.data["research"] || {}

      template
        .gsub("{{name}}", item.data["name"].to_s)
        .gsub("{{title}}", item.data["title"].to_s)
        .gsub("{{company}}", item.data["company"].to_s)
        .gsub("{{email}}", item.data["email"].to_s)
        .gsub("{{website}}", item.data["website"].to_s)
        .gsub("{{research_summary}}", research["summary"].to_s)
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
        "subject" => subject,
        "body" => body,
        "drafted_at" => Time.current.iso8601,
        "version" => (data.dig("draft", "version") || 0) + 1
      }
      item.update!(data: data)
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
