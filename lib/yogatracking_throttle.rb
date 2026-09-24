require 'faraday'

# Единая точка входа для запросов к yogatracking.cfm (кнопка "Website" на
# странице профиля — редирект-трекер, отдающий 302 с реальным адресом
# бизнеса в Location).
#
# Эндпоинт держит общий rate-limit НА ВЕСЬ исходящий IP (не на yoganumber):
# в ручных тестах ~10 запросов подряд без пауз хватало, чтобы он перестал
# отдавать Location и начал отвечать 200 "No Information Found" на ЛЮБОЙ
# yoganumber, включая уже нормально резолвившиеся раньше. Время
# восстановления не фиксированное — первое срабатывание отпустило примерно
# через 40с, но после нескольких срабатываний подряд не отпускало и через
# 6+ минут полной тишины (похоже на эскалацию при повторных нарушениях).
#
# Отсюда две защиты:
#   1) Все обращения из ВСЕХ потоков идут через один Mutex с минимальным
#      интервалом между запросами — не пытаемся вообще приблизиться к
#      порогу, вместо того чтобы ловить бан и потом отходить.
#   2) "Пустой" ответ (200 без Location) сам по себе не считается "сайта
#      нет" — подтверждаем канарейкой (id, у которого сайт точно есть).
#      Без этого один бан молча портит website всем необработанным
#      профилям до конца прогона — именно так пропал website почти у всех
#      15754 строк в csv/yogafinder_parsed.jsonl при первом прогоне
#      parse_profiles (8 потоков, без throttle): website нашёлся у 3.
module YogaTrackingThrottle
  BASE_URL = "https://www.yogafinder.com"

  MIN_INTERVAL = 4.0  # секунд между запросами к трекеру; с запасом над безопасными ~3.5с из ручных тестов
  COOLDOWN = 90        # секунд паузы при похожем на бан ответе, прежде чем пробовать снова
  MAX_ATTEMPTS = 5     # после стольких неудачных подтверждений подряд — сдаёмся, пусть вызывающий код пере-попробует позже

  CANARY_ID = "45852"  # Lumeria Maui — стабильно отдаёт Location на момент написания; используется только для отличия бана от настоящего отсутствия сайта

  BlockedError = Class.new(StandardError)

  @mutex = Mutex.new
  @last_request_at = nil

  class << self
    # tracking_path — "yogatracking.cfm?yoganumber=N" (или просто N, см.
    # ниже) — href кнопки Website со страницы профиля. connection —
    # Faraday вызывающего потока, переиспользуем его.
    #
    # Возвращает URL сайта или nil, если сайта действительно нет
    # (подтверждено канарейкой). Бросает BlockedError, если за
    # MAX_ATTEMPTS не удалось отличить бан от отсутствия — вызывающий код
    # должен такой profile считать НЕ обработанным (retry на следующем
    # прогоне), а не website=nil.
    def resolve(tracking_path, connection:)
      path = normalize(tracking_path)
      return nil if path.nil?

      attempts = 0
      loop do
        location = fetch_location(path, connection)
        return location if location

        canary_location = fetch_location(normalize(CANARY_ID), connection)
        return nil if canary_location # канарейка жива -> у tracking_path реально нет сайта

        attempts += 1
        raise BlockedError, "yogatracking.cfm ещё не отпустило после #{attempts} попыток" if attempts >= MAX_ATTEMPTS

        sleep(COOLDOWN)
      end
    end

    private

    # Принимает и полный href ("yogatracking.cfm?yoganumber=123"), и
    # голый yoganumber ("123") — второе удобно при пере-резолве по уже
    # сохранённому yoganumber без похода за страницей профиля.
    def normalize(tracking_path_or_id)
      return nil if tracking_path_or_id.to_s.strip.empty?

      tracking_path_or_id.to_s.include?("yogatracking.cfm") ? tracking_path_or_id.to_s : "yogatracking.cfm?yoganumber=#{tracking_path_or_id}"
    end

    def fetch_location(path, connection)
      throttle!
      response = connection.get("#{BASE_URL}/#{path.sub(%r{\A/}, '')}")
      response.headers['location'].to_s.strip.presence
    rescue Faraday::Error
      nil
    end

    # Держит mutex во время sleep намеренно — это то, что реально
    # сериализует запросы из всех потоков разом, а не просто защищает
    # чтение/запись @last_request_at.
    def throttle!
      @mutex.synchronize do
        if @last_request_at
          wait = MIN_INTERVAL - (Time.now - @last_request_at)
          sleep(wait) if wait > 0
        end
        @last_request_at = Time.now
      end
    end
  end
end
