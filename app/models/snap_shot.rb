class SnapShot < ActiveRecord::Base

  belongs_to :profile

  # Современный синтаксис (Rails 7.1+):
  # serialize :labels, coder: JSON

  # serialize :scores, JSON
  # serialize :badges, JSON
  serialize :labels, JSON
  # serialize :links, JSON
  # serialize :contacts, JSON
  # serialize :mixed, JSON

end
