class StaticPagesController < ApplicationController
  def home
  	@tags = Tag.limit(50)
  end

  def about
  end

  def statistics
  	if params[:founded_date]
  		@companies = Company.where(visible: true, founded_date: params[:founded_date]).all
  	else
  		@companies = Company.where(visible: true)
  	end
  
  	# Filter companies from year 2000 onwards and only valid years
  	@companies = @companies.where('founded_date >= ? AND founded_date <= ? AND founded_date ~ ?', 
  								 '2000', 
  								 Time.current.year.to_s,
  								 '^\d{4}$')
  
  	# Get unique years from 2000 onwards, sorted, only valid years
  	@years = Company.where(visible: true)
  				 .where('founded_date >= ? AND founded_date <= ? AND founded_date ~ ?',
  							'2000',
  							Time.current.year.to_s,
  							'^\d{4}$')
  				 .distinct
  				 .pluck(:founded_date)
  				 .sort
  				 .reject(&:blank?)
  end

end
