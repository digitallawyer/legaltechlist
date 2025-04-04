class AddTotalFundingAmountUsdToCompanies < ActiveRecord::Migration[7.0]
  def change
    add_column :companies, :total_funding_amount_usd, :decimal
  end
end
