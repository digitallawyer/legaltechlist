# Structured output for triaging a public directory submission (spam/quality gate).
# All fields required (OpenAI strict structured outputs).
class SubmissionTriageSchema < RubyLLM::Schema
  SCHEMA_VERSION = "2026-07-02.2".freeze

  string :verdict, enum: %w[accept review reject], description: "Triage verdict."
  number :confidence, description: "0.0-1.0 confidence in the verdict."
  string :reason, description: "Short reason for the verdict."
end
