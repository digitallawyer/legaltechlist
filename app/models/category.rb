class Category < ApplicationRecord
  has_many :sub_categories
  has_many :companies, through: :sub_categories
  
  def self.ransackable_attributes(auth_object = nil)
    %w[id name created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[sub_categories companies]
  end
end
