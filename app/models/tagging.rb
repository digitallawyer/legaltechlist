class Tagging < ActiveRecord::Base
  belongs_to :company
  belongs_to :tag

  def self.ransackable_attributes(auth_object = nil)
    %w[id tag_id company_id created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    ["tag", "company"]
  end
end
