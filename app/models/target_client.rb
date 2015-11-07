class TargetClient < ActiveRecord::Base
  has_many :companies
  
  accepts_nested_attributes_for :companies
  
end
