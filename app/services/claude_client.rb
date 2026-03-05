class ClaudeClient
  API_URL = "https://api.anthropic.com/v1/messages"

  def initialize(api_key:)
    @api_key = api_key
  end

  def call(model:, system:, prompt:, tools: [], max_tokens: 4096)
    messages = [{ role: "user", content: prompt }]

    body = {
      model: model,
      max_tokens: max_tokens,
      system: system,
      messages: messages
    }

    body[:tools] = tools if tools.any?

    response = Faraday.post(API_URL) do |req|
      req.headers["Content-Type"] = "application/json"
      req.headers["x-api-key"] = @api_key
      req.headers["anthropic-version"] = "2023-06-01"
      req.body = body.to_json
      req.options.timeout = 120
      req.options.open_timeout = 10
    end

    parsed = JSON.parse(response.body)

    if response.status != 200
      raise "Claude API Error (#{response.status}): #{parsed['error']&.dig('message') || response.body}"
    end

    text_blocks = parsed["content"]
      .select { |c| c["type"] == "text" }
      .map { |c| c["text"] }
      .join("\n")

    { raw_response: parsed, text: text_blocks }
  end
end
