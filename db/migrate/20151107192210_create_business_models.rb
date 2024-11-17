class CreateBusinessModels < ActiveRecord::Migration[6.1]
  def change
    create_table :business_models do |t|
      t.string :name
      t.text :description

      t.timestamps null: false
    end
    
    add_reference :companies, :business_model, index: true, foreign_key: true
  end
end
