(function () {
  console.log('[parser] content script загружен на', window.location.href);

  // Query-параметры (?parse_profile=true) некоторые сайты (например
  // TripAdvisor) обрезают редиректом на канонический URL раньше, чем успеет
  // отработать content script. Fragment (#parse_profile=true) сервер вообще
  // не видит и не может обрезать — браузер сам переносит его через редирект,
  // так что проверяем оба варианта.
  const searchParams = new URLSearchParams(window.location.search);
  const hashParams = new URLSearchParams(window.location.hash.replace(/^#/, ''));

  const shouldParse = searchParams.get('parse_profile') === 'true' || hashParams.get('parse_profile') === 'true';
  if (!shouldParse) return;

  console.log('[parser] Найден parse_profile=true. Начинаем сбор данных...');

  // restaurant_id не передаём — сохранённый HTML привязывается к Profile
  // на сервере по самому url при парсинге, отдельный id не нужен.
  const cleanUrl = window.location.href
    .replace(/[?&]parse_profile=true/, '')
    .replace(/#parse_profile=true/, '');

  const payload = {
    url: cleanUrl,
    html: document.documentElement.outerHTML
  };

  // Сам fetch выполняется в background.js (service worker), а не здесь —
  // fetch напрямую из content script на другой origin (http://127.0.0.1)
  // с https-страницы блокируется как mixed content/CORS. Background script
  // с host_permissions в manifest.json от этого не страдает.
  chrome.runtime.sendMessage({ type: 'PARSE_PROFILE', payload }, (response) => {
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
})();
