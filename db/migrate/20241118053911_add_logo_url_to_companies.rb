class AddLogoUrlToCompanies < ActiveRecord::Migration[7.0]
  def change
    add_column :companies, :logo_url, :string
  end
end
