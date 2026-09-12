(function () {
  console.log('[parser] content script загружен на', window.location.href);

  let sent = false; // страховка от двойной отправки (свой hash-чек + FORCE_PARSE из background.js)

  // Тяжёлые SPA (замечено на Google Maps) на document_idle ещё показывают
  // пустой скелет — карточка заведения (рейтинг/отзывы/цена) дорисовывается
  // JS-ом уже ПОСЛЕ этого события, отдельным асинхронным запросом. Захват
  // outerHTML сразу же даёт 220KB разметки без единого текстового узла —
  // проверено на 12 реальных снапшотах Google Maps, во всех document.body
  // содержал только пустые <div> с хешированными классами.
  // Поэтому ждём, пока в body не появится ощутимый объём видимого текста
  // (или не истечёт максимальное время ожидания), и только потом снимаем
  // outerHTML.
  function waitForRenderedContent(maxWaitMs = 10000, checkIntervalMs = 300, minTextLength = 300) {
    return new Promise((resolve) => {
      const start = Date.now();
      const check = () => {
        const textLength = document.body ? document.body.innerText.trim().length : 0;
        if (textLength >= minTextLength || Date.now() - start >= maxWaitMs) {
          resolve();
        } else {
          setTimeout(check, checkIntervalMs);
        }
      };
      check();
    });
  }

  async function parseAndSend(keepHtml, local) {
    if (sent) return;
    sent = true;

    console.log('[parser] Ждём отрисовки страницы...');
    await waitForRenderedContent();

    console.log(
      '[parser] Начинаем сбор данных...',
      keepHtml ? '(с сохранением html_content)' : '',
      local ? '(на локальный дев-сервер)' : ''
    );

    // restaurant_id не передаём — сохранённый HTML привязывается к Profile
    // на сервере по самому url при парсинге, отдельный id не нужен.
    const cleanUrl = window.location.href
      .replace(/[?&]parse_profile=true/, '')
      .replace(/#profile_local_html$/, '')
      .replace(/#profile_local$/, '')
      .replace(/#profile_html$/, '')
      .replace(/#profile$/, '');

    const payload = {
      url: cleanUrl,
      html: document.documentElement.outerHTML,
      // #profile_html вместо #profile — сервер не затирает html_content
      // после разбора, даже если для сайта есть детерминированный парсер
      // (см. keep_html в post '/api/parse', app.rb). Нужно для сбора
      // реальных образцов при обкатке новых парсеров в lib/parsers.
      keep_html: !!keepHtml
    };

    // Сам fetch выполняется в background.js (service worker), а не здесь —
    // fetch напрямую из content script на другой origin (http://127.0.0.1)
    // с https-страницы блокируется как mixed content/CORS. Background script
    // с host_permissions в manifest.json от этого не страдает. local — не
    // часть payload (сервер про него не знает), просто говорит background.js,
    // на какой ENDPOINT слать этот конкретный запрос.
    chrome.runtime.sendMessage({ type: 'PARSE_PROFILE', payload, local: !!local }, (response) => {
      if (chrome.runtime.lastError) {
        alert(`❌ Ошибка расширения: ${chrome.runtime.lastError.message}`);
        return;
      }

      if (response && response.ok) {
        console.log('Успешно отправлено на сервер:', response.data);
      } else {
        const details = (response && response.error) || 'неизвестная ошибка';
        alert(`❌ Не удалось отправить данные на сервер!\n\nДетали ошибки: ${details}`);
      }
    });
  }

  // Четыре варианта маркера — независимо комбинируются keep_html (сохранить
  // html_content целиком) и local (слать на локальный дев-сервер вместо
  // прода): #profile, #profile_html, #profile_local, #profile_local_html.
  // Query-параметр (?parse_profile=true) некоторые сайты (например
  // TripAdvisor) обрезают редиректом на канонический URL раньше, чем
  // успеет отработать content script, поэтому его тоже проверяем — всегда
  // прод, без keep_html (для локальной отладки используйте hash-маркеры).
  const MARKERS = {
    '#profile': { keepHtml: false, local: false },
    '#profile_html': { keepHtml: true, local: false },
    '#profile_local': { keepHtml: false, local: true },
    '#profile_local_html': { keepHtml: true, local: true }
  };

  const searchParams = new URLSearchParams(window.location.search);
  const marker = MARKERS[window.location.hash];
  if (searchParams.get('parse_profile') === 'true') parseAndSend(false, false);
  else if (marker) parseAndSend(marker.keepHtml, marker.local);

  // Фолбэк: некоторые ссылки (например короткие https://maps.app.goo.gl/...)
  // уходят через цепочку редиректов, где Google на одном из хопов пересобирает
  // целевой URL из своего параметра continue= — fragment при этом теряется
  // ещё до того, как мы окажемся здесь. background.js отслеживает такие
  // переходы через chrome.webNavigation по tabId (а не по содержимому URL) и
  // просит досчитать разбор принудительно, если fragment не дожил — заодно
  // сообщает, каким именно маркером вкладка была помечена изначально.
  chrome.runtime.onMessage.addListener((message) => {
    if (message.type === 'FORCE_PARSE') parseAndSend(message.keepHtml, message.local);
  });
})();
