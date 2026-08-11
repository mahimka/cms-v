require 'net/http'
require 'json'
require 'uri'

# Тонкий клиент к Gemini API (Generative Language API) — без отдельного
# гема, тем же приёмом, что и Beds24Client: голый Net::HTTP + JSON.
# Ошибки не глотает, а поднимает наверх — ретраи (retryable) и лимиты
# делает вызывающий код.
class GeminiClient
  BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models".freeze
  DEFAULT_MODEL = "gemini-flash-latest".freeze

  def initialize(api_key:, model: DEFAULT_MODEL)
    @api_key = api_key
    @model = model
  end

  # Переводит один или несколько текстовых полей ОДНИМ вызовом API.
  #
  # texts: { "title" => "...", "h1" => "..." } — произвольные ключи,
  # ответ гарантированно возвращается с теми же ключами (через JSON-схему
  # ответа), поэтому батчить поля одной страницы на один язык — безопасно.
  #
  # from/to — коды языков ("sl", "en" и т.п.), не названия языков.
  def translate_batch(texts, from:, to:)
    return {} if texts.nil? || texts.empty?

    schema = {
      type: "OBJECT",
      properties: texts.keys.to_h { |key| [key, { type: "STRING" }] },
      required: texts.keys
    }

    JSON.parse(generate(build_translate_prompt(texts, from: from, to: to), response_schema: schema))
  end

  # Перевод одной строки — через тот же translate_batch с одним ключом,
  # чтобы правила промпта (см. build_translate_prompt) были едины.
  def translate(text, from:, to:)
    return text if text.nil? || text.strip.empty?

    translate_batch({ "value" => text }, from: from, to: to)["value"]
  end

  private

  # я Claude (2026-08-11): промпт черновой — проговорено с автором, что
  # формулировку ещё будут уточнять (особенно про anchor_text). Ключевое,
  # что уже зафиксировано: <%= ... %> — код шаблона, не трогать, кроме
  # текста анкора внутри него.
  def build_translate_prompt(texts, from:, to:)
    <<~PROMPT
      Переведи значения из JSON ниже с языка "#{from}" на язык "#{to}".
      Верни JSON с теми же ключами и переведёнными значениями, без пояснений,
      без markdown-обёртки, без комментариев — только сам JSON.

      Правила:
      - Фрагменты вида <%= ... %> — код шаблона (ERB), их структуру и все
        символы внутри не менять и не переводить, копировать дословно.
      - Исключение: если внутри <%= ... %> передаётся anchor_text (видимый
        текст ссылки) — переведи именно это значение, остальной код вокруг
        (имя хелпера, url, прочие аргументы) — не трогай.
      - Сохраняй форматирование: переносы строк, markdown-разметку, если она
        есть в исходном тексте.

      JSON:
      #{JSON.generate(texts)}
    PROMPT
  end

  # Низкоуровневый вызов generateContent. response_schema, если передан,
  # включает structured output (JSON mode) — без него Gemini вернёт
  # обычный текст.
  def generate(prompt, response_schema: nil)
    uri = URI("#{BASE_URL}/#{@model}:generateContent")

    generation_config = { temperature: 0.2 }

    if response_schema
      generation_config[:responseMimeType] = "application/json"
      generation_config[:responseSchema] = response_schema
    end

    body = {
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: generation_config
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request['content-type'] = 'application/json'
    request['x-goog-api-key'] = @api_key
    request.body = JSON.generate(body)

    response = http.request(request)

    raise "Gemini API Error: #{response.code} - #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    text = data.dig("candidates", 0, "content", "parts", 0, "text")

    raise "Gemini API: пустой ответ (#{data.inspect})" if text.nil?

    text
  end
end
