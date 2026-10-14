# Одноразовая ссылка для входа по email. В БД только sha256 токена.
# User создаётся не при запросе ссылки, а при её использовании
# (иначе открытая форма наполняет базу мусорными аккаунтами).
class LoginToken < ActiveRecord::Base
  TTL          = 15 * 60
  MAX_PER_MAIL = 3     # запросов на один адрес за TTL
  MAX_PER_IP   = 10    # запросов с одного IP за час

  belongs_to :user, optional: true

  # Можно ли сейчас выслать ссылку (простой лимит против спама через форму).
  def self.allowed?(email:, ip:)
    where(email: email).where('created_at > ?', Time.now - TTL).count < MAX_PER_MAIL &&
      (ip.nil? || where(ip: ip).where('created_at > ?', Time.now - 3600).count < MAX_PER_IP)
  end

  # Возвращает сырой токен для письма.
  def self.issue(email:, ip: nil)
    raw = SecureRandom.urlsafe_base64(32)
    create!(email: email, ip: ip, token_digest: digest(raw), expires_at: Time.now + TTL)
    raw
  end

  # Гасит токен и возвращает его email, либо nil (нет/просрочен/уже использован).
  def self.consume(raw)
    t = find_by(token_digest: digest(raw.to_s), used_at: nil)
    return unless t && t.expires_at > Time.now
    return unless where(id: t.id, used_at: nil).update_all(used_at: Time.now) == 1
    t.email
  end

  def self.digest(raw) = Digest::SHA256.hexdigest(raw)
end
