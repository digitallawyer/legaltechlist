# One fetch of one page of a company's own web presence, as the server saw it.
class CompanyEvidenceSnapshot < ActiveRecord::Base
  belongs_to :company

  FRESH_FOR = 21.days

  scope :fetched, -> { where(status: "fetched") }
  scope :fresh, -> { where("fetched_at > ?", FRESH_FOR.ago) }

  # The page as a reader sees it, for a judge to read and for a quote to be checked against.
  def readable
    [title, meta_description, text].compact_blank.join("\n")
  end
end
