require 'securerandom'
require 'fileutils'

# Загрузка JSON с уточнениями по entity: шаг 1 — проверка (dry-run), шаг 2 — применение.
# Формат файла и правила — в комментарии к lib/entity_importer.rb.
class EntityImportsController < App

  IMPORT_DIR      = File.expand_path('../../tmp/imports', __dir__)
  MAX_UPLOAD_SIZE = 5 * 1024 * 1024
  TOKEN_FORMAT    = /\A[0-9a-f]{32}\z/

  namespace '/admin/import' do

    get '/entities' do
      @report = nil
      erb :"/import/entities", layout: :"/layout/wide", views: settings.views_admin
    end

    # шаг 1: файл -> dry-run, файл остаётся в tmp/imports до подтверждения
    post '/entities/check' do
      upload = params[:import_file]
      unless upload.is_a?(Hash) && upload[:tempfile]
        flash[:error_title] = 'Файл не выбран'
        redirect '/admin/import/entities'
      end

      json = upload[:tempfile].read(MAX_UPLOAD_SIZE + 1).to_s
      if json.bytesize > MAX_UPLOAD_SIZE
        flash[:error_title] = "Файл больше #{MAX_UPLOAD_SIZE / 1024 / 1024} МБ"
        redirect '/admin/import/entities'
      end

      json = json.dup.force_encoding('UTF-8').delete_prefix("\uFEFF")
      @report   = EntityImporter.new(json).call(apply: false)
      @filename = upload[:filename]
      @token    = nil

      if @report.ok? && @report.records.any? { |r| r[:action] != :error && r[:action] != :unchanged }
        cleanup_old_imports
        @token = SecureRandom.hex(16)
        FileUtils.mkdir_p(IMPORT_DIR)
        File.write(import_path(@token), json)
      end

      erb :"/import/entities", layout: :"/layout/wide", views: settings.views_admin
    end

    # шаг 2: тот же файл применяется в одной транзакции (записи с ошибками пропускаются)
    post '/entities/apply' do
      token = params[:token].to_s
      path  = TOKEN_FORMAT.match?(token) ? import_path(token) : nil
      unless path && File.exist?(path)
        flash[:error_title] = 'Файл проверки не найден или устарел — загрузите его заново'
        redirect '/admin/import/entities'
      end

      @report = EntityImporter.new(File.read(path)).call(apply: true)
      File.delete(path)
      @filename = params[:filename]
      @token    = nil

      erb :"/import/entities", layout: :"/layout/wide", views: settings.views_admin
    end

  end

  helpers do
    def import_path(token)
      File.join(IMPORT_DIR, "#{token}.json")
    end

    def cleanup_old_imports
      Dir.glob(File.join(IMPORT_DIR, '*.json')).each do |f|
        File.delete(f) if File.mtime(f) < Time.now - 24 * 3600
      end
    end
  end

end
