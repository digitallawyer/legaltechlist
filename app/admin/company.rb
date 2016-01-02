load 'import_csv_to_company.rb'

ActiveAdmin.register Company do

# See permitted parameters documentation:
# https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters

permit_params :name, :location, :founded_date, :category, :business_model, :target_client, :description, :main_url, 
  :twitter_url, :angellist_url, :crunchbase_url, :employee_count, :all_tags, 
  :category_id, :business_model_id, :target_client_id

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
    encoding = Encoding::ISO_8859_1.name
    csv = CSV.generate( encoding: encoding) do |csv|
      
      ImportCSVtoCompany.export(csv)
    end

    send_data csv, 
      type: "text/csv; charset=#{encoding}; header=present",
      disposition: "attachment; filename=companies.csv"
  end

index do
	column :name
	column :category
  column :sub_category
  column :description
	column :main_url
  column :all_tags
  actions
end

form do |f|
  f.inputs do
    f.input :name,          :placeholder => "LegalTech, Inc.",         :required => true
    f.input :location,      :placeholder => "Palo Alto, CA",           :required => true
    f.input :founded_date,  :placeholder => "2015",                    :required => true

    #f.input :category, as: :select,  collection: Category.all, :required => true, :include_blank => false
    #f.input :sub_category,  as: :select,  :required => false

    f.input :category, as: :select,  collection: Category.all.order(:name), :required => true, :include_blank => false
    f.input :sub_category,  as: :select, collection: option_groups_from_collection_for_select(Category.all.order(:name), :sub_categories, :name, :id, :name), :required => true, :include_blank => false
    
    f.input :target_client, as: :select, collection: TargetClient.all, :required => true, :include_blank => false
    f.input :business_model,as: :select, collection: BusinessModel.all, :required => true, :include_blank => false
    f.input :description,   :placeholder => "Makes great legal tech",  :required => true
    f.input :main_url,      :placeholder => "www.legaltech.com"
    f.input :twitter_url,   :placeholder => "@LegalTechInc"
    f.input :angellist_url, :placeholder => "www.angellist.com/legaltech"
    f.input :crunchbase_url,:placeholder => "www.crunchbase.com/legaltech"
    f.input :employee_count,:placeholder => "1"
    f.input :all_tags,      :placeholder => "All relevant tags separated by commas"
  end
  f.actions do
    f.action :submit
    f.action :cancel
  end
end

# or

# permit_params do
#   permitted = [:permitted, :attributes]
#   permitted << :other if resource.something?
#   permitted
# end


end
