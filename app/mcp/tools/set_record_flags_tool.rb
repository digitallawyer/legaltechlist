module Mcp
  module Tools
    # Turn automated changes off for a record that keeps being damaged, and turn them
    # back on. Without this, protecting a record meant asking engineering, and every
    # restore raced the next enrichment — which is how the SpecterAI restore was lost.
    class SetRecordFlagsTool < BaseTool
      tool_name "set_record_flags"
      title "Set per-record automation flags"
      description "Turn automated processing on or off for one record. do_not_enrich stops enrichment touching it at all; description_locked stops any automated path replacing its description while still allowing a deliberate edit through update_company_field. Both are durable, both are reported by get_company and get_proposal, and both require a reason. Set the flag BEFORE restoring text: the other order is how a previous restore was overwritten."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true, title: "Set record flags")
      input_schema(
        properties: {
          slug: { type: "string", description: "Company slug or numeric id. Give this or proposal_id." },
          proposal_id: { type: "integer", description: "Proposal id. Give this or slug." },
          do_not_enrich: { type: "boolean", description: "true to stop enrichment for this record, false to allow it again." },
          description_locked: { type: "boolean", description: "true to stop automated description replacement, false to allow it again. Company records only." },
          reason: { type: "string", description: "Required. Why this record is being protected or released." }
        },
        required: %w[reason]
      )

      def self.call(server_context:, reason:, slug: nil, proposal_id: nil, do_not_enrich: nil, description_locked: nil)
        return error_response("result" => "blocked", "retryable" => false, "error" => "reason is required.") if reason.to_s.strip.blank?
        if do_not_enrich.nil? && description_locked.nil?
          return error_response("result" => "blocked", "retryable" => false, "error" => "Set do_not_enrich and/or description_locked.")
        end

        if proposal_id.present?
          proposal = CompanyProposal.find_by(id: proposal_id)
          return not_found("Proposal #{proposal_id} not found") unless proposal

          apply_to_proposal!(proposal, do_not_enrich: do_not_enrich, reason: reason)
          audit!(action: "set_record_flags", summary: "Flags set on proposal #{proposal.id}", records_processed: 1,
                 details: { "proposal_id" => proposal.id, "do_not_enrich" => do_not_enrich, "reason" => reason })
          return json_response("result" => "updated", "proposal_id" => proposal.id,
                               "do_not_enrich" => proposal.agent_details["do_not_enrich"] == true)
        end

        company = find_company(slug)
        return not_found("Company '#{slug}' not found") unless company

        apply_to_company!(company, do_not_enrich: do_not_enrich, description_locked: description_locked, reason: reason)
        audit!(action: "set_record_flags", summary: "Flags set on #{company.name}", records_processed: 1,
               details: { "company_id" => company.id, "do_not_enrich" => do_not_enrich, "description_locked" => description_locked, "reason" => reason })

        json_response("result" => "updated", "company_id" => company.id,
                      "do_not_enrich" => company.quality_review["do_not_enrich"] == true,
                      "description_locked" => company.quality_review["description_locked"] == true)
      end

      def self.apply_to_proposal!(proposal, do_not_enrich:, reason:)
        details = proposal.agent_details.deep_dup
        unless do_not_enrich.nil?
          details["do_not_enrich"] = ActiveModel::Type::Boolean.new.cast(do_not_enrich)
          details["do_not_enrich_reason"] = reason.to_s.strip
          details["do_not_enrich_set_at"] = Time.current.utc.iso8601
        end
        proposal.update_columns(agent_details: details)
      end

      def self.apply_to_company!(company, do_not_enrich:, description_locked:, reason:)
        review = company.quality_review.is_a?(Hash) ? company.quality_review.deep_dup : {}
        %w[do_not_enrich description_locked].each do |flag|
          value = flag == "do_not_enrich" ? do_not_enrich : description_locked
          next if value.nil?

          review[flag] = ActiveModel::Type::Boolean.new.cast(value)
          review["#{flag}_reason"] = reason.to_s.strip
          review["#{flag}_set_at"] = Time.current.utc.iso8601
        end
        company.update_columns(quality_review: review)
      end
    end
  end
end
