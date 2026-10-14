# Отправка писем сайта. SMTP берётся из config/secret.yml (smtp:), см. _secret.yml.
# Без настроенного smtp письмо не уходит, а пишется в log/mail.log
# (в development ссылку для входа берём оттуда).
require 'mail'

module Mailer
  module_function

  def deliver(to:, subject:, body:, settings: App.settings)
    smtp = settings.respond_to?(:smtp) ? settings.smtp : nil
    from = (smtp && smtp['from']) || "no-reply@#{settings.domain}"

    if smtp.nil? || smtp['address'].to_s.empty?
      File.open(File.expand_path('../log/mail.log', __dir__), 'a') do |f|
        f.puts "[#{Time.now}] to=#{to} subject=#{subject}\n#{body}\n---"
      end
      return :logged
    end

    Mail.new do
      from    from
      to      to
      subject subject
      body    body
    end.tap do |m|
      m.delivery_method :smtp,
        address: smtp['address'], port: smtp['port'] || 587,
        user_name: smtp['user_name'], password: smtp['password'],
        authentication: :plain, enable_starttls_auto: true
    end.deliver!
    :sent
  end
end
