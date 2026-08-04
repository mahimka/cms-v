class AddTranslationsToTagsAndLabels < ActiveRecord::Migration[6.1]
  def change
    add_column :tags, :translations, :text
    add_column :labels, :translations, :text
  end
end
