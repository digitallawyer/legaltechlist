class Tag < ActiveRecord::Base
  has_many :taggings, dependent: :destroy
  has_many :companies, through: :taggings
  
  def self.counts
    Tag.select("tags.id, tags.name, count(taggings.tag_id) as count"). joins(:taggings).group("taggings.tag_id, tags.id, tags.name")
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id name created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[taggings companies]
  end
end
