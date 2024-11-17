ActiveAdmin.register Category do

# See permitted parameters documentation:
# https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
#
permit_params :name, :description

index do
	column :name
	column :description
  actions
end

# Remove any default filters that might be trying to use companies association
remove_filter :companies

form do |f|
  f.inputs do
    f.input :name
    f.input :description
  end
  f.actions
end

#
# or
#
# permit_params do
#   permitted = [:permitted, :attributes]
#   permitted << :other if resource.something?
#   permitted
# end


end
