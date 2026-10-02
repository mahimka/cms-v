require 'erb'
require 'json'
require 'yaml'

namespace :parser do
  desc "Собрать расширение tools/chrome-profile-parser под этот сайт: config.js и manifest.json из config/config.yml (domain, site_name, parser_local_port — по умолчанию 4567) и config/secret.yml (api_key_for_parser) (rake parser:extension)"
  task :extension do
    root = File.expand_path('..', __dir__)
    dir = File.join(root, 'tools', 'chrome-profile-parser')
    load_yaml = lambda do |name|
      path = File.join(root, 'config', name)
      raise "Не найден #{path}" unless File.exist?(path)

      YAML.safe_load(ERB.new(File.read(path)).result, aliases: true) || {}
    end

    config = load_yaml.call('config.yml')
    api_key = load_yaml.call('secret.yml')['api_key_for_parser'].to_s.strip
    raise "В config/secret.yml не задан api_key_for_parser" if api_key.empty?
    domain = config['domain'].to_s.strip.downcase
    raise "В config/config.yml не задан domain" if domain.empty?

    site_name = config['site_name'].to_s.strip
    site_name = domain if site_name.empty?
    port = (config['parser_local_port'] || 4567).to_i

    File.write(File.join(dir, 'config.js'), <<~JS)
      // Сгенерировано rake parser:extension из config/config.yml и config/secret.yml — не править и не коммитить (здесь секрет).
      const ENDPOINT_PROD = 'https://#{domain}/api/parse';
      const ENDPOINT_LOCAL = 'http://127.0.0.1:#{port}/api/parse';
      const API_KEY = '#{api_key}';
    JS

    manifest = JSON.parse(File.read(File.join(dir, 'manifest.template.json')))
    manifest['name'] = "#{site_name} Profile Parser"
    manifest['host_permissions'] = ["http://127.0.0.1:#{port}/*", "https://#{domain}/*"]
    File.write(File.join(dir, 'manifest.json'), JSON.pretty_generate(manifest) + "\n")

    puts "tools/chrome-profile-parser: #{manifest['name']} -> https://#{domain}, local http://127.0.0.1:#{port}"
    puts "Перезагрузи расширение в chrome://extensions (Load unpacked: #{dir})"
  end
end
