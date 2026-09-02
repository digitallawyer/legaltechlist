module Mcp
  module Tools
    class UpdateProposalTool < BaseTool
      tool_name "update_proposal"
      title "Update proposal"
      # Setting any taxonomy field counts as a curator confirmation of the taxonomy,
      # which clears the "low-confidence taxonomy" quality blocker (previously only
      # re-running enrich_proposal could clear it).
      TAXONOMY_FIELDS = %w[category_id secondary_category_id business_model_id business_model_ids target_client_id target_client_ids].freeze

      description "Set corrected values on a pending proposal before approval. Writes allowlisted company fields into the proposal's final_changes and returns a refreshed quality report. Setting taxonomy fields (category/business model/target client) marks the taxonomy as curator-confirmed, clearing the low-confidence-taxonomy blocker. Use get_taxonomy for valid ids/tags. Descriptions must be neutral and public-ready: no marketing language, no internal notes, no remarks about missing information."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, title: "Update proposal")
      input_schema(
        properties: {
          id: { type: "integer", description: "Proposal id." },
          changes: { type: "object", description: "Company fields to set on the proposal.", properties: CHANGE_FIELD_SCHEMA, additionalProperties: false },
          evidence: {
            type: "array",
            description: "Pages you actually opened for this record. Recorded as evidence so the research gate can be satisfied without running enrichment, which rewrites the description. Each entry is {url, note}. Only cite pages you read.",
            items: { type: "object", properties: { url: { type: "string" }, note: { type: "string" } }, required: %w[url] }
          }
        },
        required: %w[id]
      )

      def self.call(server_context:, id:, changes: nil, evidence: nil)
        proposal = CompanyProposal.find_by(id: id)
        return not_found("Proposal #{id} not found") unless proposal
        return error_response("error" => "Cannot edit a #{proposal.status} proposal.") if proposal.status.in?(%w[published rejected])

        recorded_evidence = record_evidence!(proposal, evidence)
        applied = slice_editable_changes(changes || {})
        if applied.empty? && recorded_evidence.zero?
          return error_response("error" => "Provide changes and/or evidence. Editable fields: #{CompanyProposal::EDITABLE_COMPANY_FIELDS.join(', ')}")
        end

        proposal.final_changes = proposal.final_changes.merge(applied)
        taxonomy_confirmed = confirm_taxonomy!(proposal) if (applied.keys & TAXONOMY_FIELDS).any?
        refresh_description_critic!(proposal) if applied.key?("description")
        proposal.save!
        proposal.reload
        quality = CompanyProposalQualityService.call(proposal)

        audit!(action: "update_proposal", summary: "Updated proposal #{id} fields: #{applied.keys.join(', ')}", records_processed: 1, details: { "proposal_id" => id, "fields" => applied.keys, "taxonomy_confirmed" => taxonomy_confirmed })

        json_response(
          "result" => "updated",
          "proposal_id" => proposal.id,
          "status" => proposal.status,
          "updated_fields" => applied.keys,
          "persisted_changes" => proposal.final_changes.slice(*applied.keys),
          "taxonomy_confirmed" => taxonomy_confirmed || false,
          "evidence_recorded" => recorded_evidence,
          "publish_ready" => quality["publish_ready"],
          "blockers" => quality["blockers"],
          "final_changes" => proposal.final_changes,
          "quality" => quality,
          "duplicate_blocking" => proposal.duplicate_blocking?,
          "admin_url" => admin_proposal_url(proposal)
        )
      rescue ActiveRecord::RecordInvalid => e
        error_response("result" => "error", "retryable" => false, "error" => e.message)
      rescue StandardError => e
        Rails.logger.debug("[UpdateProposalTool] transient failure for proposal #{id}: #{e.class}: #{e.message}")
        error_response("result" => "error", "retryable" => true, "error" => "Transient failure (#{e.class}); safe to retry: #{e.message}")
      end

      # Keep the stored critic verdict in sync with an edited description so the
      # persisted agent_details never disagrees with the live publish gate.
      def self.refresh_description_critic!(proposal)
        description = proposal.final_changes["description"]
        critic = if description.blank?
          nil
        else
          CompanyProposalEnrichmentService.description_critic_for(
            description,
            source_description: proposal.source_payload["source_description"],
            full_source_description: proposal.source_payload["full_source_description"]
          )
        end
        proposal.agent_details = proposal.agent_details.merge("description_critic" => critic)
      end

      # Sources a curator read themselves. Recorded in the same shape the research gate
      # already understands, so a record can be established as researched without
      # running the one operation that overwrites its description. Attribution is
      # explicit: these are the curator's citations, not retrieved pages.
      def self.record_evidence!(proposal, evidence)
        entries = Array(evidence).filter_map do |entry|
          attrs = entry.respond_to?(:to_unsafe_h) ? entry.to_unsafe_h : entry.to_h
          url = attrs["url"].presence || attrs[:url].presence
          next unless Company.valid_http_url?(url)

          { "title" => (attrs["note"] || attrs[:note]).to_s.squish.presence || url, "url" => url,
            "snippet" => (attrs["note"] || attrs[:note]).to_s.squish.presence,
            "recorded_by" => "curator", "recorded_at" => Time.current.utc.iso8601 }.compact
        end
        return 0 if entries.empty?

        research = proposal.agent_details["web_research"]
        research = { "mode" => "curator_recorded", "results" => [] } unless research.is_a?(Hash)
        research["results"] = Array(research["results"]) + entries
        proposal.agent_details = proposal.agent_details.merge("web_research" => research)
        entries.size
      end

      def self.confirm_taxonomy!(proposal)
        suggestion = proposal.agent_details["taxonomy_suggestion"]
        suggestion = {} unless suggestion.is_a?(Hash)
        proposal.agent_details = proposal.agent_details.merge(
          "taxonomy_suggestion" => suggestion.merge("accepted" => true, "confirmed_by" => "curator", "confirmed_at" => Time.current.utc.iso8601)
        )
        true
      end
    end
  end
end
