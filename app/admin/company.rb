ActiveAdmin.register Company do

# See permitted parameters documentation:
# https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters

permit_params :name, :location, :founded_date, :category, :description, :main_url, :twitter_url, :angellist_url, :crunchbase_url, :employee_count, :all_tags

index do
	column :name
	column :category
  column :description
	column :main_url
  column :all_tags
end

# or

# permit_params do
#   permitted = [:permitted, :attributes]
#   permitted << :other if resource.something?
#   permitted
# end


end
