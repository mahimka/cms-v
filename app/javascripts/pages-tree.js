$(function () {
  const $workspace = $(".pages-workspace");
  const $editor = $("#page-editor");
  const $tree = $("#pages-tree");

  if (!$workspace.length || !$editor.length) {
    return;
  }


  $(document).on(
    "submit",
    "[data-page-edit-form]",
    function (event) {
      event.preventDefault();

      const $form = $(this);
      const $submit = $form.find('[type="submit"]');
      const pageId = $form
        .attr("action")
        .split("/")
        .filter(Boolean)
        .pop();

      $submit
        .prop("disabled", true)
        .addClass("is-loading");

      $.ajax({
        url: $form.attr("action"),
        method: "POST",
        data: $form.serialize(),
        dataType: "html",
        headers: {
          "X-Requested-With": "XMLHttpRequest"
        }
      })
        .done(function (html, textStatus, xhr) {
          const savedPageId =
            xhr.getResponseHeader("X-Page-Id") || pageId;

          reloadTreeAndOpenPage(savedPageId);
        })
        .fail(function (xhr) {
          if (xhr.status === 422 && xhr.responseText) {
            // Показываем форму с ошибками валидации.
            $editor.html(xhr.responseText);
            return;
          }

          console.error(
            "Ошибка сохранения страницы:",
            xhr.status,
            xhr.responseText
          );

          showEditorError("Не удалось сохранить страницу.");
        })
        .always(function () {
          $submit
            .prop("disabled", false)
            .removeClass("is-loading");
        });
    }
  );


  /*
   * Раскрытие и сворачивание веток дерева
   */
  $(document).on("click", "[data-tree-toggle]", function (event) {
    event.preventDefault();

    const $button = $(this);
    const $node = $button.closest(".page-tree-node");
    const $children = $node.children("[data-tree-children]");

    if (!$children.length) {
      return;
    }

    const isExpanded =
      $button.attr("aria-expanded") === "true";

    if (isExpanded) {
      collapseNode($button, $children);
      return;
    }

    if ($children.data("loaded")) {
      expandNode($button, $children);
      return;
    }

    loadChildren($node, $button, $children);
  });

  /*
   * Открытие формы существующей страницы
   */
  $(document).on("click", "[data-page-open]", function (event) {
    event.preventDefault();

    const $link = $(this);
    const $node = $link.closest(".page-tree-node");
    const pageId = $node.data("page-id");

    if (!pageId) {
      showEditorError("Не удалось определить ID страницы.");
      return;
    }

    activateTreeLink($link);

    openPageById(pageId);
  });


  $(document).on("click", "[data-page-edit]", function (event) {
    event.preventDefault();

    const pageId = $(this).data("page-id");

    if (!pageId) {
      showEditorError("Не удалось определить ID страницы.");
      return;
    }

    showEditorLoading("Загрузка формы редактирования…");

    $.ajax({
      url: `/admin/pages/${encodeURIComponent(pageId)}/edit/form`,
      method: "GET",
      dataType: "html"
    })
      .done(function (html) {
        $editor.html(html);
      })
      .fail(function (xhr) {
        console.error(
          "Ошибка загрузки формы редактирования:",
          xhr.status,
          xhr.responseText
        );

        showEditorError(
          "Не удалось загрузить форму редактирования."
        );
      });
  });

  

  /*
   * Обычная новая master-страница
   */
  $(document).on("click", "[data-page-new]", function (event) {
    event.preventDefault();

    loadNewPageForm("/admin/pages/new/form");
  });

  /*
   * Создание подстраницы
   */
  $(document).on("click", "[data-page-sub]", function (event) {
    event.preventDefault();

    const sourcePageId = $(this).data("source-page-id");

    if (!sourcePageId) {
      showEditorError("Не удалось определить исходную страницу.");
      return;
    }

    loadNewPageForm(
      `/admin/pages/new/form?source_page_id=${encodeURIComponent(sourcePageId)}&sub=true`
    );
  });

  /*
   * Копирование страницы
   */
  $(document).on("click", "[data-page-copy]", function (event) {
    event.preventDefault();

    const sourcePageId = $(this).data("source-page-id");

    if (!sourcePageId) {
      showEditorError("Не удалось определить исходную страницу.");
      return;
    }

    loadNewPageForm(
      `/admin/pages/new/form?source_page_id=${encodeURIComponent(sourcePageId)}&copy=true`
    );
  });

  /*
   * Открытие существующего перевода страницы
   */
  $(document).on("click", "[data-page-lang-open]", function (event) {
    event.preventDefault();

    const targetPageId = $(this).data("target-page-id");

    if (!targetPageId) {
      showEditorError("Не удалось определить перевод страницы.");
      return;
    }

    const $targetNode = $tree.find(
      `.page-tree-node[data-page-id="${targetPageId}"]`
    );

    if ($targetNode.length) {
      activateTreeLink(
        $targetNode
          .children(".page-tree-row")
          .find("[data-page-open]")
      );
    } else {
      deactivateSelection();
    }

    openPageById(targetPageId);
  });

  /*
   * Создание нового перевода страницы
   */
  $(document).on("click", "[data-page-lang-create]", function (event) {
    event.preventDefault();

    const sourcePageId = $(this).data("source-page-id");
    const lang = $(this).data("lang");

    if (!sourcePageId || !lang) {
      showEditorError("Не удалось определить исходную страницу или язык.");
      return;
    }

    loadNewPageForm(
      `/admin/pages/new/form?source_page_id=${encodeURIComponent(sourcePageId)}&lang=${encodeURIComponent(lang)}`
    );
  });

  /*
   * Отмена создания или копирования
   */
  $(document).on(
    "click",
    "[data-page-form-cancel]",
    function (event) {
      event.preventDefault();

      showEditorPlaceholder();
    }
  );

  /*
   * AJAX-сохранение новой страницы
   */
  $(document).on(
    "submit",
    "[data-page-create-form]",
    function (event) {
      event.preventDefault();

      const $form = $(this);
      const $submit = $form.find('[type="submit"]');

      $submit.prop("disabled", true);

      $.ajax({
        url: $form.attr("action"),
        method: ($form.attr("method") || "POST").toUpperCase(),
        data: $form.serialize(),
        dataType: "html",
        headers: {
          "X-Requested-With": "XMLHttpRequest"
        }
      })
        .done(function (html, textStatus, xhr) {
          const pageId =
            xhr.getResponseHeader("X-Page-Id");

          if (pageId) {
            reloadTreeAndOpenPage(pageId);
            return;
          }

          // Сервер вернул форму с ошибками валидации.
          $editor.html(html);
        })
        .fail(function (xhr) {
          if (xhr.responseText) {
            $editor.html(xhr.responseText);
          } else {
            showEditorError(
              "Не удалось создать страницу."
            );
          }
        })
        .always(function () {
          $submit.prop("disabled", false);
        });
    }
  );

  /*
   * Загрузка непосредственных детей узла
   */
  function loadChildren($node, $button, $children) {
    const pageId = $node.data("page-id");

    if (!pageId) {
      return;
    }

    $button
      .prop("disabled", true)
      .addClass("is-loading");

    $.ajax({
      url: `/admin/pages/${encodeURIComponent(pageId)}/children`,
      method: "GET",
      dataType: "html"
    })
      .done(function (html) {
        const content = $.trim(html);

        if (!content) {
          $button.replaceWith(
            '<span class="page-tree-toggle-placeholder"></span>'
          );

          $children.remove();
          return;
        }

        $children
          .html(html)
          .data("loaded", true);

        expandNode($button, $children);
      })
      .fail(function (xhr) {
        console.error(
          "Ошибка загрузки дочерних страниц:",
          xhr.status,
          xhr.responseText
        );

        showEditorError(
          "Не удалось загрузить дочерние страницы."
        );
      })
      .always(function () {
        $button
          .prop("disabled", false)
          .removeClass("is-loading");
      });
  }

  /*
   * Снимает выделение с активной страницы и подсветку её ветки.
   */
  function deactivateSelection() {
    const $prevLink = $(".page-tree-link.is-selected");

    $prevLink.removeClass("is-selected has-text-weight-bold");
    unmarkActiveSlug($prevLink);

    $(".page-tree-children.is-active-branch").each(function () {
      const $ul = $(this);
      $ul.removeClass("is-active-branch");

      const $ownToggle = $ul
        .closest(".page-tree-node")
        .children(".page-tree-row")
        .find("[data-tree-toggle]");

      if ($ownToggle.attr("aria-expanded") !== "true") {
        $ul.removeClass("has-background-grey-lighter");
      }
    });
  }

  /*
   * Отмечает страницу активной: жирный текст, tag is-info на слаге
   * и фоновая подсветка has-background-grey-lighter на всей ветке
   * предков (активной ветке дерева).
   */
  function activateTreeLink($link) {
    deactivateSelection();

    $link.addClass("is-selected has-text-weight-bold");
    markActiveSlug($link);

    $link
      .closest(".page-tree-node")
      .parents("[data-tree-children]")
      .addClass("is-active-branch has-background-grey-lighter");
  }

  /*
   * Выделяет слаг активной страницы бейджем tag is-info.
   */
  function markActiveSlug($link) {
    $link
      .find(".page-tree-slug-text")
      .addClass("tag is-info");
  }

  /*
   * Снимает бейдж tag is-info со слага — кроме языковых корней,
   * у которых это постоянное обозначение (см. is-lang-root).
   */
  function unmarkActiveSlug($link) {
    const $slug = $link.find(".page-tree-slug-text");

    if (!$slug.hasClass("is-lang-root")) {
      $slug.removeClass("tag is-info");
    }
  }

  /*
   * Раскрытие ветки
   */
  function expandNode($button, $children) {
    $children
      .prop("hidden", false)
      .show()
      .addClass("has-background-grey-lighter");

    $button
      .attr("aria-expanded", "true")
      .attr(
        "aria-label",
        "Свернуть дочерние страницы"
      )
      .find("span")
      .text("−");
  }

  /*
   * Сворачивание ветки
   */
  function collapseNode($button, $children) {
    $children
      .prop("hidden", true)
      .hide()
      .removeClass("has-background-grey-lighter");

    $button
      .attr("aria-expanded", "false")
      .attr(
        "aria-label",
        "Раскрыть дочерние страницы"
      )
      .find("span")
      .text("+");
  }

  /*
   * Загрузка формы создания или копирования
   */
  function loadNewPageForm(url) {
    showEditorLoading("Загрузка формы…");

    $.ajax({
      url: url,
      method: "GET",
      dataType: "html"
    })
      .done(function (html) {
        $editor.html(html);
      })
      .fail(function (xhr) {
        console.error(
          "Ошибка загрузки формы:",
          xhr.status,
          xhr.responseText
        );

        showEditorError(
          "Не удалось загрузить форму страницы."
        );
      });
  }

  /*
   * Открытие существующей страницы по ID
   */
  function openPageById(pageId) {
    showEditorLoading("Загрузка страницы…");

    $.ajax({
      url: `/admin/pages/${encodeURIComponent(pageId)}/form`,
      method: "GET",
      dataType: "html"
    })
      .done(function (html) {
        $editor.html(html);
      })
      .fail(function (xhr) {
        console.error(
          "Ошибка загрузки страницы:",
          xhr.status,
          xhr.responseText
        );

        showEditorError(
          "Не удалось загрузить форму страницы."
        );
      });
  }

  /*
   * Обновление дерева после создания страницы
   */
  function reloadTreeAndOpenPage(pageId) {
    if (!$tree.length) {
      openPageById(pageId);
      return;
    }

    $tree.load(
      "/admin/pages/tree/nodes",
      function (response, status, xhr) {
        if (status !== "success") {
          console.error(
            "Ошибка обновления дерева:",
            xhr.status,
            xhr.responseText
          );

          showEditorError(
            "Страница создана, но дерево не удалось обновить."
          );

          return;
        }

        const $targetNode = $tree.find(
          `.page-tree-node[data-page-id="${pageId}"]`
        );

        if ($targetNode.length) {
          activateTreeLink(
            $targetNode
              .children(".page-tree-row")
              .find("[data-page-open]")
          );
        }

        openPageById(pageId);
      }
    );
  }

  /*
   * Индикатор загрузки правой панели
   */
  function showEditorLoading(message) {
    $editor.html(`
      <div class="page-editor-placeholder">
        <p>${escapeHtml(message)}</p>
      </div>
    `);
  }

  /*
   * Начальное состояние правой панели
   */
  function showEditorPlaceholder() {
    $editor.html(`
      <div class="page-editor-placeholder">
        <h2>Выберите страницу</h2>
        <p>Нажмите на страницу в дереве.</p>
      </div>
    `);
  }

  /*
   * Вывод ошибки
   */
  function showEditorError(message) {
    $editor.html(`
      <div class="page-editor-placeholder page-editor-error">
        <p>${escapeHtml(message)}</p>
      </div>
    `);
  }

  /*
   * Экранирование текста перед вставкой в HTML
   */
  function escapeHtml(value) {
    return $("<div>")
      .text(value)
      .html();
  }
});