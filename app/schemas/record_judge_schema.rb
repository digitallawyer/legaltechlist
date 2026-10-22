class RecordJudgeSchema < Schematist::Schema
  SCHEMA_VERSION = "2026-10-22.1".freeze

  string :scope, enum: %w[in_scope law_firm consultancy not_legal_tech parked_or_for_sale unreadable], description: "What kind of company the pages show."
  string :decision, enum: %w[list close needs_work], description: "list, close (not in scope, shown plainly), or needs_work (unreadable, ambiguous or unsure)."
  string :description, description: "Entry text when decision is list, from the pages only; empty otherwise."
  array :support_quotes, of: :string, description: "Short exact snippets from the pages backing the description."
  string :successor_note, description: "If the site belongs to a different company than the record, who it is; otherwise empty."
  string :reason, description: "One or two sentences of evidence for the scope and decision."
  number :confidence, description: "0.0-1.0 confidence in the decision."
end
