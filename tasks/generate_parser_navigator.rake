namespace :export do
  desc "Сгенерировать HTML-навигатор по profile.url без snap_shot, для расширения-парсера (rake export:parser_navigator[site_domain])"
  task :parser_navigator, [:site_domain] do |_t, args|
    domain = args[:site_domain] || 'tripadvisor.com'
    site = Site.find_by!(domain: domain)

    urls = Profile.where(site: site).where.missing(:snap_shots).pluck(:url)

    out_path = File.expand_path("../tmp/parser_navigator_#{domain}.html", __dir__)
    FileUtils.mkdir_p(File.dirname(out_path))

    File.write(out_path, <<~HTML)
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>Parser navigator — #{domain}</title>
        <style>
          body { font-family: sans-serif; padding: 20px; max-width: 700px; }
          #status { font-size: 1.1em; margin: 20px 0; }
          #log { font-size: 0.85em; color: #666; white-space: pre-wrap; max-height: 300px; overflow-y: auto; border: 1px solid #ddd; padding: 8px; }
          button { font-size: 1em; padding: 8px 16px; }
          input { width: 60px; }
        </style>
      </head>
      <body>
        <h1>Parser navigator — #{domain}</h1>
        <p>#{urls.size} URL без snap_shot.</p>
        <p>
          Задержка между переходами (сек):
          <input type="number" id="delay" value="10" min="3">
        </p>
        <button id="start">Старт</button>
        <button id="stop" disabled>Стоп</button>
        <div id="status">Не запущено</div>
        <div id="log"></div>

        <script>
          const urls = #{urls.to_json};
          let index = 0;
          let running = false;
          let popupWindow = null;
          let timer = null;

          const statusEl = document.getElementById('status');
          const logEl = document.getElementById('log');
          const startBtn = document.getElementById('start');
          const stopBtn = document.getElementById('stop');
          const delayInput = document.getElementById('delay');

          function log(msg) {
            logEl.textContent = new Date().toLocaleTimeString() + ' — ' + msg + '\\n' + logEl.textContent;
          }

          function openNext() {
            if (!running) return;

            if (index >= urls.length) {
              statusEl.textContent = 'Готово! Обработано ' + urls.length + ' из ' + urls.length;
              running = false;
              startBtn.disabled = false;
              stopBtn.disabled = true;
              return;
            }

            const url = urls[index] + '#profile';
            statusEl.textContent = 'Открываю ' + (index + 1) + ' из ' + urls.length;
            log(url);

            if (!popupWindow || popupWindow.closed) {
              popupWindow = window.open(url, 'profileParserTab');
            } else {
              popupWindow.location.href = url;
            }

            index++;
            const delayMs = Math.max(3, parseInt(delayInput.value, 10) || 10) * 1000;
            timer = setTimeout(openNext, delayMs);
          }

          startBtn.addEventListener('click', () => {
            running = true;
            startBtn.disabled = true;
            stopBtn.disabled = false;
            openNext();
          });

          stopBtn.addEventListener('click', () => {
            running = false;
            clearTimeout(timer);
            startBtn.disabled = false;
            stopBtn.disabled = true;
            statusEl.textContent = 'Остановлено на ' + index + ' из ' + urls.length;
          });
        </script>
      </body>
      </html>
    HTML

    puts "Написано #{urls.size} url в #{out_path}"
  end
end
