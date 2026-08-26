// Переключи на 'https://diversorio.com/api/parse' когда будешь готов слать
// на прод — endpoint и ключ проверяются на сервере одинаково в обоих случаях
// (см. post '/api/parse' в app.rb, settings.api_key_for_parser).
const ENDPOINT = 'http://127.0.0.1:4567/api/parse';
const API_KEY = 'prs_e64124a1c131393c88ef56bb5d84bd49';

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type !== 'PARSE_PROFILE') return;

  fetch(ENDPOINT, {
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
