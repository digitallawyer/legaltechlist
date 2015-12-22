ActiveAdmin.register Company do

# See permitted parameters documentation:
# https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters

permit_params :name, :location, :founded_date, :category, :business_model, :target_client, :description, :main_url, 
  :twitter_url, :angellist_url, :crunchbase_url, :employee_count, :all_tags, 
  :category_id, :business_model_id, :target_client_id

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
    f.input :business_model,as: :select,collection: BusinessModel.all, :required => true, :include_blank => false
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

csv do
  column :name, :column_name => "name"
  column :location
  column :founded_date
  column (:category)        { |company| company.category.name }
  column (:sub_category)    { |company| company.sub_category.name }
  column (:target_client)   { |company| company.target_client.name }
  column (:business_model)  { |company| company.business_model.name }
  column :description
  column :main_url
  column :twitter_url
  column :angellist_url
  column :crunchbase_url
  column :employee_count
  column :all_tags
end

# or

# permit_params do
#   permitted = [:permitted, :attributes]
#   permitted << :other if resource.something?
#   permitted
# end


end
