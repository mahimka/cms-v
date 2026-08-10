/*
 * @@-автокомплит поиска страниц по h1 в textarea page[body]/page[faq]
 * (форма редактирования страницы в дереве, см. _tree_edit_form.erb).
 *
 * Печатаете "@@текст" — подгружается список подходящих по h1 страниц,
 * выбор (клик или ↑↓+Enter/Tab) вставляет вместо "@@текст" готовый
 * ERB-вызов link_to с этим uri и anchor_text = h1 найденной страницы.
 */
$(function () {
  var SELECTOR = 'textarea[name="page[body]"], textarea[name="page[faq]"]';
  var MAX_QUERY_LENGTH = 60;
  var SEARCH_DELAY = 250;

  var $dropdown = buildDropdown();
  var $activeTextarea = null;
  var mentionStart = null;
  var mentionEnd = null;
  var activeIndex = -1;
  var results = [];
  var searchTimer = null;
  var searchSeq = 0;
  var dismissedAt = null;

  injectStyles();

  $(document).on('input', SELECTOR, handleInput);
  $(document).on('keydown', SELECTOR, handleKeydown);

  $(document).on('blur', SELECTOR, function () {
    // задержка, чтобы mousedown по пункту списка успел сработать раньше blur
    setTimeout(function () {
      if (!$dropdown.is(':hover')) closeDropdown();
    }, 150);
  });

  $(document).on('click', function (event) {
    if (
      $dropdown.is(':visible') &&
      !$(event.target).closest('.page-mention-dropdown').length &&
      !$(event.target).is(SELECTOR)
    ) {
      closeDropdown();
    }
  });

  function handleInput() {
    var $ta = $(this);
    var el = this;
    var value = $ta.val();
    var caret = el.selectionStart;
    var textBeforeCaret = value.substring(0, caret);
    var idx = textBeforeCaret.lastIndexOf('@@');

    if (idx === -1) {
      closeDropdown();
      return;
    }

    var query = textBeforeCaret.substring(idx + 2);

    if (query.indexOf('\n') !== -1 || query.length > MAX_QUERY_LENGTH) {
      closeDropdown();
      return;
    }

    if (dismissedAt === idx) return;

    $activeTextarea = $ta;
    mentionStart = idx;
    mentionEnd = caret;

    openDropdown($ta, idx);

    clearTimeout(searchTimer);

    if (query.length === 0) {
      renderMessage('Введите текст для поиска…');
      return;
    }

    renderMessage('Поиск…');

    searchTimer = setTimeout(function () {
      runSearch(query);
    }, SEARCH_DELAY);
  }

  function handleKeydown(event) {
    if (!$dropdown.is(':visible')) return;

    if (event.key === 'Escape') {
      event.preventDefault();
      dismissedAt = mentionStart;
      closeDropdown();
      return;
    }

    if (event.key === 'ArrowDown') {
      event.preventDefault();
      setActiveIndex(activeIndex + 1);
      return;
    }

    if (event.key === 'ArrowUp') {
      event.preventDefault();
      setActiveIndex(activeIndex - 1);
      return;
    }

    if ((event.key === 'Enter' || event.key === 'Tab') && results.length) {
      event.preventDefault();
      selectResult(results[activeIndex] || results[0]);
    }
  }

  function runSearch(query) {
    var seq = ++searchSeq;
    var lang =
      ($activeTextarea && $activeTextarea.closest('[data-page-lang]').data('page-lang')) || '';

    $.ajax({
      url: '/admin/pages/search_by_h1',
      method: 'GET',
      dataType: 'json',
      data: { q: query, lang: lang }
    })
      .done(function (data) {
        if (seq !== searchSeq) return; // ответ на устаревший запрос

        results = data || [];
        activeIndex = 0;

        if (!results.length) {
          renderMessage('Ничего не найдено');
        } else {
          renderResults();
        }
      })
      .fail(function () {
        if (seq !== searchSeq) return;
        renderMessage('Ошибка поиска');
      });
  }

  function selectResult(page) {
    if (!page || !$activeTextarea) return;

    var el = $activeTextarea[0];
    var value = $activeTextarea.val();
    var before = value.substring(0, mentionStart);
    var after = value.substring(mentionEnd);
    var snippet =
      "<%= link_to('" + escapeForRubyString(page.uri) + "', anchor_text: '" +
      escapeForRubyString(page.h1 || '') + "') %>";

    var newValue = before + snippet + after;
    var newCaret = (before + snippet).length;

    $activeTextarea.val(newValue);
    el.setSelectionRange(newCaret, newCaret);
    $activeTextarea.trigger('focus');

    closeDropdown();
  }

  function escapeForRubyString(text) {
    return String(text).replace(/\\/g, '\\\\').replace(/'/g, "\\'");
  }

  function setActiveIndex(index) {
    if (!results.length) return;

    activeIndex = (index + results.length) % results.length;
    renderResults();
  }

  function renderMessage(text) {
    results = [];
    activeIndex = -1;
    $dropdown.html('<p class="page-mention-message">' + escapeHtml(text) + '</p>');
  }

  function renderResults() {
    var $list = $('<div class="page-mention-list"></div>');

    results.forEach(function (page, index) {
      var $item = $(
        '<div class="page-mention-item' + (index === activeIndex ? ' is-active' : '') + '">' +
          '<span class="page-mention-h1"></span>' +
          '<span class="page-mention-uri"></span>' +
        '</div>'
      );

      $item.find('.page-mention-h1').text(page.h1 || '(без h1)');
      $item.find('.page-mention-uri').text(page.uri);

      // mousedown, не click — иначе textarea теряет фокус/selection
      // раньше, чем мы успеваем прочитать mentionStart/mentionEnd
      $item.on('mousedown', function (event) {
        event.preventDefault();
        selectResult(page);
      });

      $list.append($item);
    });

    $dropdown.html($list);
  }

  function openDropdown($ta, mentionIdx) {
    $dropdown.appendTo('body').show();
    positionDropdown($ta, mentionIdx);
  }

  function closeDropdown() {
    $dropdown.hide().empty();
    $activeTextarea = null;
    mentionStart = null;
    mentionEnd = null;
    results = [];
    activeIndex = -1;
    clearTimeout(searchTimer);
  }

  function positionDropdown($ta, mentionIdx) {
    var coords = getCaretCoordinates($ta[0], mentionIdx);
    var offset = $ta.offset();

    $dropdown.css({
      top: offset.top + coords.top + coords.height - $ta[0].scrollTop,
      left: offset.left + coords.left - $ta[0].scrollLeft
    });
  }

  function buildDropdown() {
    return $('<div class="page-mention-dropdown"></div>').hide().appendTo('body');
  }

  function escapeHtml(text) {
    return $('<div></div>').text(text).html();
  }

  // Позиция каретки в textarea в пикселях — через "зеркальный" div с теми
  // же текстом/шрифтом/переносами (стандартный приём, т.к. у textarea
  // нет родного API для координат каретки).
  var MIRROR_PROPERTIES = [
    'boxSizing', 'width', 'height', 'overflowX', 'overflowY',
    'borderTopWidth', 'borderRightWidth', 'borderBottomWidth', 'borderLeftWidth',
    'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft',
    'fontStyle', 'fontVariant', 'fontWeight', 'fontStretch', 'fontSize', 'fontSizeAdjust',
    'lineHeight', 'fontFamily', 'textAlign', 'textTransform', 'textIndent',
    'textDecoration', 'letterSpacing', 'wordSpacing', 'tabSize', 'whiteSpace', 'wordWrap'
  ];

  function getCaretCoordinates(el, position) {
    var mirror = document.createElement('div');
    var span = document.createElement('span');
    var style = window.getComputedStyle(el);

    mirror.id = 'page-mention-mirror';
    document.body.appendChild(mirror);

    var mirrorStyle = mirror.style;
    mirrorStyle.position = 'absolute';
    mirrorStyle.visibility = 'hidden';
    mirrorStyle.whiteSpace = 'pre-wrap';
    mirrorStyle.wordWrap = 'break-word';
    mirrorStyle.top = '0';
    mirrorStyle.left = '-9999px';

    MIRROR_PROPERTIES.forEach(function (prop) {
      mirrorStyle[prop] = style[prop];
    });

    mirror.textContent = el.value.substring(0, position);
    span.textContent = el.value.substring(position) || '.';
    mirror.appendChild(span);

    var coords = {
      top: span.offsetTop,
      left: span.offsetLeft,
      height: parseInt(style.lineHeight, 10) || parseInt(style.fontSize, 10) * 1.2
    };

    document.body.removeChild(mirror);

    return coords;
  }

  function injectStyles() {
    if (document.getElementById('page-mention-styles')) return;

    var css = [
      '.page-mention-dropdown {',
      '  position: absolute;',
      '  z-index: 4000;',
      '  min-width: 260px;',
      '  max-width: 420px;',
      '  max-height: 260px;',
      '  overflow-y: auto;',
      '  background: #fff;',
      '  border: 1px solid #dbdbdb;',
      '  border-radius: 4px;',
      '  box-shadow: 0 0.5em 1em -0.125em rgba(10,10,10,.1), 0 0 0 1px rgba(10,10,10,.02);',
      '  font-size: 0.85rem;',
      '}',
      '.page-mention-message {',
      '  padding: 0.5em 0.75em;',
      '  color: #7a7a7a;',
      '}',
      '.page-mention-item {',
      '  padding: 0.4em 0.75em;',
      '  cursor: pointer;',
      '  display: flex;',
      '  justify-content: space-between;',
      '  align-items: baseline;',
      '  gap: 0.75em;',
      '}',
      '.page-mention-item.is-active, .page-mention-item:hover {',
      '  background: #f0f4f7;',
      '}',
      '.page-mention-h1 {',
      '  white-space: nowrap;',
      '  overflow: hidden;',
      '  text-overflow: ellipsis;',
      '}',
      '.page-mention-uri {',
      '  color: #939393;',
      '  font-size: 0.8em;',
      '  white-space: nowrap;',
      '}'
    ].join('\n');

    var styleTag = document.createElement('style');
    styleTag.id = 'page-mention-styles';
    styleTag.textContent = css;
    document.head.appendChild(styleTag);
  }
});
