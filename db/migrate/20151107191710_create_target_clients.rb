class CreateTargetClients < ActiveRecord::Migration[6.1]
  def change
    create_table :target_clients do |t|
      t.string :name
      t.text :description

      t.timestamps null: false
    end
    
    add_reference :companies, :target_client, index: true, foreign_key: true
  end
end
