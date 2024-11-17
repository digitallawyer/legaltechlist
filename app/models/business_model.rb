class BusinessModel < ActiveRecord::Base
  belongs_to :company
  
  accepts_nested_attributes_for :companies
  
  def self.ransackable_attributes(auth_object = nil)
    %w[id name description created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[companies]
  end
end
