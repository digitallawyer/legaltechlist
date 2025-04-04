namespace :data do
  desc "Remove all companies and their associations"
  task clear_companies: :environment do
    puts "Starting to remove companies and associations..."

    # Count before
    company_count = Company.count
    puts "Found #{company_count} companies to remove"

    # Remove in transaction to ensure consistency
    ActiveRecord::Base.transaction do
      # Disable geocoding and twitter callbacks temporarily
      Company.class_eval do
        skip_callback :update, :before, :publish_tweet
        skip_callback :update, :before, :publish_to_list
        skip_callback :validation, :after, :geocode
      end

      # Delete all companies - this will automatically delete taggings due to dependent: :destroy
      puts "Removing companies and their associations..."
      Company.delete_all

      # Re-enable callbacks
      Company.class_eval do
        set_callback :update, :before, :publish_tweet
        set_callback :update, :before, :publish_to_list
        set_callback :validation, :after, :geocode
      end
    end

    # Verify
    remaining = Company.count
    puts "Complete! Removed #{company_count} companies. #{remaining} companies remaining."
  end
end
