class DuplicateLookupTool < RubyLLM::Tool
  description "Look up possible duplicate companies by name, brand, domain and shared LinkedIn/Crunchbase profile. Each candidate reports how it matched, its confidence, and whether it is publicly visible. Read-only."

  parameter :company_id, type: :integer, description: "Existing company id to exclude from candidate lists.", required: false
  parameter :name, description: "Company name to compare.", required: false
  parameter :url, description: "Company URL to compare.", required: false

  def execute(company_id: nil, name: nil, url: nil)
    normalized_name = Company.normalized_name_value(name)
    canonical_domain = Company.canonical_domain_for(url)
    matches = CompanyIdentityMatcher.matches_for(name: name, domains: [canonical_domain], exclude_company_id: company_id)

    {
      "lookup" => {
        "company_id" => company_id,
        "normalized_name" => normalized_name.presence,
        "canonical_domain" => canonical_domain
      },
      "name_candidates" => CompanyIdentityMatcher.name_matches(matches),
      "domain_candidates" => CompanyIdentityMatcher.domain_matches(matches),
      "read_only" => true
    }
  end
end
