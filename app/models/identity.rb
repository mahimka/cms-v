# Один способ входа участника. uid - неизменный id у провайдера (sub у Google),
# не email. Для почтовой ссылки provider='email', uid=email.
class Identity < ActiveRecord::Base
  PROVIDERS = %w[email google facebook].freeze

  belongs_to :user

  validates :provider, inclusion: { in: PROVIDERS }
  validates :uid, presence: true, uniqueness: { scope: :provider }
end
