class AddCodexPresenterToCompanies < ActiveRecord::Migration
  def change
    add_column :companies, :codex_presenter, :boolean
    add_column :companies, :codex_presentation_date, :date
  end
end
