# Вход посетителей по письму со ссылкой и через Google (AuthController).
# users - существующая таблица (пароль, admin); пароль теперь необязателен.
class AddLoginToUsers < ActiveRecord::Migration[6.1]
  def change
    add_column :users, :email_verified_at, :datetime   # склеивать аккаунты только по подтверждённому
    add_column :users, :avatar_url, :string
    add_column :users, :status, :string, null: false, default: 'active'   # active | blocked
    add_column :users, :last_login_at, :datetime

    create_table :identities do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false      # email | google | facebook
      t.string :uid,      null: false      # неизменный id у провайдера (sub у Google), не email
      t.string :email
      t.timestamps
    end
    add_index :identities, [:provider, :uid], unique: true

    create_table :login_tokens do |t|
      t.references :user, foreign_key: true   # пусто, пока человек не перешёл по ссылке
      t.string   :email,        null: false   # на этот адрес ушла ссылка
      t.string   :ip
      t.string   :token_digest, null: false
      t.datetime :expires_at,   null: false
      t.datetime :used_at
      t.timestamps
    end
    add_index :login_tokens, :token_digest, unique: true
  end
end
