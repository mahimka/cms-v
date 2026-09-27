require 'ferrum'
require 'mini_magick'
require 'fileutils'
require 'uri'
require 'date'
require_relative 'link_checker'
require_relative 'parsers/website_page_parser'

# Ferrum-скрапер для Link с label "website" (официальный сайт заведения):
# заходит под реальным UA, проверяет статус/редирект/"домен продаётся" (та
# же логика, что LinkChecker — только тут дополнительно нужен отрендеренный
# JS body для скриншота, поэтому статус проверяется на том же заходе в
# Ferrum, а не отдельным Net::HTTP запросом), и если сайт живой — снимает
# полностраничный скриншот и достаёт контакты/соцссылки (WebsitePageParser)
# в Picture/Link/Entity#address.
#
# Смоделирован на lib/profile_scraper_ferrum.rb (тот же browser lifecycle,
# те же исключения) — в отличие от него НЕ блокирует Image/Stylesheet/Script,
# потому что результат тут — визуальный скриншот, а не только HTML.
class WebsiteScraper
  UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
       "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

  SCREENSHOT_DIR = "screenshots"
  MAX_ATTEMPTS = 2

  # Скриншот — только видимая область (не full-page): сайт всё равно
  # показывает его в фиксированной is-4by3 CSS-рамке через object-fit:cover
  # (та же рамка, что у карточек заведений — см. app/controllers/
  # pictures_controller.rb#RATIOS и app/views/partials/_card*.erb), так что
  # весь длинный скролл ниже верхнего экрана всё равно был бы обрезан —
  # незачем его вообще снимать и хранить. 1200x900 = ровно 4:3.
  WINDOW_SIZE = [1200, 900].freeze
  PICTURE_RATIO = "is-4by3".freeze
  JPEG_QUALITY = 82

  # Пытается закрыть баннер согласия на куки/GDPR-плашку перед скриншотом —
  # сперва по ID кнопки у самых частых CMP (OneTrust/Cookiebot/Didomi/
  # Quantcast и т.п., быстро и точно), потом фоллбеком — по ключевым словам
  # кнопки на нескольких языках. Список слов конечен и точно не покрывает
  # все формулировки (сайты студий на en/de/it/fr/es/nl/pl попадались с
  # разными вариантами — "Ich stimme zu", "Alle akzeptieren", "accetta
  # tutti", "Accepteren", "Akceptuj" и т.п., и наверняка есть ещё) — вместо
  # точного совпадения всей фразы (было раньше, ломалось на каждую новую
  # формулировку) сравниваем по границе слова (\b), это переживает и
  # опечатки на конце фразы, и разный порядок слов. \b, а не includes() —
  # иначе короткие токены вроде "ok" ложно совпадают внутри "cookie"/"book".
  DISMISS_CONSENT_JS = <<~JS
    (function () {
      var knownSelectors = [
        '#onetrust-accept-btn-handler',
        '#CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll',
        '#CybotCookiebotDialogBodyButtonAccept',
        '.qc-cmp2-summary-buttons button[mode="primary"]',
        '#didomi-notice-agree-button',
        '.fc-cta-consent',
        '#accept-choices',
        '.cc-btn.cc-allow',
        '.cc-allow'
      ];
      for (var i = 0; i < knownSelectors.length; i++) {
        var el = document.querySelector(knownSelectors[i]);
        if (el) { el.click(); return 'selector:' + knownSelectors[i]; }
      }

      var acceptWords = [
        'accept all cookies', 'accept all', 'accept everything', 'accept everyting', 'accept',
        'i agree', 'agree', 'allow all', 'allow cookies', 'allow', 'consent',
        'got it', 'i understand', 'understood', 'ok',
        'ich stimme zu', 'zustimmen', 'akzeptieren', 'akzeptiere alle', 'alles akzeptieren',
        'alles akzeptiern', 'alle akzeptieren', 'akzeptiere', 'cookies akzeptieren', 'einverstanden',
        'accetta tutti', 'accetta tutto', 'accetta', 'accetto', 'acconsento',
        'tout accepter', "j'accepte", 'accepter',
        'aceptar todo', 'aceptar', 'acepto',
        'accepteren', 'akkoord',
        'akceptuj', 'aceptuj', 'zgadzam sie'
      ];
      var rejectWords = [
        'reject', 'decline', 'deny', 'manage', 'customise', 'customize', 'settings',
        'preferences', 'only necessary', 'more options',
        'ablehnen', 'verweigern', 'einstellungen', 'anpassen',
        'rifiuta', 'personalizza', 'impostazioni',
        'rechazar', 'configurar',
        'weiger', 'aanpassen', 'instellingen',
        'odrzuc', 'ustawienia'
      ];

      function escapeRe(s) { return s.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&'); }
      var acceptRe = new RegExp('\\\\b(' + acceptWords.map(escapeRe).join('|') + ')\\\\b', 'i');
      var rejectRe = new RegExp('\\\\b(' + rejectWords.map(escapeRe).join('|') + ')\\\\b', 'i');

      // Настоящие button/a/role=button — основной случай. Плюс, отдельно,
      // любые div/span ВНУТРИ явно cookie/consent-контейнера — часть CMP
      // (например итальянский "bottone_accetta") рисует кнопку голым div
      // без role и без тега button, обычный селектор такое не видит вообще.
      var candidates = Array.from(
        document.querySelectorAll('button, a, [role="button"], input[type="button"], input[type="submit"]')
      );
      var scopes = document.querySelectorAll(
        '[class*="cookie" i], [id*="cookie" i], [class*="consent" i], [id*="consent" i], ' +
        '[class*="gdpr" i], [id*="gdpr" i], [class*="cmp" i], [id*="cmp" i]'
      );
      for (var s = 0; s < scopes.length; s++) {
        candidates = candidates.concat(Array.from(scopes[s].querySelectorAll('div, span')));
      }

      var best = null;
      for (var i = 0; i < candidates.length; i++) {
        var el = candidates[i];
        var text = (el.innerText || el.value || el.getAttribute('aria-label') || '').trim();
        if (!text || text.length > 60) continue;
        if (rejectRe.test(text)) continue;
        if (!acceptRe.test(text)) continue;

        var rect = el.getBoundingClientRect();
        if (rect.width <= 0 || rect.height <= 0) continue;

        // Из нескольких совпадений (частый случай — обёртка вида
        // <div>кнопка1 кнопка2</div> сама тоже проходит текстовую проверку)
        // берём самый "вложенный" элемент — у него меньше всего дочерних
        // узлов, значит это и есть настоящая кнопка, а не её обёртка.
        var depth = el.querySelectorAll('*').length;
        if (!best || depth < best.depth) best = { el: el, text: text, depth: depth };
      }

      if (best) { best.el.click(); return 'text:' + best.text; }
      return null;
    })()
  JS

  # network.status иногда возвращает nil без единого исключения — сайт
  # ответил, но Ferrum не успел/не смог связать статус с главным запросом
  # (не так уж редко на медленных сайтах, живьём воспроизводится — один и
  # тот же URL то 200, то пустой статус без ошибки). Без этого класса такой
  # ответ тихо записывался бы как dead с первой же попытки, хотя сайт живой.
  class BlankStatusError < StandardError; end

  def initialize(link, timeout: 25, headless: true, sleep_retry: 5)
    @link = link
    @timeout = timeout
    @headless = headless
    @sleep_retry = sleep_retry
  end

  # Возвращает { status: :ok / :for_sale / :dead / :error, message: String }.
  def call
    entity = @link.linkable
    return { status: :error, message: "linkable не Entity" } unless entity.is_a?(Entity)

    begin
      # process_timeout — отдельный от timeout: (сетевого) таймаут на сам
      # запуск процесса Chrome. Дефолт гема — 10с, при 4 параллельных
      # потоках, стартующих Chrome одновременно, этого не хватало (~37
      # ProcessTimeoutError на 3900+ прогоне) — увеличиваем с запасом.
      @browser = Ferrum::Browser.new(timeout: @timeout, headless: @headless, window_size: WINDOW_SIZE,
                                      process_timeout: 20)
      @browser.headers.set("User-Agent" => UA, "Accept-Language" => "en-US,en;q=0.9")

      @browser.goto(@link.url)
      begin
        @browser.network.wait_for_idle(timeout: 5)
      rescue Ferrum::TimeoutError
        # лучше скриншотить то, что есть, чем падать — не у всех сайтов
        # сеть вообще успокаивается (постоянный поллинг/аналитика).
      end
      dismiss_cookie_consent!

      process_response(entity)
    rescue Ferrum::PendingConnectionsError, Ferrum::TimeoutError => e
      # retry запускает begin заново (новый @browser.new ниже) — ensure тут
      # не срабатывает (мы не покидаем блок), поэтому старый браузер нужно
      # закрыть явно, иначе на каждый повтор остаётся висящий headless Chrome.
      @browser&.quit
      @attempts = (@attempts || 0) + 1
      if @attempts > MAX_ATTEMPTS
        record_failure!("#{e.class}: #{e.message}")
      else
        @timeout += 5
        sleep(rand(@sleep_retry))
        retry
      end
    rescue Ferrum::NodeNotFoundError, BlankStatusError => e
      @browser&.quit
      @attempts = (@attempts || 0) + 1
      if @attempts > MAX_ATTEMPTS
        record_failure!("#{e.class}: #{e.message}")
      else
        sleep(rand(@sleep_retry))
        retry
      end
    rescue StandardError => e
      # Любая другая ошибка (в т.ч. Ferrum::StatusError — например битый
      # SSL-сертификат сайта) — не ретраим, но обязательно фиксируем в
      # Link через тот же LinkChecker.apply_result!, что и успешный путь:
      # иначе checked_at не обновится, и rake-таск (который отбирает
      # ссылки по "checked_at IS NULL OR < N дней назад") будет пытаться
      # тот же заведомо неработающий сайт на каждом прогоне.
      record_failure!("#{e.class}: #{e.message}")
    ensure
      @browser&.quit
    end
  end

  private

  def record_failure!(message)
    LinkChecker.apply_result!(@link, LinkChecker::Result.new(error: message))
    { status: :error, message: message }
  end

  # Не блокирующая неудача: если баннера нет, evaluate вернёт null, ничего
  # не произойдёт. Если что-то на странице ломает evaluate (редкий CSP-кейс
  # и т.п.) — просто не закрываем баннер, скриншот всё равно снимаем.
  def dismiss_cookie_consent!
    clicked = @browser.evaluate(DISMISS_CONSENT_JS)
    return unless clicked

    sleep 0.5

    # Часть CMP просто пишет cookie/localStorage на клик и полагается на
    # то, что баннер сам не отрендерится при следующей загрузке — саму
    # видимую плашку динамически не убирают (проверено на живом сайте:
    # cookie_gdpr_consent реально выставляется, а DOM баннера остаётся
    # нетронутым до перезагрузки). Значит один клик без перезахода не
    # гарантирует чистый скриншот — перезаходим на тот же URL и, если
    # вдруг вылезло что-то новое, пробуем ещё раз (без рекурсии дальше:
    # решает подавляющее большинство случаев, а зацикливаться на упрямых
    # баннерах — уже не про это).
    @browser.goto(@browser.current_url)
    begin
      @browser.network.wait_for_idle(timeout: 5)
    rescue Ferrum::TimeoutError
      nil
    end
    @browser.evaluate(DISMISS_CONSENT_JS)
    sleep 0.3
  rescue StandardError
    nil
  end

  # Многие сайты вешают lazy-load картинок на scroll/IntersectionObserver —
  # даже то, что попадает в самый первый экран, может остаться недогруженным
  # (пустые полосы на скриншоте), если ни разу не было события скролла.
  # Скроллим чуть вниз и обратно, как реальный пользователь, и даём сети
  # время догрузить то, что после этого включилось.
  def wait_for_render!
    @browser.evaluate("window.scrollTo(0, 400)")
    sleep 0.4
    @browser.evaluate("window.scrollTo(0, 0)")
    sleep 0.3

    @browser.network.wait_for_idle(timeout: 4)
  rescue StandardError
    nil
  end

  def process_response(entity)
    # browser.goto возвращает frameId (строку), а не response — правильный
    # способ получить статус главного запроса это network.status (см.
    # ferrum/network.rb#status, "shortcut for response.status"). Похожий код
    # в lib/profile_scraper_ferrum.rb дергает response.status у результата
    # goto — это NoMethodError на строке, молча проглатывается общим rescue
    # Exception там же; тут делаем правильно.
    status_code = @browser.network.status
    raise BlankStatusError, "network.status пустой при живом ответе" if status_code.blank?

    final_url = @browser.current_url
    body = @browser.body.to_s

    result = LinkChecker::Result.new(
      status_code: status_code,
      final_url: final_url,
      redirected: final_url != @link.url,
      body: body
    )
    LinkChecker.apply_result!(@link, result)

    return { status: :dead, message: @link.response } unless @link.alive?
    return { status: :for_sale, message: "похоже, домен продаётся — скриншот пропущен" } if LinkChecker.for_sale?(body)

    sync_entity!(entity, final_url, body)
    { status: :ok, message: @link.response }
  end

  def sync_entity!(entity, final_url, body)
    data = WebsitePageParser.new.extract(body)

    save_screenshot!(entity, final_url)
    create_contact_detail!(entity, 'phone', data['phone'])
    create_contact_detail!(entity, 'email', data['email'])
    create_social_links!(entity, data['social_links'])
    fill_address!(entity, data['address'])
  end

  def save_screenshot!(entity, final_url)
    domain = URI.parse(final_url).host.to_s.sub(/\Awww\./, '')
    return if domain.empty?

    # entity.id в имени обязателен — несколько entity нередко ссылаются на
    # один и тот же домен (франшизы/сети вроде CorePower Yoga с локациями на
    # одном сайте, или просто у нескольких записей совпал url), и без id все
    # они писали бы в один и тот же файл на диске, затирая скриншоты друг
    # друга (нашли на кейсе ion-club.net на kitezilla.com — 8 разных филиалов
    # делили один файл). Домен+дата оставлены для читаемости имени на диске.
    filename = "#{domain}-#{entity.id}-#{Date.today.iso8601}.jpg"
    relative_path = "/images/#{SCREENSHOT_DIR}/#{filename}"
    disk_path = File.join(PUBLIC_FOLDER, relative_path)
    FileUtils.mkdir_p(File.dirname(disk_path))

    wait_for_render!

    # Без full: — снимает ровно видимую область (WINDOW_SIZE), не всю
    # прокрутку. Кодирует сразу в JPEG (quality:) через сам Chrome — так
    # выходит компактнее PNG (без него полностраничный скриншот весил
    # 350КБ-2МБ, тут — обычно 60-150КБ) и не нужен отдельный шаг recompress
    # через MiniMagick.
    @browser.screenshot(path: disk_path, format: "jpeg", quality: JPEG_QUALITY)

    image = MiniMagick::Image.open(disk_path)

    # Имя файла содержит дату — повторный прогон в другой день иначе создавал
    # бы ещё одну Picture вместо замены старой (см. запрос пользователя
    # 2026-09-27: дубли копились по одной на каждый день перепрогона).
    # Один скриншот на entity: старые (включая отклонённые active: false)
    # удаляем перед записью новой.
    remove_other_screenshots!(entity, keep_path: relative_path)

    picture = Picture.find_or_initialize_by(imageable: entity, file: relative_path)
    picture.content_type = "image/jpeg"
    picture.width = image.width
    picture.height = image.height
    picture.ratio = PICTURE_RATIO
    picture.alt = build_alt_text(entity)
    picture.active = true
    picture.save!
  end

  def remove_other_screenshots!(entity, keep_path:)
    entity.pictures.where("file LIKE ?", "/images/#{SCREENSHOT_DIR}/%").where.not(file: keep_path).find_each do |old|
      disk = File.join(PUBLIC_FOLDER, old.file.to_s)
      File.delete(disk) if File.exist?(disk)
      old.destroy!
    end
  end

  def build_alt_text(entity)
    parts = [entity.name]

    styles = entity.tags_of_group('Yoga Style').limit(3).pluck(:name)
    parts << styles.join(', ') if styles.any?

    text = parts.join(' - ')

    locality = entity.tags_of_group('addressLocality').first&.name
    text += " in #{locality}" if locality

    text
  end

  # phone/email — в entity.details (Detail), а не Link: это не переходимая
  # ссылка, а значение (номер/адрес), плюс так их видно в тех же карточках
  # деталей, что и остальные данные заведения. WebsitePageParser уже отдаёт
  # значение без tel:/mailto: — тут просто кладём как есть.
  def create_contact_detail!(entity, label_name, value)
    return if value.blank?

    label = Label.find_by(name: label_name)
    return unless label
    return if entity.detail_records.exists?(label: label)

    entity.detail_records.create!(label: label, value: value)
  end

  def create_social_links!(entity, social_links)
    social_links.each do |label_name, url|
      next if entity.links.joins(:label).where(labels: { name: label_name }).exists?

      label = Label.find_by(name: label_name)
      next unless label

      entity.links.create!(label: label, url: url)
    end
  end

  def fill_address!(entity, address)
    return if address.blank? || entity.address.present?

    entity.update!(address: address)
  end
end
