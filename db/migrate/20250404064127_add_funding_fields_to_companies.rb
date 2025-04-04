class AddFundingFieldsToCompanies < ActiveRecord::Migration[7.0]
  def change
    add_column :companies, :total_funding_amount_usd, :decimal, precision: 15, scale: 2
    add_column :companies, :funding_status, :string
    add_column :companies, :number_of_funding_rounds, :integer
    add_column :companies, :exit_date, :date
  end
end
