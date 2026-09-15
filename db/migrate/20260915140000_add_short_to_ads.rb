class AddShortToAds < ActiveRecord::Migration[6.1]
  def change
    # "общее"/короткое имя (например "Egypt" вместо официального
    # name="Arab Republic of Egypt") — от него берём slug, когда оно
    # задано; nil означает "совпадает с name" (так было и в источнике).
    add_column :ads, :short, :string
  end
end
