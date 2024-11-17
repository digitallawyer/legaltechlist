class AddContactEmailToCompanies < ActiveRecord::Migration[6.1]
  def change
    add_column :companies, :contact_email, :string
  end
end
