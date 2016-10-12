class AddContactEmailToCompanies < ActiveRecord::Migration
  def change
    add_column :companies, :contact_email, :string
  end
end
