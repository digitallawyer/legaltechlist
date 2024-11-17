class AddLatitudeToCompanies < ActiveRecord::Migration[6.1]
  def change
    add_column :companies, :latitude, :float
  end
end
