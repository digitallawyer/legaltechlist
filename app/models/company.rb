class Company < ActiveRecord::Base
  before_update :publish_tweet, :if => :visible_changed?
  before_update :publish_to_list, :if => :visible_changed?

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

  #convenience method to parse the twitter username from the twitter url, 
  #but also handle the case where the user entered their twitter name instead.
  def twitter_name
    #parse the twitter url to get the twitter_name
    if self.twitter_url.present?
      if self.twitter_url.include? "twitter.com/"
        if self.twitter_url.split('twitter.com/').last.include? "@"
          self.twitter_url.split('twitter.com/').last.split('@').last
        else
          self.twitter_url.split('twitter.com/').last
        end
      else 
        if self.twitter_url.include? "@"
          self.twitter_url.split('@').last
        else
          self.twitter_url
        end
      end
    else
      nil
    end
  end

  def publish_tweet
    if (self.visible? && Rails.configuration.twitter_publish)
      #initialize twitter_client to access their API
      twitter_client = Twitter::REST::Client.new do |config|
          config.consumer_key        = ENV["TWITTER_CONSUMER_KEY"]
          config.consumer_secret     = ENV["TWITTER_CONSUMER_SECRET"]
          config.access_token        = ENV["TWITTER_ACCESS_TOKEN"]
          config.access_token_secret = ENV["TWITTER_ACCESS_SECRET"]
      end

      #publish a tweet
      twitter_client.update(I18n.t("twitter.publish") + " @" + self.twitter_name + " " + self.main_url)
    end
  end
  
  def publish_to_list
    if (self.visible? && Rails.configuration.twitter_publish)
      #initialize twitter_client to access their API
      twitter_client = Twitter::REST::Client.new do |config|
          config.consumer_key        = ENV["TWITTER_CONSUMER_KEY"]
          config.consumer_secret     = ENV["TWITTER_CONSUMER_SECRET"]
          config.access_token        = ENV["TWITTER_ACCESS_TOKEN"]
          config.access_token_secret = ENV["TWITTER_ACCESS_SECRET"]
      end

      #add users to the list
      if (self.twitter_name.present?)
        begin
          twitter_client.add_list_member(Rails.configuration.twitter_user,Rails.configuration.twitter_list, self.twitter_name)
        rescue Twitter::Error::Forbidden
          logger.errror "#{self.twitter_name} is not a valid twitter id"
        end
      end
    end
  end
end
