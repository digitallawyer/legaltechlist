load 'import_csv_to_company.rb'

ActiveAdmin.register Company do

# See permitted parameters documentation:
# https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters

  scope("In Moderation") { |scope| scope.where(visible: false) }

  permit_params :name, :location, :founded_date, :category, :business_model, :target_client, :description, :main_url, :twitter_url, :angellist_url, :crunchbase_url, :all_tags, :category_id, :business_model_id, :target_client_id, :latitute, :longitude, :contact_name, :contact_email, :visible, :codex_presenter, :codex_presentation_date

######

  action_item :only => :index do
    link_to 'Upload CSV', :action => 'upload_csv'
  end
  
  action_item :only => :index do
    link_to 'Download CSV', :action => 'export_csv'
  end
  
  collection_action :upload_csv do
    render "admin/csv/upload_csv"
  end
  
  collection_action :import_csv, :method => :post do
    ImportCSVtoCompany.import(params[:dump][:file])
    redirect_to :action => :index, :notice => "CSV imported successfully."
  end
  
  collection_action :export_csv, :method => :get do
    encoding = Encoding::UTF_8.name
    csv = CSV.generate( encoding: encoding) do |csv|
      ImportCSVtoCompany.export(csv)
    end

    send_data csv, 
      type: "text/csv; charset=#{encoding}; header=present",
      disposition: "attachment; filename=companies.csv"
  end

  ###### 

  index do
  	column :name
  	column :category
    column :sub_category
    column :description
  	column :main_url
    column :all_tags
    column :visible
    actions
  end

  form do |f|
    f.inputs do
      f.input :contact_name
      f.input :contact_email
      f.input :name,          :required => true
      f.input :location,      :required => true
      f.input :founded_date,  :required => true
      f.input :visible,       as: :boolean
      f.input :category,      as: :select, collection: Category.all.order(:name), :required => true, :include_blank => false
      f.input :sub_category,      as: :select, collection: SubCategory.all.order(:name), :required => true, :include_blank => false
      f.input :target_client, as: :select, collection: TargetClient.all, :required => true, :include_blank => false
      f.input :business_model,as: :select, collection: BusinessModel.all, :required => true, :include_blank => false
      f.input :description,   :required => true
      f.input :main_url      
      f.input :twitter_url
      f.input :angellist_url
      f.input :crunchbase_url
      f.input :all_tags  
      f.input :codex_presenter
      f.input :codex_presentation_date    
    end
    f.actions do
      f.action :submit
      f.action :cancel
    end
  end
end
