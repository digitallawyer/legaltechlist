class AddContactNameToCompanies < ActiveRecord::Migration[6.1]
  def change
    add_column :companies, :contact_name, :string
  end
end
