module Mcp
  module Tools
    # Create a directory entry directly from a KNOWN company, without web-search
    # discovery. Fills the gap for adding specific companies (especially historical/
    # acquired ones whose sites now redirect to the acquirer and never surface via
    # discovery) so curators no longer have to cannibalize a discovery-minted proposal
    # shell. It builds a proper proposal (with duplicate signals + quality gate) and,
    # when publish is requested, routes through the same approve_proposal path — so the
    # gating, autonomy thresholds, and one-step acquisition handling all apply.
    class CreateCompanyTool < BaseTool
      SOURCE = "curator_manual_entry".freeze

      tool_name "create_company"
      title "Create a company"
      description "Create a directory entry from a known company (no web-search discovery). Provide name and main_url plus any known facts and taxonomy ids (from get_taxonomy). Runs a duplicate check first and returns existing matches instead of creating a duplicate. By default it creates a pending proposal for review; pass publish=true (with a high confidence, or human_approved=true) to go live immediately, and an optional acquisition payload (acquirer_name/acquirer_url/acquired_on/successor_slug/source_url) or status (e.g. \"acquired\"/\"inactive\") to import a historical/acquired company straight into that lifecycle state in one call. Use this — not update_proposal on a discovery shell — to add specific companies."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, title: "Create a company")
      input_schema(
        properties: {
          name: { type: "string", description: "Company name." },
          main_url: { type: "string", description: "Company website (http(s))." },
          location: { type: "string", description: "Headquarters location, e.g. 'Boston, MA' or 'Leuven, Belgium'." },
          founded_date: { type: "string", description: "4-digit founding year." },
          description: { type: "string", description: "Neutral, encyclopedic description (required to publish live)." },
          status: { type: "string", description: "Lifecycle status to create into (e.g. \"active\", \"acquired\", \"inactive\"). Defaults to active, or acquired when an acquisition payload is given." },
          category_id: { type: "integer", description: "Primary category id (from get_taxonomy)." },
          secondary_category_id: { type: "integer", description: "Secondary category id (from get_taxonomy)." },
          business_model_ids: { type: "array", items: { type: "integer" }, description: "Business/revenue model ids (from get_taxonomy)." },
          target_client_ids: { type: "array", items: { type: "integer" }, description: "Target client ids (from get_taxonomy)." },
          all_tags: { type: "string", description: "Comma-separated canonical tag names (from get_taxonomy)." },
          crunchbase_url: { type: "string" },
          linkedin_url: { type: "string" },
          founders: { type: "string" },
          source_url: { type: "string", description: "Citation URL for the entry (defaults to main_url)." },
          publish: { type: "boolean", description: "Publish live immediately (requires human_approved=true or a confidence above the autonomy threshold and a passing quality gate). Omit to create a pending proposal for review." },
          confidence: { type: "number", description: "Your honest confidence (0.0-1.0) for an autonomous publish." },
          human_approved: { type: "boolean", description: "Set true only when a human approved this; overrides the auto-publish gate and confidence threshold." },
          duplicate_override: { type: "boolean", description: "Publish despite duplicate signals (only honored with human_approved)." },
          acquisition: {
            type: "object",
            description: "Optional: import as an acquired company (implies status=acquired). Requires publish.",
            properties: {
              acquirer_name: { type: "string" },
              acquirer_url: { type: "string" },
              acquired_on: { type: "string", description: "YYYY or YYYY-MM-DD." },
              successor_slug: { type: "string" },
              source_url: { type: "string" }
            }
          }
        },
        required: %w[name main_url]
      )

      def self.call(server_context:, name:, main_url:, location: nil, founded_date: nil, description: nil, status: nil,
                    category_id: nil, secondary_category_id: nil, business_model_ids: nil, target_client_ids: nil,
                    all_tags: nil, crunchbase_url: nil, linkedin_url: nil, founders: nil, source_url: nil,
                    publish: nil, confidence: nil, human_approved: false, duplicate_override: false, acquisition: nil)
        return error_response("result" => "blocked", "retryable" => false, "error" => "name is required.") if name.to_s.strip.blank?
        return error_response("result" => "blocked", "retryable" => false, "error" => "main_url is required.") if main_url.to_s.strip.blank?

        acquisition = (acquisition || {}).transform_keys(&:to_s).presence
        human_approved = ActiveModel::Type::Boolean.new.cast(human_approved)
        should_publish = ActiveModel::Type::Boolean.new.cast(publish) || human_approved

        if acquisition && !should_publish
          return error_response("result" => "blocked", "retryable" => false, "error" => "An acquisition payload requires publish=true (or human_approved=true) so a company exists to attach it to. To draft first, create without acquisition, then approve_proposal(publish:true, acquisition:{...}).")
        end

        normalized = AtlasCandidateNormalizerService.call("Organization Name" => name, "Website" => main_url)
        source_identifier = normalized["canonical_domain"].presence || Company.normalized_name_value(name)

        proposal = CompanyProposal.find_or_initialize_by(source: SOURCE, source_identifier: source_identifier)
        if proposal.persisted? && proposal.company_id.present?
          company = proposal.company
          return json_response("result" => "already_exists", "created" => false, "proposal_id" => proposal.id, "company_id" => company.id, "company_slug" => company.slug, "published" => company.visible, "profile_url" => (profile_url(company) if company.slug.present?), "duplicate_matches" => { "name" => normalized["name_matches"], "domain" => normalized["domain_matches"] })
        end

        changes = build_changes(
          name: name, main_url: normalized["website"], location: location, founded_date: founded_date,
          description: description, status: status, category_id: category_id, secondary_category_id: secondary_category_id,
          business_model_ids: business_model_ids, target_client_ids: target_client_ids, all_tags: all_tags,
          crunchbase_url: crunchbase_url.presence || normalized["crunchbase_url"], linkedin_url: linkedin_url.presence || normalized["linkedin_url"],
          founders: founders, source_url: source_url.presence || normalized["website"]
        )

        proposal.assign_attributes(
          status: "pending",
          proposal_type: "atlas_candidate",
          admin_user: curator,
          source_payload: normalized,
          proposed_changes: changes,
          final_changes: changes,
          duplicate_signals: { "name_matches" => Array(normalized["name_matches"]), "domain_matches" => Array(normalized["domain_matches"]), "recommended_action" => normalized["recommended_action"] },
          reviewer_notes: "Created via create_company (known company, no web discovery)."
        )
        proposal.save!

        audit!(action: "create_company", summary: "Created proposal #{proposal.id} for #{name}", records_processed: 1, details: { "proposal_id" => proposal.id, "source_identifier" => source_identifier, "will_publish" => should_publish })

        unless should_publish
          return json_response(
            "result" => "proposal_created",
            "created" => true,
            "published" => false,
            "proposal_id" => proposal.id,
            "duplicate_matches" => { "name" => normalized["name_matches"], "domain" => normalized["domain_matches"] },
            "recommended_action" => normalized["recommended_action"],
            "next_step" => "Review, then approve_proposal(id: #{proposal.id}, publish: true) to go live."
          )
        end

        # Delegate publishing to approve_proposal so gating, autonomy thresholds, and
        # the one-step status/acquisition handling are applied in exactly one place.
        ApproveProposalTool.call(
          server_context: server_context,
          id: proposal.id,
          publish: true,
          confidence: confidence,
          human_approved: human_approved,
          duplicate_override: duplicate_override,
          status: status,
          acquisition: acquisition
        )
      rescue ActiveRecord::RecordInvalid => e
        error_response("result" => "blocked", "retryable" => false, "error" => e.message)
      rescue StandardError => e
        Rails.logger.debug("[CreateCompanyTool] transient failure for #{name}: #{e.class}: #{e.message}")
        error_response("result" => "error", "retryable" => true, "error" => "Transient failure (#{e.class}); safe to retry: #{e.message}")
      end

      def self.build_changes(name:, main_url:, location:, founded_date:, description:, status:, category_id:, secondary_category_id:, business_model_ids:, target_client_ids:, all_tags:, crunchbase_url:, linkedin_url:, founders:, source_url:)
        business_ids = Array(business_model_ids).map(&:to_i).reject(&:zero?)
        client_ids = Array(target_client_ids).map(&:to_i).reject(&:zero?)
        {
          "name" => name.to_s.strip,
          "main_url" => main_url,
          "location" => location.presence && LocationCountryResolver.format_for_display(location),
          "founded_date" => founded_date.to_s[/\d{4}/],
          "description" => description.presence,
          "status" => status.presence,
          "category_id" => category_id,
          "secondary_category_id" => secondary_category_id,
          # Set both the singular id (used at company build/validation time) and the
          # array (applied after save for the has-many join) so the presence
          # validations pass on the initial save.
          "business_model_id" => business_ids.first,
          "business_model_ids" => business_ids.presence,
          "target_client_id" => client_ids.first,
          "target_client_ids" => client_ids.presence,
          "all_tags" => all_tags.presence,
          "crunchbase_url" => crunchbase_url.presence,
          "linkedin_url" => linkedin_url.presence,
          "founders" => founders.presence,
          "source" => "Curator manual entry",
          "source_url" => source_url
        }.compact.slice(*CompanyProposal::EDITABLE_COMPANY_FIELDS)
      end
    end
  end
end
