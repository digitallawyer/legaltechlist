class AddAcquisitionDetailsToCompanies < ActiveRecord::Migration[8.0]
  def change
    # Provenance for a recorded acquisition: the announcement source_url, the
    # precision of the acquisition date ("year" vs "day"), and when it was recorded.
    add_column :companies, :acquisition_details, :jsonb
  end
end
