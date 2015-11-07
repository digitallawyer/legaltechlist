class RemoveCompanyCategoryName < ActiveRecord::Migration
  def change
    remove_column :companies, :category_name
  end
end
