class AddCategoriesToCompany < ActiveRecord::Migration
  def change
    rename_column :companies, :category, :category_name
    add_reference :companies, :category, index: true, foreign_key: true

    add_index :companies, :category_id
  end
end
