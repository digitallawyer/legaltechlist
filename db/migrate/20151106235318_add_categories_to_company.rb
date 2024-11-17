class AddCategoriesToCompany < ActiveRecord::Migration[6.1]
  def change
    rename_column :companies, :category, :category_name
    add_reference :companies, :category, index: true, foreign_key: true
  end
end
