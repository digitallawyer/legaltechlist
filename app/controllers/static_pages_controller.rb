class StaticPagesController < ApplicationController
  def home
  	@tags = Tag.limit(50)
  end

  def about
  end

end
