class ::Admin::PieterController < ApplicationController
  before_action :authenticate_admin_user!
  def index
    # if params[:query].present? && !params[:query].blank?
    #   @data = Company.where("name ILIKE ?", "%#{params[:query]}%").to_a
    #   @saved_text = params[:query]
    # else
    #   @data = nil
    #   @saved_text = nil
    # end
    if params[:exact_match] == 'on'
      # ----------------------------------------------
      if params[:query].present? && !params[:query].blank?
        @data = Company.where("name LIKE ?", "#{params[:query]}").to_a
        @saved_text = params[:query]
      else
        @data = nil
        @saved_text = nil
      end
      # ----------------------------------------------
    else
      # ----------------------------------------------
      if params[:query].present? && !params[:query].blank?
        @data = Company.where("name ILIKE ?", "%#{params[:query]}%").to_a
        @saved_text = params[:query]
      else
        @data = nil
        @saved_text = nil
      end
      # ----------------------------------------------
    end
    render "index", locals: { data: @data }
  end
end
