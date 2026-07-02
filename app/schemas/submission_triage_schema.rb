# Structured output for triaging a public directory submission (spam/quality gate).
class SubmissionTriageSchema < RubyLLM::Schema
  SCHEMA_VERSION = "2026-07-02.1".freeze

  string :verdict, enum: %w[accept review reject], description: "Triage verdict."
  number :confidence, required: false, description: "0.0-1.0 confidence in the verdict."
  string :reason, required: false, description: "Short reason for the verdict."
end
