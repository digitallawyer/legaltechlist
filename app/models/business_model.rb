class BusinessModel < ActiveRecord::Base
  has_many :companies
  
  accepts_nested_attributes_for :companies
  
end
