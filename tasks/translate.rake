# Бэкфилл переводов через Gemini — ничего не перезаписывает вручную
# заполненное, только доливает отсутствующее.
#
# rake translate:pages      — создаёт недостающие языковые версии Page
# rake translate:taggables  — доливает translations[lang] у Tag/Label
# rake translate:all        — оба сразу
namespace :translate do
  desc "Создать недостающие языковые версии Page через Gemini (существующие переводы не трогает)"
  task :pages do
    translator = PageTranslator.new(
      gemini_client: GeminiClient.new(api_key: App.settings.gemini_api_key),
      languages: App.settings.languages.keys
    )

    Page.masters.find_each do |master|
      results = translator.create_missing_translations!(master)
      next if results.empty?

      puts master.uri
      results.each do |r|
        puts "  #{r.lang}: #{r.success? ? 'OK' : "FAIL (#{r.error})"}"
      end
    end
  end

  desc "Дозаполнить translations[lang] у Tag/Label через Gemini (существующие переводы не трогает)"
  task :taggables do
    backfiller = TaggableTranslationsBackfiller.new(
      gemini_client: GeminiClient.new(api_key: App.settings.gemini_api_key),
      languages: App.settings.languages.keys,
      home_language: App.settings.home_language
    )

    [Tag, Label].each do |klass|
      puts klass.name
      report = backfiller.backfill!(klass)

      report.each do |lang, records|
        ok = records.count { |_, success| success }
        failed = records.reject { |_, success| success }.keys

        puts "  #{lang}: #{ok} переведено#{failed.any? ? ", не удалось: #{failed.join(', ')}" : ''}"
      end
    end
  end

  desc "translate:pages + translate:taggables"
  task all: [:pages, :taggables]
end
