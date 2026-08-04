require 'net/http'
require 'uri'
require 'nokogiri'

class ProfileScraper
  def initialize(profile, timeout: 25, headless: true, sleep_retry: 5)
    @profile = profile
    @timeout = timeout
    # headless и sleep_retry оставлены для совместимости инициализации, но браузер больше не нужен
  end

  def call
    uri = URI.parse(@profile.url)
    
    # Настраиваем HTTP-клиент с обработкой редиректов вручную или через Net::HTTP
    response = fetch_with_redirects(uri)

    unless response
      puts "Failed to fetch profile: #{@profile.id}"
      return
    end

    status_code = response.code.to_i
    @profile.status = status_code

    # Проверяем, был ли редирект (Net::HTTP сам следует по редиректам, поэтому смотрим конечный URL)
    final_url = response.uri.to_s
    if final_url != @profile.url
      @profile.redirected = true
      @profile.redirected_to = final_url
      @profile.save
      puts "Redirect detected for profile #{@profile.id}: #{@profile.url} -> #{final_url}"
      return
    elsif status_code != 200
      @profile.redirected = false
      @profile.save
      puts "Non-200 status (#{status_code}) for profile #{@profile.id}. Skipping snapshot."
      return
    end

    @profile.redirected = false

    # Парсим полученный чистый HTML через Nokogiri
    doc = Nokogiri::HTML(response.body)
    doc.search('script, style, link, meta, noscript').remove
    html = doc.to_html

    Shot.create!(
      profile_id: @profile.id,
      html_content: html
    )

    @profile.scraped_at = Time.current
    @profile.save

    puts "Successfully saved shot for profile: #{@profile.id} (status: #{status_code})"

  rescue StandardError => e
    puts "Exception Class: #{e.class.name}"
    puts "Exception Message: #{e.message}"
  end

  private

  # Метод для безопасной загрузки с поддержкой редиректов (до 5 раз)
  def fetch_with_redirects(uri, limit = 5)
    raise 'HTTP redirect too deep' if limit <= 0

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = @timeout
    http.read_timeout = @timeout

    request = Net::HTTP::Get.new(uri.request_uri)
    # Обязательно передаем User-Agent, чтобы сайт не блокировал скрипт
    request['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

    response = http.request(request)

    case response
    when Net::HTTPSuccess
      # Привязываем конечный URI к объекту ответа для проверки редиректов
      response.instance_variable_set(:@uri, uri)
      response
    when Net::HTTPRedirection
      redirect_url = response['location']
      new_uri = URI.parse(redirect_url)
      new_uri = uri.merge(new_uri) if new_uri.relative?
      fetch_with_redirects(new_uri, limit - 1)
    else
      response.instance_variable_set(:@uri, uri)
      response
    end
  end
end