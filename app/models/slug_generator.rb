# String#parameterize транслитерирует только латинские буквы с диакритикой
# (č, š, é и т.п. — через I18n.transliterate) — кириллица ему незнакома и
# вырезается целиком, так что entity.name на кириллице дал бы пустой slug.
# Прогоняем такие буквы через собственную карту и уже потом отдаём
# parameterize — тот сам разберётся с регистром, пробелами и остальной
# диакритикой.
module SlugGenerator
  CYRILLIC_TO_LATIN = {
    "а" => "a", "б" => "b", "в" => "v", "г" => "g", "д" => "d",
    "е" => "e", "ё" => "e", "ж" => "zh", "з" => "z", "и" => "i",
    "й" => "y", "к" => "k", "л" => "l", "м" => "m", "н" => "n",
    "о" => "o", "п" => "p", "р" => "r", "с" => "s", "т" => "t",
    "у" => "u", "ф" => "f", "х" => "h", "ц" => "ts", "ч" => "ch",
    "ш" => "sh", "щ" => "sch", "ъ" => "", "ы" => "y", "ь" => "",
    "э" => "e", "ю" => "yu", "я" => "ya"
  }.freeze

  def self.call(name)
    return "" if name.blank?

    transliterated = name.to_s.downcase.each_char.map { |char| CYRILLIC_TO_LATIN[char] || char }.join

    transliterated.parameterize
  end
end
