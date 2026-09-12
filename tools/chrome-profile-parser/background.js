const ENDPOINT_PROD = 'https://diversorio.com/api/parse';
const ENDPOINT_LOCAL = 'http://127.0.0.1:9292/api/parse'; // тоже в host_permissions manifest.json
const API_KEY = 'prs_e64124a1c131393c88ef56bb5d84bd49'; // endpoint и ключ проверяются на сервере одинаково в обоих случаях (см. post '/api/parse' в app.rb, settings.api_key_for_parser)

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type !== 'PARSE_PROFILE') return;

  const endpoint = message.local ? ENDPOINT_LOCAL : ENDPOINT_PROD;

  fetch(endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-API-Key': API_KEY
    },
    body: JSON.stringify(message.payload)
  })
    .then((res) => res.json().then((data) => ({ status: res.status, data })))
    .then(({ status, data }) => {
      if (status >= 200 && status < 300) {
        sendResponse({ ok: true, data });
      } else {
        sendResponse({ ok: false, error: data.error || `HTTP ${status}` });
      }
    })
    .catch((err) => {
      sendResponse({ ok: false, error: err.message });
    });

  return true; // держим канал открытым для асинхронного sendResponse
});

// --- Фолбэк для ссылок, теряющих #profile*-маркер в цепочке редиректов ---
// Короткие ссылки вида https://maps.app.goo.gl/... уходят через несколько
// хопов (goo.gl -> maps.google.com -> consent.google.com -> maps.google.com),
// и хотя бы один из них Google собирает не через обычный Location-редирект
// (где браузер сам переносит fragment), а пересобирает целевой URL из своего
// параметра continue= — fragment в этом месте теряется безвозвратно, и
// content.js к моменту document_idle его уже не видит.
//
// Поэтому вместо того чтобы полагаться только на fragment, доживший до
// финальной страницы, отмечаем вкладку ещё на старте навигации (пока
// исходный URL с маркером только запрашивается) и, если после полной
// загрузки fragment пропал, просим content script разобрать страницу
// принудительно — заодно передаём, каким именно маркером вкладка была
// помечена изначально (keepHtml — #profile_html/#profile_local_html;
// local — #profile_local/#profile_local_html, слать на локальный сервер).
function matchProfileMarker(url) {
  if (url.endsWith('#profile_local_html')) return { matched: true, keepHtml: true, local: true };
  if (url.endsWith('#profile_local')) return { matched: true, keepHtml: false, local: true };
  if (url.endsWith('#profile_html')) return { matched: true, keepHtml: true, local: false };
  if (url.endsWith('#profile')) return { matched: true, keepHtml: false, local: false };
  if (/[?&]parse_profile=true(&|$)/.test(url)) return { matched: true, keepHtml: false, local: false };
  return { matched: false };
}

const armedTabs = new Map(); // tabId -> { keepHtml, local }

chrome.webNavigation.onBeforeNavigate.addListener((details) => {
  if (details.frameId !== 0) return;
  const marker = matchProfileMarker(details.url);
  if (marker.matched) {
    armedTabs.set(details.tabId, { keepHtml: marker.keepHtml, local: marker.local });
  }
});

chrome.webNavigation.onCompleted.addListener((details) => {
  if (details.frameId !== 0) return;
  if (!armedTabs.has(details.tabId)) return;
  const armed = armedTabs.get(details.tabId);
  armedTabs.delete(details.tabId);

  if (matchProfileMarker(details.url).matched) {
    return; // fragment дожил сам — content.js уже отправил разбор
  }

  chrome.tabs.sendMessage(details.tabId, { type: 'FORCE_PARSE', keepHtml: armed.keepHtml, local: armed.local });
});

chrome.webNavigation.onErrorOccurred.addListener((details) => {
  armedTabs.delete(details.tabId);
});

chrome.tabs.onRemoved.addListener((tabId) => armedTabs.delete(tabId));
