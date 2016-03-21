class AddLongitudeToCompanies < ActiveRecord::Migration
  def change
    add_column :companies, :longitude, :float
  end
end
