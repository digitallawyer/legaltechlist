# What the server saw on a company's site, and what each review concluded from it.
# Snapshots are the shared memory: a review reuses a fresh one instead of fetching again,
# and a judgement is tied to the content hash it was made from. Events are the audit trail
# and the measurement: every judge, apply and second-opinion run is one row.
class CreateCompanyEvidenceSnapshotsAndReviewEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :company_evidence_snapshots do |t|
      t.references :company, null: false, foreign_key: true
      t.string :kind, null: false, default: "website"
      t.string :url, null: false
      t.string :final_url
      t.string :status, null: false
      t.string :reason
      t.integer :http_status
      t.boolean :renders_text, null: false, default: true
      t.string :title
      t.text :meta_description
      t.text :text
      t.string :content_hash
      t.datetime :fetched_at, null: false
      t.timestamps
    end
    add_index :company_evidence_snapshots, [:company_id, :kind, :fetched_at], name: "index_snapshots_on_company_kind_fetched"

    create_table :company_review_events do |t|
      t.references :company, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :actor
      t.string :model
      t.string :decision
      t.string :scope
      t.float :confidence
      t.string :evidence_hash
      t.boolean :applied, null: false, default: false
      t.jsonb :details, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :company_review_events, [:company_id, :occurred_at]
    add_index :company_review_events, [:kind, :occurred_at]
  end
end
