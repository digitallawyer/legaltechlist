class AddAcquisitionFieldsToCompanies < ActiveRecord::Migration[8.0]
  def change
    add_column :companies, :acquirer_name, :string
    add_column :companies, :acquirer_url, :string
  end
end
