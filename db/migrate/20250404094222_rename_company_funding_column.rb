class RenameCompanyFundingColumn < ActiveRecord::Migration[7.0]
  def change
    add_column :companies, :total_funding_amount_usd, :decimal, precision: 15, scale: 2
  end
end
