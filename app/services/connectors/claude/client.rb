module Connectors
  module Claude
    class Client
      API_URL = "https://api.anthropic.com/v1/messages".freeze
      BATCH_API_URL = "https://api.anthropic.com/v1/messages/batches".freeze

      def initialize(api_key:)
        @api_key = api_key
      end

      # Single synchronous call (legacy, no caching)
      def call(model:, system:, prompt:, tools: [], max_tokens: 4096)
        messages = [{ role: "user", content: prompt }]
        body = build_body(model: model, system: system, messages: messages, tools: tools, max_tokens: max_tokens)

        parsed = post_messages(body)
        extract_text(parsed)
      end

      # Single synchronous call with prompt caching
      # static_prompt gets cached, dynamic_prompt does not
      def call_with_cache(model:, system:, static_prompt:, dynamic_prompt:, tools: [], max_tokens: 4096)
        content = [
          { type: "text", text: static_prompt, cache_control: { type: "ephemeral" } },
          { type: "text", text: dynamic_prompt }
        ]
        messages = [{ role: "user", content: content }]
        body = build_body(model: model, system: system, messages: messages, tools: tools, max_tokens: max_tokens)

        parsed = post_messages(body)
        extract_text(parsed)
      end

      # Submit a batch of requests for async processing (50% cost discount)
      # requests: Array of { custom_id:, params: { model:, system:, messages:, tools:, max_tokens: } }
      def create_batch(requests:)
        response = faraday_post(BATCH_API_URL, { requests: requests }.to_json)
        parsed = JSON.parse(response.body)

        unless response.status == 200
          raise "Claude Batch API Error (#{response.status}): #{parsed['error']&.dig('message') || response.body}"
        end

        parsed
      end

      # Check batch status
      def get_batch(batch_id:)
        response = faraday_get("#{BATCH_API_URL}/#{batch_id}")
        parsed = JSON.parse(response.body)

        unless response.status == 200
          raise "Claude Batch API Error (#{response.status}): #{parsed['error']&.dig('message') || response.body}"
        end

        parsed
      end

      # Fetch batch results (JSONL)
      def get_batch_results(batch_id:)
        response = faraday_get("#{BATCH_API_URL}/#{batch_id}/results")

        unless response.status == 200
          raise "Claude Batch Results Error (#{response.status}): #{response.body}"
        end

        # Response is JSONL (one JSON object per line)
        response.body.lines.map { |line| JSON.parse(line.strip) }.reject(&:blank?)
      end

      private

      def build_body(model:, system:, messages:, tools:, max_tokens:)
        body = {
          model: model,
          max_tokens: max_tokens,
          system: system,
          messages: messages
        }
        body[:tools] = tools if tools.any?
        body
      end

      def post_messages(body)
        response = faraday_post(API_URL, body.to_json)
        parsed = JSON.parse(response.body)

        unless response.status == 200
          raise "Claude API Error (#{response.status}): #{parsed['error']&.dig('message') || response.body}"
        end

        log_usage(parsed)
        parsed
      end

      def log_usage(parsed)
        usage = parsed["usage"]
        return unless usage

        parts = []
        parts << "input=#{usage['input_tokens']}"
        parts << "output=#{usage['output_tokens']}"
        parts << "cache_creation=#{usage['cache_creation_input_tokens']}" if usage["cache_creation_input_tokens"]&.positive?
        parts << "cache_read=#{usage['cache_read_input_tokens']}" if usage["cache_read_input_tokens"]&.positive?
        Rails.logger.info("[Claude] #{parsed['model']} | #{parts.join(' | ')}")
      end

      def extract_text(parsed)
        text_blocks = parsed["content"]
          .select { |c| c["type"] == "text" }
          .map { |c| c["text"] }
          .join("\n")

        { raw_response: parsed, text: text_blocks }
      end

      def faraday_post(url, json_body)
        Faraday.post(url) do |req|
          apply_headers(req)
          req.body = json_body
          req.options.timeout = 120
          req.options.open_timeout = 10
        end
      end

      def faraday_get(url)
        Faraday.get(url) do |req|
          apply_headers(req)
          req.options.timeout = 120
          req.options.open_timeout = 10
        end
      end

      def apply_headers(req)
        req.headers["Content-Type"] = "application/json"
        req.headers["x-api-key"] = @api_key
        req.headers["anthropic-version"] = "2023-06-01"
      end
    end
  end
end
