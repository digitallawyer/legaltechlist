require 'twitter'

namespace :twitter do
	task :list_seed => :environment do

		twitter_client = Twitter::REST::Client.new do |config|
			config.consumer_key        = ENV["TWITTER_CONSUMER_KEY"]
			config.consumer_secret     = ENV["TWITTER_CONSUMER_SECRET"]
			config.access_token        = ENV["TWITTER_ACCESS_TOKEN"]
			config.access_token_secret = ENV["TWITTER_ACCESS_SECRET"]
		end

		#add users to the list
		Company.all.each do |c|
			if (c.twitter_name.present?)
				puts "Adding " +c.twitter_name.to_s
				begin
					twitter_client.add_list_member(Rails.application.config.twitter_user,Rails.application.config.twitter_list, c.twitter_name)
				rescue Twitter::Error::Forbidden
					puts "Invalid twitter id!"
				end
			end
		end
	end
end
