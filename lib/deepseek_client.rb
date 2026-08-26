require 'net/http'
require 'json'
require 'uri'
require 'retryable'

# Клиент к DeepSeek через BytePlus Ark Responses API. Тот же приём, что и
# GeminiClient: голый Net::HTTP + JSON, без отдельного гема.
#
# У Ark Responses API нет подтверждённого strict JSON-schema режима (в
# отличие от Gemini responseSchema) — просим чистый JSON текстом в промпте
# и парсим ответ с защитой от markdown-обёртки (```json ... ```), которую
# reasoning-модели иногда добавляют вопреки инструкции.
class DeepseekClient
  BASE_URL = "https://ark.ap-southeast.bytepluses.com/api/v3/responses".freeze
  DEFAULT_MODEL = "deepseek-v4-flash-260425".freeze
  RETRYABLE_STATUSES = %w[429 500 502 503 504].freeze
  RETRY_TRIES = 5

  RateLimitedError = Class.new(StandardError)

  def initialize(api_key:, model: DEFAULT_MODEL)
    @api_key = api_key
    @model = model
  end

  # instructions — сайт/тип-специфичный текст (project/prompts/*.txt), что
  # именно извлекать. Формат ответа (markers/details) — общий, задаётся
  # здесь, тем же способом, что и у GeminiClient#extract_profile_data:
  # список пар {group, values}/{key, value}, а не объект с динамическими
  # ключами — имя группы/ключа тут ЗНАЧЕНИЕ строки, а не имя поля схемы.
  #
  # Возвращает { "markers" => { "группа" => [...] }, "details" => { "ключ" => "значение" } }
  def extract_profile_data(html, instructions:)
    raw = JSON.parse(strip_markdown_fence(generate(build_extract_prompt(instructions, html))))

    {
      "markers" => raw["markers"].to_a.to_h { |m| [m["group"], m["values"]] },
      "details" => raw["details"].to_a.to_h { |d| [d["key"], d["value"]] }
    }
  end

  private

  def build_extract_prompt(instructions, html)
    <<~PROMPT
      #{instructions}

      Верни JSON строго такой структуры, без пояснений, без markdown-обёртки
      (без ```), без комментариев — только сам JSON:
      {
        "markers": [ { "group": "группа", "values": ["значение1", "значение2"] } ],
        "details": [ { "key": "ключ", "value": "значение" } ]
      }

      Если извлекать нечего — верни пустые списки [] для markers и/или details, не null.

      HTML страницы:
      #{html}
    PROMPT
  end

  def strip_markdown_fence(text)
    text.strip.sub(/\A```(?:json)?\s*/, '').sub(/```\s*\z/, '')
  end

  def generate(prompt)
    uri = URI(BASE_URL)

    request_body = JSON.generate({
      model: @model,
      stream: false,
      input: [
        { role: "user", content: [{ type: "input_text", text: prompt }] }
      ]
    })

    response = Retryable.retryable(tries: RETRY_TRIES, on: RateLimitedError, sleep: ->(n) { 2**n }) do
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 15
      http.read_timeout = 180

      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{@api_key}"
      request['Content-Type'] = 'application/json'
      request.body = request_body

      resp = http.request(request)

      raise RateLimitedError, "DeepSeek API #{resp.code}: #{resp.body}" if RETRYABLE_STATUSES.include?(resp.code)

      resp
    end

    raise "DeepSeek API Error: #{response.code} - #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    message = data["output"]&.find { |o| o["type"] == "message" }
    text = message&.dig("content", 0, "text")

    raise "DeepSeek API: пустой ответ (#{data.inspect})" if text.nil?

    text
  end
end
