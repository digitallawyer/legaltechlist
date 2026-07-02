class AddUrlHealthToCompanies < ActiveRecord::Migration[8.0]
  def change
    add_column :companies, :url_status, :string
    add_column :companies, :url_status_code, :integer
    add_column :companies, :url_checked_at, :datetime
    add_column :companies, :url_health, :jsonb

    add_index :companies, :url_status
    add_index :companies, :url_checked_at
  end
end
