namespace :data do
  desc "Remove all companies and their associations"
  task clear_companies: :environment do
    puts "Starting to remove companies and associations..."

    # Count before
    company_count = Company.count
    puts "Found #{company_count} companies to remove"

    # Remove in transaction to ensure consistency
    ActiveRecord::Base.transaction do
      # First remove all associations
      puts "Removing company associations..."
      CompanyBusinessModel.delete_all
      CompanyTargetClient.delete_all
      CompanyTag.delete_all

      # Then remove all companies
      puts "Removing companies..."
      Company.delete_all
    end

    # Verify
    remaining = Company.count
    puts "Complete! Removed #{company_count} companies. #{remaining} companies remaining."
  end
end
