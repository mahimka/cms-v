class User < ActiveRecord::Base
  # Пароль необязателен: можно входить по письму со ссылкой / через Google.
  # Если пароль задан (форма /register), он должен быть не короче 8 символов.
  has_secure_password validations: false

  has_many :pictures, dependent: :nullify
  has_many :identities, dependent: :destroy
  has_many :login_tokens, dependent: :nullify

  before_validation { self.email = email.to_s.strip.downcase.presence }

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :password, presence: true, on: :register   # форма /register требует пароль

  def self.ransackable_attributes(auth_object = nil)
    ["id", "name", "email", "created_at", "updated_at"]
  end

  def blocked? = status == 'blocked'

  # Единая точка входа для всех способов (письмо, Google...). Возвращает User.
  #  1. известная пара provider+uid -> её владелец;
  #  2. иначе, если email ПОДТВЕРЖДЁН провайдером и такой User есть -> привязываем
  #     способ к нему (по неподтверждённому email склеивать нельзя - угон аккаунта);
  #  3. иначе создаём нового. Без подтверждённого email создать нельзя
  #     (email в users обязателен).
  def self.sign_in_with(provider:, uid:, email: nil, email_verified: false, name: nil, avatar_url: nil)
    email = email.to_s.strip.downcase.presence
    return nil unless email && email_verified
    transaction do
      identity = Identity.find_by(provider: provider, uid: uid.to_s)
      user   = identity&.user
      user ||= find_by(email: email)
      user ||= new(email: email, name: name.presence || email.split('@').first, avatar_url: avatar_url).tap do |u|
        u.save!
      end
      user.identities.create!(provider: provider, uid: uid.to_s, email: email) unless identity
      user.email_verified_at ||= Time.now if user.email == email
      user.avatar_url ||= avatar_url
      user.last_login_at = Time.now
      user.save!
      user
    end
  end
end
