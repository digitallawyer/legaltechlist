class AddFoundersAndRegionToCompanies < ActiveRecord::Migration[7.0]
  def change
    add_column :companies, :founders, :text
    add_column :companies, :headquarters_region, :string
  end
end
