class AddVisibleToCompanies < ActiveRecord::Migration[6.1]
  def change
    add_column :companies, :visible, :boolean, :default => true
  end
end
