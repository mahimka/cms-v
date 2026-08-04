require 'ferrum'
require 'nokogiri'

class ProfileScraper
  def initialize(profile, timeout: 25, headless: true, sleep_retry: 5)
    @profile = profile
    @timeout = timeout
    @headless = headless
    @sleep_retry = sleep_retry
  end

  def call
    begin
      @browser = Ferrum::Browser.new(timeout: @timeout, headless: @headless)
      
      # Перехватываем лишние ресурсы (скрипты, стили, картинки, шрифты), 
      # чтобы страница не висела на фоновых запросах.
      @browser.network.intercept
      @browser.on(:request) do |request|
        if %w[Image Font Stylesheet Script].include?(request.resource_type) || request.url.include?('commercekit-ajax')
          request.abort
        else
          request.continue
        end
      end

      # Метод goto возвращает объект response
      response = @browser.goto(@profile.url)
      
      process_response(response, forced: false)

    rescue Ferrum::PendingConnectionsError, Ferrum::TimeoutError => e
      # Если соединение всё же зависло, но HTML уже отрендерился в памяти — спасаем то, что есть
      if @browser && @browser.body.present?
        # Создаем фиктивный объект ответа со статусом 200 для экстренного сохранения
        fake_response = Struct.new(:status).new(200)
        process_response(fake_response, forced: true)
      else
        @timeout += 5
        sleep(rand(@sleep_retry))
        retry
      end

    rescue Ferrum::NodeNotFoundError => e
      sleep(rand(@sleep_retry))
      retry

    rescue Exception => e
      puts "Exception Class: #{e.class.name}"
      puts "Exception Message: #{e.message}"
    ensure
      @browser&.quit
    end
  end

  private

  def process_response(response, forced: false)
    status_code = response ? response.status : 200
    current_url = @browser.current_url

    @profile.status = status_code

    if current_url != @profile.url
      @profile.redirected = true
      @profile.redirected_to = current_url
      @profile.save
      puts "Redirect detected for profile #{@profile.id}: #{@profile.url} -> #{current_url}"
      return
    elsif status_code != 200 && !forced
      @profile.redirected = false
      @profile.save
      puts "Non-200 status (#{status_code}) for profile #{@profile.id}. Skipping snapshot."
      return
    end

    @profile.redirected = false

    # Чистим HTML через Nokogiri
    doc = Nokogiri::HTML(@browser.body)
    doc.search('script, style, link, meta, noscript').remove
    html = doc.to_html

    Shot.create!(
      profile_id: @profile.id,
      html_content: html
    )

    @profile.scraped_at = Time.current
    @profile.save

    puts "Successfully saved shot for profile: #{@profile.id} (status: #{status_code})"
  end
end