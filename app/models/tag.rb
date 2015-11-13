class Tag < ActiveRecord::Base
  has_many :taggings
  has_many :companies, through: :taggings
  
  def self.counts
    Tag.select("tags.id, tags.name, count(taggings.tag_id) as count"). joins(:taggings).group("taggings.tag_id, tags.id, tags.name")
  end
end
