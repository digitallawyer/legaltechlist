class Category < ActiveRecord::Base
  has_many :companies
  has_many :sub_categories

  accepts_nested_attributes_for :companies
  
end
