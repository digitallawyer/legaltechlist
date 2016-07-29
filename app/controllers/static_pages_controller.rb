class StaticPagesController < ApplicationController
  def home
  	@tags = Tag.limit(60)
  end

  def about
  end

end
