ActiveAdmin.register SubCategory do
  permit_params :name, :description, :category_id

  # Remove any default filters that might be trying to use companies association
  remove_filter :companies

  index do
    column :name
    column :description
    column :category
    actions
  end

  form do |f|
    f.inputs do
      f.input :name
      f.input :description
      f.input :category
    end
    f.actions
  end

  filter :name
  filter :description
  filter :category
end
