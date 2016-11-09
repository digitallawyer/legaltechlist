class StaticPagesController < ApplicationController
  def home
  	@tags = Tag.limit(50)
  end

  def about
  end

  def statistics
  	if params[:founded_date]
  		@companies = Company.where('founded_date' => params[:founded_date]).all
  	else
  		@companies = Company.all
  	end
    @years_all = Company.order(founded_date: :asc).all
    @years = @years_all.uniq.pluck(:founded_date)
    #@years = ['2009', '2010', '2011', '2012', '2013', '2014', '2015', '2016']
  end

end
