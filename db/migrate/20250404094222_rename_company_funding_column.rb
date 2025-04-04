class RenameCompanyFundingColumn < ActiveRecord::Migration[7.0]
  def change
    rename_column :companies, :total_funding_usd, :total_funding_amount_usd
  end
end
