ActiveAdmin.register Tag do
  permit_params :name

  index do
    column :name
    column :companies do |tag|
      tag.companies.count
    end
    actions
  end

  filter :name
  filter :companies

  form do |f|
    f.inputs do
      f.input :name
    end
    f.actions
  end

  # Show view
  show do
    attributes_table do
      row :name
      row :companies do |tag|
        ul do
          tag.companies.map { |company| li link_to(company.name, admin_company_path(company)) }
        end
      end
    end
  end
end
