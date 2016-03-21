class AddLatitudeToCompanies < ActiveRecord::Migration
  def change
    add_column :companies, :latitude, :float
  end
end
