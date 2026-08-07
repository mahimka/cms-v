module Taggable
  extend ActiveSupport::Concern

  included do
    has_many :taggings, as: :taggable, dependent: :destroy
    has_many :tags, through: :taggings
  end

  class_methods do
    # Entity.tagged_with("Hotel")
    # Picture.tagged_with(["Town View", "sea view"])          # match: :any (по умолчанию)
    # Item.tagged_with(["wc", "shower"], match: :all)
    def tagged_with(names, match: :any)
      names = Array(names)
      return none if names.empty?

      scope = joins(:tags).where(tags: { name: names }).distinct

      match == :all ? scope.group("#{table_name}.id")
                           .having("COUNT(DISTINCT tags.id) = ?", names.uniq.size)
                    : scope
    end
  end

  def tagged_with?(tag_name_or_id)
    case tag_name_or_id
    when Integer
      taggings.exists?(tag_id: tag_name_or_id)
    when String
      tags.exists?(name: tag_name_or_id)
    else
      false
    end
  end

  def tagged_with_group?(group_name_or_id)
    case group_name_or_id
    when Integer
      tags.joins(:parent).exists?(parent: { id: group_name_or_id })
    when String
      tags.joins(:parent).exists?(parent: { name: group_name_or_id })
    end
  end

  def tags_of_group(group_name_or_id)
    case group_name_or_id
    when Integer
      tags.joins(:parent).where(parent: { id: group_name_or_id })
    when String
      tags.joins(:parent).where(parent: { name: group_name_or_id })
    end
  end

  def tags_of_group_localized(group_name_or_id, lang)
    tags_of_group(group_name_or_id).map { |tag| tag.translation(lang) }
  end

  def first_tag_of_group(group_name_or_id, lang = nil)
    tag = tags_of_group(group_name_or_id)&.first
    return nil unless tag

    lang ? tag.translation(lang) : tag.name
  end
end
