/*
 * Кнопка "translate to all" на странице редактирования картинки —
 * переводит alt на все языки через Gemini (см.
 * PicturesController#translate_missing_alt_languages) и подставляет
 * результат в поля picture[translations][<lang>], не трогая уже
 * заполненные вручную (это делает сам сервер).
 */
$(document).on("click", "[data-picture-translate-alt]", function (event) {
  event.preventDefault();

  var $button = $(this);
  var pictureId = $button.data("picture-id");

  $button.prop("disabled", true).addClass("is-loading");

  $.ajax({
    url: "/admin/pictures/" + encodeURIComponent(pictureId) + "/translate_alt",
    method: "POST",
    dataType: "json"
  })
    .done(function (result) {
      $.each(result.translations, function (lang, value) {
        $('input[name="picture[translations][' + lang + ']"]').val(value);
      });

      var failedLangs = Object.keys(result.errors || {});
      $button.prop("disabled", false).removeClass("is-loading");

      if (failedLangs.length) {
        $button.addClass("is-warning").text("⚠ " + failedLangs.length + " failed");
        console.error("Ошибки перевода:", result.errors);
      } else {
        $button.addClass("is-success").text("✓ translated");
      }
    })
    .fail(function (xhr) {
      var message = (xhr.responseJSON && xhr.responseJSON.error) || xhr.statusText;
      alert("Не удалось перевести: " + message);
      $button.prop("disabled", false).removeClass("is-loading");
    });
});
