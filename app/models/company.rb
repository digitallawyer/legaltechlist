class Company < ActiveRecord::Base
  has_many :taggings
  has_many :tags, through: :taggings
  
	include PgSearch
	pg_search_scope :search,
                  	:against => :name,
                  	:using => {
                    	:tsearch => {:prefix => true}
                  }

	def self.text_search(query)
		if query.present?
			search(query)
		else
			all
		end
	end
  
  def self.tagged_with(name)
    Tag.find_by_name!(name).companies
  end
  
  def all_tags=(names)
    self.tags = names.split(",").map do |name|
      Tag.where(name: name.strip).first_or_create!
    end
  end
  
  def all_tags
    self.tags.map(&:name).join(", ")
  end

end
