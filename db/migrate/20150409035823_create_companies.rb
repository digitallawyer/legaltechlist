class CreateCompanies < ActiveRecord::Migration
  def change
    create_table :companies do |t|
      t.string :name
      t.string :location
      t.string :founded_date
      t.string :category
      t.text :description
      t.string :main_url
      t.string :twitter_url
      t.string :angellist_url
      t.string :crunchbase_url
      t.string :employee_count

      t.timestamps null: false
    end
  end
end
