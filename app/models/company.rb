class Company < ActiveRecord::Base
  has_many :taggings,  dependent: :destroy
  has_many :tags, through: :taggings
  
  #this should be has_one, but apparently there's a known bug
  belongs_to :category
  belongs_to :sub_category
  belongs_to :business_model
  belongs_to :target_client
  
  # I'm not 100% sure these are required.
  accepts_nested_attributes_for :category
  accepts_nested_attributes_for :sub_category
  accepts_nested_attributes_for :business_model
  accepts_nested_attributes_for :target_client
  
  # Validation for manual entry of data.
  validates :name, presence: true, length: {minimum: 3}
  validates :location, presence: true, length: {minimum: 1}
  validates :founded_date, presence: true, format: {with: /\d\d\d\d/, message: "must be a 4-digit year."}
  validates :category, presence: true
  # validates :business_model, presence: true
  # validates :target_client, presence: true
  validates :description, presence: true, length: {minimum: 5}

  #geocoding

  geocoded_by :location
  after_validation :geocode, :if => :location_changed?
  
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
      Tag.where(name: name.strip.downcase).first_or_create!
    end
  end
  
  def all_tags
    self.tags.map(&:name).join(", ")
  end

end
