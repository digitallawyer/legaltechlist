class SubCategory < ActiveRecord::Base
  belongs_to :category
  has_many :companies

  def self.ransackable_attributes(auth_object = nil)
    %w[id name description category_id created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[category companies]
  end
end
