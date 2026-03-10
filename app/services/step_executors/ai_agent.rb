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
        Website: #{item.data['website']}

        Finde heraus:
        1. Was macht die Firma genau? (Produkte, Dienstleistungen, Branche)
        2. Welche Rolle hat die Person?
        3. Aktuelle News oder Entwicklungen des Unternehmens?
        4. Mögliche Pain Points in Bezug auf KI/Automatisierung?
        5. Konkreter Hook für eine personalisierte Ansprache?

        Gib das Ergebnis als PLAIN TEXT zurück (kein Markdown, keine Formatierung) mit exakt diesen Abschnitten:
        ZUSAMMENFASSUNG: (2-3 Sätze über Firma und Person, Fließtext)
        PAIN_POINTS: (kommaseparierte Liste, z.B. "Punkt 1, Punkt 2, Punkt 3")
        HOOK: (ein konkreter Aufhänger für die Email, ein Satz)
      PROMPT

      tools = build_tools
      result = client.call(
        model: step.config["model"] || "claude-opus-4-6",
        system: system_prompt,
        prompt: prompt,
        tools: tools
      )

      text = result[:text]

      summary = text.match(/ZUSAMMENFASSUNG:\s*(.+?)(?=PAIN_POINTS:|$)/m)&.captures&.first&.strip || text
      pain_points_raw = text.match(/PAIN_POINTS:\s*(.+?)(?=HOOK:|$)/m)&.captures&.first&.strip || ""
      pain_points = pain_points_raw.split(",").map(&:strip).reject(&:blank?)
      hook_angle = text.match(/HOOK:\s*(.+)/m)&.captures&.first&.strip || ""

      data = item.data.dup
      data["research"] = {
        "summary" => summary,
        "pain_points" => pain_points,
        "hook_angle" => hook_angle,
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

        Pain Points:
        #{Array(item.data.dig('research', 'pain_points')).join(', ')}

        Hook/Aufhänger:
        #{item.data.dig('research', 'hook_angle')}

        WICHTIG:
        - Max. 120 Wörter Body
        - Betreffzeile max. 8 Wörter
        - Konkreter Bezug zur Person/Firma
        - Frage als CTA
        - Signatur: "Beste Grüße\\nAlexander Kamphorst"

        Gib die Email in exakt diesem Format zurück:
        SUBJECT: [Betreffzeile]
        BODY:
        [Email-Text inkl. Signatur]
      PROMPT

      result = client.call(
        model: step.config["model"] || "claude-opus-4-6",
        system: system_prompt,
        prompt: prompt,
        tools: []
      )

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
      parts << "Deine Aufgabe: Hochwertige, personalisierte Cold Emails erstellen."
      parts << "\n## Memory\n#{memory[:memory]}" if memory[:memory].present?
      parts << "\n## Style Guide\n#{memory[:style_guide]}" if memory[:style_guide].present? && task == "draft"
      parts << "\n## Tagesnotizen\n#{memory[:daily_log]}" if memory[:daily_log].present?
      parts.join("\n")
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
