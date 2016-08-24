class AddVisibleToCompanies < ActiveRecord::Migration
  def change
    add_column :companies, :visible, :boolean
  end
end
