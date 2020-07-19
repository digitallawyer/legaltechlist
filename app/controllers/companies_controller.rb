class CompaniesController < ApplicationController
  before_action :set_company, only: [:show, :edit, :update, :destroy]

  # GET /companies
  # GET /companies.json

  # this search could easily be made much more complex and powerful
  # with ands and ors if necessary
  def index
    if params[:tag]
      @companies = Company.where('visible' => true).tagged_with(params[:tag]).page(params[:page]).per(10)
    elsif params[:category]
      @cat = Category.find(params[:category])
      @companies = Company.where('visible' => true).where(:category => params[:category]).page(params[:page]).per(10)
    elsif params[:business_model]
      @companies = Company.where('visible' => true).where(:business_model => params[:business_model]).page(params[:page]).per(10)
    elsif params[:target_client]
      @target = TargetClient.find(params[:target_client])
      @companies = Company.where('visible' => true).where(:target_client => params[:target_client]).page(params[:page]).per(10)
    else
      @companies = Company.where('visible' => true).text_search(params[:query]).page(params[:page]).per(10)
    end
  end

  def map
    @companies = Company.all
    @hash = Gmaps4rails.build_markers(@companies) do |company, marker|
      marker.lat company.latitude
      marker.lng company.longitude
      contentString = '<div id="content">'+
        '<h2 id="firstHeading" class="firstHeading">' +
        company.name +
        '</h2>'+
        '<div id="bodyContent">'+
        '<p>' +
        company.description +
        '</p>'+
        '(last updated June 22, 2009).</p>'+
        '<a href="/companies/' +
        company.id.to_s +
        '" class="btn btn-default">View Info</a>' +
        '</div>'+
        '</div>';
      marker.infowindow contentString
      marker.json({ title: company.name })
    end
  end

  def feed
    @companies = Company.all
    respond_to do |format|
      format.rss { render :layout => false }
    end
  end

  # GET /companies/1
  # GET /companies/1.json
  def show

  end

  # GET /companies/new
  def new
    @company = Company.new
  end

  # GET /companies/1/edit
  def edit

  end

  # POST /companies
  # POST /companies.json
  # Actual companies are created in the Admin module. This function will accept
  # the values from the new form, verify them, and then e-mail them to the
  # administrator to be added later.
  def create
    @company = Company.new(company_params)
    @company.visible = false

    respond_to do |format|
      if verify_recaptcha(model: @company) && @company.save
        # set company to invisible

        SuggestionMailer.newcompany_email(@company).deliver_now

        format.html { redirect_to "/companies", notice: t('controllers.company.created_success') }
        format.json { render :show, status: :created, location: @company }
      else
        format.html { render :new }
        format.json { render json: @company.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /companies/1
  # PATCH/PUT /companies/1.json
  # Actual companies are edited in the Admin module. This function will accept the
  # values from the edit form, verify them, and then e-mail them to the
  # administrator to be added later.
  def update
    @company = Company.new(company_params)

    respond_to do |format|
      if verify_recaptcha(model: @company) && @company.valid?

        SuggestionMailer.editcompany_email(@company).deliver_now

        #redirect to the company we're editing, not the company changes we're submitting!
        format.html { redirect_to Company.find(params[:id]), notice: t('controllers.company.updated_success') }
        format.json { render :show, status: :ok, location: @company }
      else
        flash.now[:notice] = "Failed, please try again"
        format.html { render :edit }
        format.json { render json: @company.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /companies/1
  # DELETE /companies/1.json
  def destroy
    @company.destroy
    respond_to do |format|
      format.html { redirect_to companies_url, notice: t('controllers.company.destroyed_success') }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_company
      @company = Company.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def company_params
      params.require(:company).permit(:name, :location, :founded_date, :category, :sub_category,
                                      :business_model, :target_client, :description, :main_url,
                                      :twitter_url, :angellist_url, :crunchbase_url, :employee_count,
                                      :all_tags, :category_id, :sub_category_id, :target_client_id,
                                      :business_model_id, :visible, :contact_name, :contact_email,
                                      :codex_presenter, :codex_presentation_date)
    end
end
