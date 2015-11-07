class CreateSubCategories < ActiveRecord::Migration
  def change
    create_table :sub_categories do |t|
      t.string :name
      t.text :description
      t.belongs_to :category, index: true, foreign_key: true

      t.timestamps null: false
    end
    
    add_reference :companies, :sub_category, index: true, foreign_key: true
  end
end
