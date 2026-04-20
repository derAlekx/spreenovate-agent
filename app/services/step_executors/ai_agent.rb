module StepExecutors
  class AiAgent < Base
    SYSTEM_PROMPT = "Folge den Anweisungen im Prompt exakt. Sei knapp und präzise! Kürze > Vollständigkeit.".freeze
    PROMPT_SEPARATOR = "\n---\n".freeze

    # Same temperature for both variants so the only difference is prompt + model
    VARIANT_A_TEMPERATURE = 0.7
    VARIANT_B_TEMPERATURE = 0.7

    # Variant B uses a different model so we can directly compare Opus vs Sonnet
    VARIANT_B_MODEL = "claude-sonnet-4-6"

    # Single item execution (with prompt caching)
    def execute
      item.update!(status: "processing")

      project = item.pipeline.project
      api_key = project.credential_for("ai_api_key")
      raise "Kein API Key für Projekt #{project.name}" unless api_key

      task = step.config["task"]
      raise "Unbekannter Task: #{task}" unless %w[qualify research draft].include?(task)

      client = ClaudeClient.new(api_key: api_key)

      if task == "draft"
        execute_draft_variants(client)
      else
        # Qualify and Research: single call with default prompt
        prompt_template = AgentMemory.load_prompt(item.pipeline, task)
        raise "Kein Prompt gefunden für Task '#{task}'" if prompt_template.blank?

        static_part, dynamic_part = split_prompt(prompt_template)
        result = call_with_prompt(client, static_part, dynamic_part)
        send(:"parse_#{task}_response", result[:text])
      end

      item.item_events.create!(
        pipeline_step: step,
        event_type: "ai_completed",
        snapshot: item.data
      )

      # If qualify scored too low, auto-skip; otherwise advance normally
      if task == "qualify" && item.data.dig("qualify", "score").to_i < 3
        item.update!(status: "rejected")
        item.item_events.create!(
          pipeline_step: step,
          event_type: "human_rejected",
          note: "Auto-skip: fit_score=#{item.data.dig('qualify', 'score')} (#{item.data.dig('qualify', 'reason')})"
        )
      else
        item.advance_to_next_step!
      end
    end

    # Build batch request(s) for this item
    # Returns ARRAY: 1 request for research, 2 requests for draft (A/B with different prompts)
    def self.build_batch_requests(item, step)
      task = step.config["task"]

      if task == "draft"
        # Two requests: variant A = Opus, variant B = Sonnet (for A/B model comparison)
        # Prompts can differ per variant (prompt_draft.md vs prompt_draft_variant_b.md)
        prompt_a = AgentMemory.load_prompt(item.pipeline, task)
        prompt_b = AgentMemory.load_prompt(item.pipeline, task, variant: "b")

        raise "Kein Draft-Prompt (A) gefunden" if prompt_a.blank?
        raise "Kein Draft-Prompt (B) gefunden" if prompt_b.blank?

        [
          build_request_from_prompt(item, step, prompt_a, "#{item.id}_a", VARIANT_A_TEMPERATURE),
          build_request_from_prompt(item, step, prompt_b, "#{item.id}_b", VARIANT_B_TEMPERATURE, model_override: VARIANT_B_MODEL)
        ]
      else
        # Research: single request
        prompt = AgentMemory.load_prompt(item.pipeline, task)
        raise "Kein Prompt gefunden für Task '#{task}'" if prompt.blank?
        [build_request_from_prompt(item, step, prompt, item.id.to_s, nil)]
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

    def execute_draft_variants(client)
      prompt_a = AgentMemory.load_prompt(item.pipeline, "draft")
      prompt_b = AgentMemory.load_prompt(item.pipeline, "draft", variant: "b")

      raise "Kein Draft-Prompt (A) gefunden" if prompt_a.blank?
      raise "Kein Draft-Prompt (B) gefunden" if prompt_b.blank?

      # Variant A: default prompt, default model (Opus)
      model_a = step.config["model"] || "claude-opus-4-7"
      static_a, dynamic_a = split_prompt(prompt_a)
      result_a = call_with_prompt(client, static_a, dynamic_a, temperature: VARIANT_A_TEMPERATURE)
      variant_a = parse_variant(result_a[:text], "a", VARIANT_A_TEMPERATURE, model_a)

      # Variant B: same prompt (currently), different model (Sonnet) for A/B comparison
      static_b, dynamic_b = split_prompt(prompt_b)
      result_b = call_with_prompt(client, static_b, dynamic_b, temperature: VARIANT_B_TEMPERATURE, model_override: VARIANT_B_MODEL)
      variant_b = parse_variant(result_b[:text], "b", VARIANT_B_TEMPERATURE, VARIANT_B_MODEL)

      save_draft_variants(variant_a, variant_b)
    end

    def call_with_prompt(client, static_part, dynamic_part, temperature: nil, model_override: nil)
      model = model_override || step.config["model"] || "claude-opus-4-7"
      dynamic_content = dynamic_part ? interpolate_text(dynamic_part) : nil

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
        client.call(
          model: model,
          system: SYSTEM_PROMPT,
          prompt: interpolate_text(static_part),
          tools: build_tools,
          temperature: temperature
        )
      end
    end

    def parse_variant(text, variant_name, temperature, model = nil)
      subject, body = self.class.extract_subject_and_body(text)

      {
        "variant" => variant_name,
        "subject" => strip_markdown(subject),
        "body" => strip_markdown(body),
        "temperature" => temperature,
        "model" => model,
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

    # === Class methods ===

    def self.build_request_from_prompt(item, step, prompt_template, custom_id, temperature, model_override: nil)
      static_part, dynamic_part = split_prompt_template(prompt_template)
      dynamic_interpolated = interpolate_template(dynamic_part || "", item)

      build_single_request(item, step, static_part, dynamic_interpolated, custom_id, SYSTEM_PROMPT, temperature, model_override: model_override)
    end

    def self.build_single_request(item, step, static_part, dynamic_interpolated, custom_id, system_prompt, temperature, model_override: nil)
      # cache_control at TOP-LEVEL so Anthropic caches the longest valid prefix.
      # Our static block alone is under the 4096-token minimum for Opus 4.6 —
      # block-level cache_control would silently not cache. See ClaudeClient#call_with_cache.
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
        model: model_override || step.config["model"] || "claude-opus-4-7",
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
        task = step.config["task"]
        instance = new(item, step)
        instance.send(:"parse_#{task}_response", text)

        item.item_events.create!(
          pipeline_step: step,
          event_type: "ai_completed",
          snapshot: item.data
        )

        # Auto-skip if qualify scored too low
        if task == "qualify" && item.data.dig("qualify", "score").to_i < 3
          item.update!(status: "rejected")
          item.item_events.create!(
            pipeline_step: step,
            event_type: "human_rejected",
            note: "Auto-skip: fit_score=#{item.data.dig('qualify', 'score')} (#{item.data.dig('qualify', 'reason')})"
          )
        else
          item.advance_to_next_step!(batch_mode: true)
        end
      else
        mark_failed(item, step, result)
      end
    end

    # Expects an array of 2 results [{variant: "a", result: ...}, {variant: "b", result: ...}]
    # Batch API does not guarantee result order, so we sort by variant letter ourselves.
    def self.apply_draft_variants_result(item, step, variant_results)
      # Sort by variant letter ("a" before "b") so default draft is always variant A
      sorted_results = variant_results.sort_by { |vr| vr["variant"].to_s }

      variants = []
      failed_variant_names = []
      sorted_results.each do |vr|
        if vr["result"]["type"] == "succeeded"
          text = extract_text(vr)
          # Model comes from the response itself (Anthropic echoes the actual model used)
          model_used = vr.dig("result", "message", "model")
          instance = new(item, step)
          parsed = instance.send(:parse_variant, text, vr["variant"], vr["temperature"], model_used)
          variants << parsed
        else
          failed_variant_names << vr["variant"]
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

      # Prefer variant "a" as default; fall back to first available
      default_variant = variants.find { |v| v["variant"] == "a" } || variants.first
      data["draft"] = {
        "subject" => default_variant["subject"],
        "body" => default_variant["body"],
        "drafted_at" => default_variant["drafted_at"],
        "version" => version
      }

      item.update!(data: data)

      item.item_events.create!(
        pipeline_step: step,
        event_type: "ai_completed",
        note: failed_variant_names.any? ? "Variante #{failed_variant_names.join(',').upcase} fehlgeschlagen, nur #{variants.size} von 2 generiert" : nil,
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

    # Extract subject and body from model output. Handles both orderings
    # and both German/English markers ("Betreff:" or "subject:", "Body:" or "body:").
    # Only matches markers at the start of a line (line-level markers).
    def self.extract_subject_and_body(text)
      # Subject: find the LAST occurrence of a line starting with "subject:" or "Betreff:"
      subject_matches = text.scan(/^\s*(?:subject|Betreff):\s*(.+)$/i)
      subject = subject_matches.last&.first&.strip || "Kein Betreff"

      # Body: line starting with "body:" or "Body:" — content until next marker line or end
      body_match = text.match(/^\s*(?:body|Body):\s*(.*?)(?=^\s*(?:subject|Betreff|body|Body):|\z)/im)

      if body_match
        body = body_match[1].strip
      else
        # No body marker found — strip any subject line from the full text
        body = text.gsub(/^\s*(?:subject|Betreff):\s*.+$/i, "").strip
      end

      # Safety: if body still contains a subject line, cut it off there
      if body =~ /^\s*(?:subject|Betreff):\s*/im
        body = body.sub(/^\s*(?:subject|Betreff):\s*.*\z/im, "").strip
      end

      [subject, body]
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
        .gsub("{{excellent_examples}}", excellent_examples_for(item.pipeline))
    end

    # Returns formatted examples of emails the user explicitly marked as excellent.
    # These are injected into the draft prompt as additional few-shot references.
    # Returns empty string if there are no marked examples yet.
    #
    # Eligibility: must be (approved OR sent) AND marked_excellent == true.
    # The marked_excellent flag is the gating criterion in BOTH cases — we never
    # train on plain approved/sent items, only on those the user actively flagged.
    def self.excellent_examples_for(pipeline, limit: 5)
      marked = pipeline.items.where(status: ["approved", "sent"]).select do |i|
        next false unless i.data["marked_excellent"] == true
        # Use sent_email snapshot if available (post-send), otherwise current draft.
        # Both reflect the user's final approved version.
        body_source = i.data["sent_email"].presence || i.data["draft"]
        body_source.is_a?(Hash) && body_source["body"].to_s.present?
      end

      # Newest first
      marked = marked.sort_by { |i| i.data["marked_excellent_at"].to_s }.reverse.first(limit)
      return "" if marked.empty?

      sections = marked.map do |i|
        source = i.data["sent_email"].presence || i.data["draft"]
        comment = i.data["user_comment"].to_s.strip
        comment_note = comment.present? ? "\n> (Kommentar: #{comment})" : ""
        <<~EX
          > subject: #{source["subject"]}
          >
          > #{source["body"].to_s.gsub("\n", "\n> ")}#{comment_note}
        EX
      end

      <<~SECTION
        ## Vom Absender als herausragend markierte Emails (Few-Shot)

        Diese Emails hat der Absender ausdrücklich als herausragend markiert. Das sind die stärksten Referenzen für Stil, Tonfall und Closer. Benutze sie NICHT als Schablone (nicht einfach kopieren), aber zieh sie als Kalibrierung heran:

        #{sections.join("\n")}
      SECTION
    end

    def parse_research_response(text)
      data = item.data.dup
      data["research"] = {
        "summary" => text.strip,
        "researched_at" => Time.current.iso8601
      }
      item.update!(data: data)
    end

    def parse_qualify_response(text)
      # Try strict line-start match first; fall back to inline match if model adds preface
      score_str = text[/^\s*score:\s*(\d+)/i, 1] || text[/\bscore:\s*(\d+)/i, 1]
      reason_str = text[/^\s*reason:\s*(.+)$/i, 1] || text[/\breason:\s*(.+?)(?:\n|\z)/i, 1]

      score = score_str.to_i
      reason = reason_str.to_s.strip

      # If parsing failed entirely, log a warning so we can spot format drift
      if score == 0
        Rails.logger.warn("AiAgent#parse_qualify_response: score parse failed for Item##{item.id}. Raw text: #{text.inspect}")
      end

      # Clamp to 1..5 in case model goes out of range
      score = score.clamp(1, 5)

      data = item.data.dup
      data["qualify"] = {
        "score" => score,
        "reason" => reason.presence || "kein Grund angegeben",
        "qualified_at" => Time.current.iso8601
      }
      item.update!(data: data)
    end

    def parse_draft_response(text)
      # Legacy single-draft parsing (used by non-variant paths if needed)
      subject, body = self.class.extract_subject_and_body(text)

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
