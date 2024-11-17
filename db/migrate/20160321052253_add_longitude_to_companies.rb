class AddLongitudeToCompanies < ActiveRecord::Migration[6.1]
  def change
    add_column :companies, :longitude, :float
  end
end
