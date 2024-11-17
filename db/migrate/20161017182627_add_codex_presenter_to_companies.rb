class AddCodexPresenterToCompanies < ActiveRecord::Migration[6.1]
  def change
    add_column :companies, :codex_presenter, :boolean
    add_column :companies, :codex_presentation_date, :date
  end
end
