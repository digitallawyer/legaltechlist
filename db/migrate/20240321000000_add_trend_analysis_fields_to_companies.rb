class AddTrendAnalysisFieldsToCompanies < ActiveRecord::Migration[7.0]
  def change
    add_column :companies, :funding_status, :string
    add_column :companies, :number_of_funding_rounds, :integer
    add_column :companies, :exit_date, :date
    add_column :companies, :stage, :string
    add_column :companies, :founders, :text
    add_column :companies, :headquarters_region, :string

    add_index :companies, :stage
    add_index :companies, :funding_status
    add_index :companies, :headquarters_region
  end
end
