# One review step on a company: a judgement from evidence, a change applied from it, or a
# second opinion on it. The row says what the step saw (evidence_hash) and concluded.
class CompanyReviewEvent < ActiveRecord::Base
  belongs_to :company

  KINDS = %w[judge apply verify].freeze
  validates :kind, inclusion: { in: KINDS }

  scope :judgements, -> { where(kind: "judge") }
  scope :verifications, -> { where(kind: "verify") }
end
