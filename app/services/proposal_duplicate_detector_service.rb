# Resolves, live, whether a proposal describes a company the index already holds or
# another open proposal already covers.
#
# This replaces the intake-time snapshot that used to be written once into
# CompanyProposal#duplicate_signals and never recomputed. That snapshot meant the
# approval gate could be reading a months-old view of the index, and because it only
# ever compared a candidate against Company rows, two proposals for the same company
# stayed mutually invisible and could both be approved.
#
# Matching runs on three keys:
#
#   exact    identical normalized name, or identical canonical domain.
#   redirect the candidate's domain resolves to a domain the index already holds, or
#            vice versa. Catches rebrands, where neither name nor declared domain
#            matches: a candidate at leahai.com against an entry at contractpodai.com.
#   core     identical name once corporate-form and generic product suffixes are
#            stripped, so "ContractPodAi" meets "ContractPod Technologies" and
#            "Midpage AI" meets "Midpage". Rejected when the surviving core is
#            generic ("legal", "contracts") or too short to assert identity on.
class ProposalDuplicateDetectorService
  CACHE_TTL = 5.minutes

  # Corporate form and generic product words that carry no identity of their own.
  NOISE_TOKENS = %w[
    inc incorporated llc llp ltd limited plc corp corporation co company
    gmbh ug ag sa sas sarl srl spa bv nv ab oy oyj aps kk pte pty pvt
    group holdings holding labs lab software solutions systems
    technologies technology tech platform platforms global international
    services digital online cloud the and
    ai io app hq
  ].freeze

  # Suffixes fused onto the end of a single token ("contractpodai"). Only stripped
  # when enough of the token survives to still identify a company, which keeps
  # place names such as Dubai and Mumbai intact.
  GLUED_SUFFIXES = %w[ai io app hq].freeze
  MIN_TOKEN_REMAINDER = 5

  # A core reducing to one of these describes a market, not a company, so it cannot
  # carry a duplicate claim on its own.
  GENERIC_CORES = %w[
    legal law lex juris justice legaltech lawtech contract contracts case cases
    document documents docs compliance counsel court courts advocate advocates
    attorney attorneys firm firms client clients matter matters practice ip
  ].freeze
  MIN_CORE_LENGTH = 4

  BLOCKING_MATCH_TYPES = %w[exact_domain exact_name redirect_domain core_name].freeze

  # How far the evidence actually goes. Both tiers still require a human to resolve
  # before approval — the Avokati AI pair that reached the public site matched on name
  # alone — but the reviewer is told which of the two they are looking at, and the
  # system never asserts "duplicate" on a name coincidence.
  #
  #   confirmed  same canonical domain, a domain that redirects to it, or a matching
  #              name corroborated by a shared LinkedIn or Crunchbase profile.
  #   possible   a name match with nothing else agreeing, or a shared domain with
  #              materially different names (one company, likely two products).
  CONFIDENCE_CONFIRMED = "confirmed".freeze
  CONFIDENCE_POSSIBLE = "possible".freeze

  def self.call(**kwargs)
    new(**kwargs).call
  end

  # extra_domains lets a caller feed in domains discovered by actually fetching the
  # candidate's site (see SiteEvidenceFetcherService), which is what makes the
  # redirect key work on the proposal side.
  def initialize(proposal:, extra_domains: [])
    @proposal = proposal
    @extra_domains = Array(extra_domains).compact_blank.map { |d| d.to_s.downcase }
  end

  def call
    company_hits = company_matches
    proposal_hits = proposal_matches

    {
      "name_matches" => company_hits.select { |hit| hit["match_type"].in?(%w[exact_name core_name]) },
      "domain_matches" => company_hits.select { |hit| hit["match_type"].in?(%w[exact_domain redirect_domain]) },
      "proposal_matches" => proposal_hits,
      "recommended_action" => recommended_action(company_hits, proposal_hits),
      "blocking" => (company_hits + proposal_hits).any? { |hit| hit["match_type"].in?(BLOCKING_MATCH_TYPES) },
      "confidence" => overall_confidence(company_hits + proposal_hits),
      "checked_at" => Time.current.utc.iso8601
    }
  end

  # ---- normalization ------------------------------------------------------

  def self.core_name(value)
    tokens = Company.normalized_name_value(value).split
    tokens = tokens.map { |token| strip_glued_suffix(token) }
    core = tokens.reject { |token| token.in?(NOISE_TOKENS) }.join(" ")
    return nil if core.blank?
    return nil if core.delete(" ").length < MIN_CORE_LENGTH
    return nil if core.split.all? { |token| token.in?(GENERIC_CORES) }

    core
  end

  def self.strip_glued_suffix(token)
    GLUED_SUFFIXES.each do |suffix|
      next unless token.end_with?(suffix)

      remainder = token[0..-(suffix.length + 1)]
      return remainder if remainder.length >= MIN_TOKEN_REMAINDER
    end
    token
  end

  private

  attr_reader :proposal, :extra_domains

  def changes
    @changes ||= proposal.editable_changes
  end

  def candidate_name
    @candidate_name ||= changes["name"].presence || proposal.source_payload["name"].presence
  end

  def normalized_name
    @normalized_name ||= Company.normalized_name_value(candidate_name)
  end

  def candidate_core
    return @candidate_core if defined?(@candidate_core)

    @candidate_core = self.class.core_name(candidate_name)
  end

  # Domains the record itself claims, as distinct from domains discovered by following
  # its redirects. A match on a domain the record never declared is the signature of a
  # rebrand, and the reviewer needs to be told that rather than just "duplicate".
  def declared_domains
    @declared_domains ||= [changes["main_url"], proposal.source_payload["website"], changes["source_url"]]
                          .map { |url| Company.canonical_domain_for(url) }.compact_blank.uniq
  end

  def candidate_domains
    @candidate_domains ||= (declared_domains + extra_domains).uniq
  end

  # ---- company side ------------------------------------------------------

  def company_matches
    return [] if normalized_name.blank? && candidate_domains.empty?

    company_index.filter_map do |row|
      # A proposal that has already minted its own company is not a duplicate of it:
      # without this, promoting an approved draft re-checks duplicates, finds the row the
      # proposal itself created, and blocks its own publication. A REJECTED proposal is
      # the other case — its company link records the entry that was kept instead, so
      # that relationship must stay visible.
      next if proposal.company_id.present? && row[:id] == proposal.company_id && !proposal.rejected?

      match_type = company_match_type(row)
      next unless match_type

      {
        "id" => row[:id],
        "name" => row[:name],
        "main_url" => row[:main_url],
        "canonical_domain" => row[:domain],
        "visible" => row[:visible],
        "match_type" => match_type,
        "matched_value" => matched_value_for(match_type, row),
        "confidence" => company_confidence(match_type, row),
        "shared_profiles" => shared_profiles(row)
      }
    end.first(10)
  end

  # A shared LinkedIn or Crunchbase profile is the cheapest reliable corroboration that
  # two records are the same company rather than two companies with one name.
  def shared_profiles(row)
    %w[linkedin crunchbase].select do |kind|
      mine = profile_key(changes["#{kind}_url"].presence || proposal.source_payload["#{kind}_url"])
      theirs = profile_key(row[:"#{kind}_url"])
      mine.present? && mine == theirs
    end
  end

  def profile_key(url)
    path = URI.parse(url.to_s.strip).path.to_s.downcase.delete_suffix("/")
    path.split("/").reject(&:blank?).last.presence
  rescue URI::InvalidURIError
    nil
  end

  def company_confidence(match_type, row)
    case match_type
    when "redirect_domain"
      CONFIDENCE_CONFIRMED
    when "exact_domain"
      # One domain can host more than one product. Treat a shared domain as confirmed
      # only when the names agree too; otherwise flag it as possibly a sibling product.
      names_agree?(row) ? CONFIDENCE_CONFIRMED : CONFIDENCE_POSSIBLE
    else
      shared_profiles(row).any? ? CONFIDENCE_CONFIRMED : CONFIDENCE_POSSIBLE
    end
  end

  def names_agree?(row)
    return true if normalized_name.present? && row[:normalized] == normalized_name

    candidate_core.present? && row[:core] == candidate_core
  end

  def overall_confidence(hits)
    return nil if hits.empty?

    hits.any? { |hit| hit["confidence"] == CONFIDENCE_CONFIRMED } ? CONFIDENCE_CONFIRMED : CONFIDENCE_POSSIBLE
  end

  def company_match_type(row)
    return "exact_domain" if row[:domain].present? && candidate_domains.include?(row[:domain])
    return "redirect_domain" if row[:final_domain].present? && candidate_domains.include?(row[:final_domain])
    return "exact_name" if normalized_name.present? && row[:normalized] == normalized_name
    return "core_name" if candidate_core.present? && row[:core] == candidate_core

    nil
  end

  def matched_value_for(match_type, row)
    case match_type
    when "exact_domain" then row[:domain]
    when "redirect_domain" then row[:final_domain]
    when "exact_name" then normalized_name
    when "core_name" then candidate_core
    end
  end

  # One pluck over the non-rejected index, with the derived match keys precomputed.
  # Hidden drafts are included on purpose: approving a proposal that duplicates an
  # unpublished draft still mints a second row.
  def company_index
    Rails.cache.fetch("proposal_duplicates/company_index/#{Company.duplicate_candidate_cache_version}", expires_in: CACHE_TTL) do
      Company.where("companies.quality_status IS DISTINCT FROM ?", "rejected")
             .pluck(:id, :name, :canonical_domain, :main_url, :visible, Arel.sql("companies.url_health->>'final_url'"), :linkedin_url, :crunchbase_url)
             .map do |id, name, canonical_domain, main_url, visible, final_url, linkedin_url, crunchbase_url|
        {
          id: id,
          name: name,
          main_url: main_url,
          visible: visible,
          linkedin_url: linkedin_url,
          crunchbase_url: crunchbase_url,
          domain: canonical_domain.presence || Company.canonical_domain_for(main_url),
          final_domain: Company.canonical_domain_for(final_url),
          normalized: Company.normalized_name_value(name),
          core: self.class.core_name(name)
        }
      end
    end
  end

  # ---- sibling-proposal side ---------------------------------------------

  def proposal_matches
    return [] if normalized_name.blank? && candidate_domains.empty?

    sibling_proposals.filter_map do |sibling|
      sibling_changes = sibling.editable_changes
      sibling_name = sibling_changes["name"].presence || sibling.source_payload["name"].presence
      sibling_domains = [sibling_changes["main_url"], sibling.source_payload["website"]]
                        .map { |url| Company.canonical_domain_for(url) }.compact_blank.uniq

      match_type = sibling_match_type(sibling_name, sibling_domains)
      next unless match_type

      {
        "proposal_id" => sibling.id,
        "name" => sibling.display_name,
        "main_url" => sibling_changes["main_url"],
        "status" => sibling.status,
        "created_at" => sibling.created_at&.utc&.iso8601,
        "match_type" => match_type,
        # The older record is the one an operator has probably already looked at, so
        # name a default canonical rather than leaving the choice unframed.
        "is_older" => sibling.created_at.present? && proposal.created_at.present? && sibling.created_at < proposal.created_at
      }
    end.first(10)
  end

  def sibling_match_type(sibling_name, sibling_domains)
    return "exact_domain" if (candidate_domains & sibling_domains).any?

    sibling_normalized = Company.normalized_name_value(sibling_name)
    return "exact_name" if normalized_name.present? && sibling_normalized == normalized_name

    sibling_core = self.class.core_name(sibling_name)
    return "core_name" if candidate_core.present? && sibling_core == candidate_core

    nil
  end

  def sibling_proposals
    scope = CompanyProposal.pending_review
    scope = scope.where.not(id: proposal.id) if proposal.id.present?
    scope
  end

  # ---- reviewer-facing summary -------------------------------------------

  # True when the matched domain is one we only learned by resolving the candidate's
  # site, not one the record declares.
  def rebrand?(hit)
    return true if hit["match_type"] == "redirect_domain"

    hit["match_type"] == "exact_domain" && hit["matched_value"].present? && !declared_domains.include?(hit["matched_value"])
  end

  def recommended_action(company_hits, proposal_hits)
    return nil if company_hits.empty? && proposal_hits.empty?

    parts = []
    if (company_hit = company_hits.first)
      label = "#{company_hit['name']} (##{company_hit['id']})"
      parts << if rebrand?(company_hit)
        "#{label} already covers #{company_hit['matched_value']} — this looks like a rebrand, so update that entry rather than creating a new one. Compare the two records to see what this proposal adds."
      elsif company_hit["confidence"] == CONFIDENCE_POSSIBLE && company_hit["match_type"] == "exact_domain"
        "#{label} shares this website but has a different name — it may be a different product from the same company. Compare the two records before treating this as a duplicate."
      elsif company_hit["confidence"] == CONFIDENCE_POSSIBLE
        "Possibly the same company as #{label}, matched on name alone with nothing else agreeing. Compare the two records to confirm before resolving."
      else
        corroboration = Array(company_hit["shared_profiles"]).presence
        basis = corroboration ? "name and a shared #{corroboration.to_sentence} profile" : "website"
        "#{label} is already in the index (matched on #{basis}). Compare the two records to see whether this proposal has anything the existing entry lacks, then keep one."
      end
    end

    if (proposal_hit = proposal_hits.first)
      canonical = proposal_hit["is_older"] ? "Proposal ##{proposal_hit['proposal_id']} is the earlier record" : "This is the earlier record"
      parts << "Proposal ##{proposal_hit['proposal_id']} covers the same company. #{canonical}; keep one and reject the other."
    end

    parts.join(" ")
  end
end
