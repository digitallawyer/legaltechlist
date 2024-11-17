class RemoveCompanyCategoryName < ActiveRecord::Migration[6.1]
  def change
    remove_column :companies, :category_name
  end
end
