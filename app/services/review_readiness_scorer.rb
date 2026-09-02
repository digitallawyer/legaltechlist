# Orders the not-reviewed backlog by how efficiently a human could actually decide each
# record, so a reviewer starts where their time goes furthest.
#
# Every signal Hafez listed — website present, description quality, field completeness,
# external profiles, duplicate flags, entity confidence, age — is already stored in
# TechIndex. So this is computed, not asked of a model: it is instant, free, identical
# every time, re-runs on every page load, and each score can state its own reasons in
# the reviewer's own terms. An LLM pass over ~3,000 records would cost real money to
# produce a less explainable version of the same ordering.
#
# It is a workflow recommendation and nothing else. It never writes to a company, never
# decides publication, and low readiness never means reject — it means "this one will
# take longer", which is why age keeps pushing records upward regardless of score.
class ReviewReadinessScorer
  HIGH = "high".freeze
  MEDIUM = "medium".freeze
  LOW = "low".freeze
  NEEDS_ASSESSMENT = "needs_assessment".freeze

  LEVEL_LABELS = {
    HIGH => "High priority",
    MEDIUM => "Medium priority",
    LOW => "Low priority",
    NEEDS_ASSESSMENT => "Needs assessment"
  }.freeze

  LEVEL_RANK = { HIGH => 0, MEDIUM => 1, LOW => 2, NEEDS_ASSESSMENT => 3 }.freeze

  # A record with nothing but a name cannot be scored honestly, so it is labelled as
  # unassessed rather than given a manufactured level.
  def self.call(company, duplicate_ids: [])
    new(company, duplicate_ids: duplicate_ids).call
  end

  # Sorts an already-loaded page of companies. Age breaks ties inside a level and, past
  # the stagnation threshold, promotes a record a whole level so difficult old records
  # cannot sit at the bottom forever.
  def self.order(companies, duplicate_ids: [])
    companies.map { |company| [company, call(company, duplicate_ids: duplicate_ids)] }
             .sort_by { |company, score| [score[:rank], -score[:age_days], company.id] }
  end

  STAGNATION_DAYS = 120

  def initialize(company, duplicate_ids: [])
    @company = company
    @duplicate_ids = duplicate_ids
  end

  def call
    return unassessed if unassessable?

    level = base_level
    promoted = promote_for_age?(level)
    level = promote(level) if promoted

    {
      level: level,
      label: LEVEL_LABELS[level],
      rank: LEVEL_RANK[level],
      age_days: age_days,
      reasons: reasons(promoted),
      promoted_for_age: promoted
    }
  end

  private

  attr_reader :company, :duplicate_ids

  def age_days
    @age_days ||= ((Time.current - (company.created_at || Time.current)) / 1.day).floor
  end

  def website? = company.main_url.present?
  def description_length = company.description.to_s.strip.length
  def usable_description? = description_length >= 120
  def thin_description? = description_length.between?(1, 119)
  def profiles = [company.linkedin_url, company.crunchbase_url].compact_blank.size
  def duplicate_flagged? = duplicate_ids.include?(company.id)
  def broken_url? = company.url_status == Company::URL_STATUS_BROKEN
  def taxonomy_known? = company.category.present? && company.category.name != "Unknown"

  # Nothing to go on: no website and no description worth reading.
  def unassessable?
    !website? && description_length.zero?
  end

  def unassessed
    {
      level: NEEDS_ASSESSMENT,
      label: LEVEL_LABELS[NEEDS_ASSESSMENT],
      rank: LEVEL_RANK[NEEDS_ASSESSMENT],
      age_days: age_days,
      reasons: ["No website and no description — there is nothing here to review yet."],
      promoted_for_age: false
    }
  end

  # Readiness is about whether a reviewer can reach a decision from what is on the
  # record, not about whether the company is any good.
  def base_level
    return LOW if broken_url? || !website?
    return LOW if duplicate_flagged? && !usable_description?
    return HIGH if usable_description? && taxonomy_known? && !duplicate_flagged?
    return MEDIUM if usable_description? || profiles.positive?

    LOW
  end

  def promote_for_age?(level)
    level != HIGH && age_days >= STAGNATION_DAYS
  end

  def promote(level)
    return HIGH if level == MEDIUM

    MEDIUM
  end

  # Phrased for a reviewer deciding what to open next, not as a scoring breakdown.
  def reasons(promoted)
    parts = []
    parts << (website? ? "Official website on file" : "No website on file")
    parts << if usable_description?
      "description present"
    elsif thin_description?
      "description is thin"
    else
      "no description"
    end
    parts << "#{profiles} external profile#{'s' unless profiles == 1}" if profiles.positive?
    parts << "website is not responding" if broken_url?
    parts << "flagged as a possible duplicate" if duplicate_flagged?
    parts << "category not yet identified" unless taxonomy_known?
    parts << "pending #{age_days} day#{'s' unless age_days == 1}"
    parts << "moved up because it has been waiting" if promoted
    [parts.join(", ").upcase_first + "."]
  end
end
