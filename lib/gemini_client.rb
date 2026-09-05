require 'net/http'
require 'json'
require 'uri'
require 'retryable'

# Тонкий клиент к Gemini API (Generative Language API) — без отдельного
# гема, тем же приёмом, что и Beds24Client: голый Net::HTTP + JSON.
# 429/5xx ретраятся сами (см. RETRYABLE_STATUSES) — на free tier это
# обычный, ожидаемый ответ при пачке запросов подряд (например, кнопка
# "перевести на все"), а не повод падать. Остальные ошибки поднимаются
# наверх как есть.
class GeminiClient
  BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models".freeze
  DEFAULT_MODEL = "gemini-flash-latest".freeze
  RETRYABLE_STATUSES = %w[429 500 502 503 504].freeze
  RETRY_TRIES = 5

  RateLimitedError = Class.new(StandardError)

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

  # Переводит ОДНУ строку сразу на несколько языков одним вызовом — для
  # Tag/Label, где все переводы лежат в одном hash-столбце translations
  # (в отличие от Page, где у каждого языка отдельная запись, см.
  # translate_batch выше).
  #
  # to — массив кодов языков. Возвращает { "en" => "...", "de" => "..." }.
  def translate_to_languages(text, from:, to:)
    return {} if text.nil? || text.strip.empty? || to.empty?

    schema = {
      type: "OBJECT",
      properties: to.to_h { |lang| [lang, { type: "STRING" }] },
      required: to
    }

    JSON.parse(generate(build_translate_to_languages_prompt(text, from: from, to: to), response_schema: schema))
  end

  # instructions — сайт/тип-специфичный текст (см. project/prompts/*.txt),
  # что именно извлекать. Формат ответа (markers/details) — общий для всех
  # промптов, задаётся здесь, чтобы вызывающий код не зависел от того, как
  # именно каждый промпт сформулирован.
  #
  # Схема — списки пар {group, values}/{key, value}, а не объект с
  # динамическими ключами: Gemini structured output трактует OBJECT без
  # перечисленных properties как "разрешённых полей нет" и возвращает {}
  # (проверено вживую), а имя группы/ключа как ЗНАЧЕНИЕ строки — это как раз
  # то место, где схема может быть открытой.
  #
  # Возвращает { "markers" => { "группа" => [...] }, "details" => { "ключ" => "значение" } }
  # (в hash уже здесь, вызывающему коду не нужно знать про промежуточный
  # список пар).
  def extract_profile_data(html, instructions:)
    schema = {
      type: "OBJECT",
      properties: {
        markers: {
          type: "ARRAY",
          items: {
            type: "OBJECT",
            properties: {
              group: { type: "STRING" },
              values: { type: "ARRAY", items: { type: "STRING" } }
            },
            required: %w[group values]
          }
        },
        details: {
          type: "ARRAY",
          items: {
            type: "OBJECT",
            properties: {
              key: { type: "STRING" },
              value: { type: "STRING" }
            },
            required: %w[key value]
          }
        }
      },
      required: %w[markers details]
    }

    raw = JSON.parse(generate(build_extract_prompt(instructions, html), response_schema: schema))

    {
      "markers" => raw["markers"].to_a.to_h { |m| [m["group"], m["values"]] },
      "details" => raw["details"].to_a.to_h { |d| [d["key"], d["value"]] }
    }
  end

  private

  def build_extract_prompt(instructions, html)
    <<~PROMPT
      #{instructions}

      Верни JSON строго такой структуры:
      {
        "markers": [ { "group": "группа", "values": ["значение1", "значение2"] } ],
        "details": [ { "key": "ключ", "value": "значение" } ]
      }

      Никаких пояснений, markdown-обёртки или комментариев — только сам JSON.
      Если извлекать нечего — верни пустые списки [] для markers и/или details, не null.

      HTML страницы:
      #{html}
    PROMPT
  end

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
      - Исключение: если внутри <%= ... %> в именованном аргументе вида
        anchor_text:, title: или kicker: передаётся видимый текст (строка
        в кавычках) — переведи именно это значение, остальной код вокруг
        (имя хелпера, url, прочие аргументы вроде cards_uris:, text_on_card:,
        css_class:) — не трогай.
      - Сохраняй форматирование: переносы строк, markdown-разметку, если она
        есть в исходном тексте.

      JSON:
      #{JSON.generate(texts)}
    PROMPT
  end

  def build_translate_to_languages_prompt(text, from:, to:)
    <<~PROMPT
      Переведи текст ниже с языка "#{from}" на каждый из языков: #{to.join(', ')}.
      Верни JSON, где ключ — код языка, значение — перевод текста на этот язык.
      Без пояснений, без markdown-обёртки, без комментариев — только сам JSON.

      Текст:
      #{text}
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

    request_body = JSON.generate({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: generation_config
    })

    response = Retryable.retryable(tries: RETRY_TRIES, on: RateLimitedError, sleep: ->(n) { 2**n }) do
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 15
      # extract_profile_data гонит целую (пусть и почищенную) HTML-страницу
      # в промпте — дефолтных 60s read_timeout на это не хватает.
      http.read_timeout = 180

      request = Net::HTTP::Post.new(uri)
      request['content-type'] = 'application/json'
      request['x-goog-api-key'] = @api_key
      request.body = request_body

      resp = http.request(request)

      raise RateLimitedError, "Gemini API #{resp.code}: #{resp.body}" if RETRYABLE_STATUSES.include?(resp.code)

      resp
    end

    raise "Gemini API Error: #{response.code} - #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    text = data.dig("candidates", 0, "content", "parts", 0, "text")

    raise "Gemini API: пустой ответ (#{data.inspect})" if text.nil?

    text
  end
end
