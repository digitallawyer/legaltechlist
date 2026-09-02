module Mcp
  module Tools
    # Put back a description that an automated pass replaced.
    #
    # Every enrichment now keeps the wording it overwrote, so a restore is a lookup
    # rather than a reconstruction from a Slack thread. Restoring locks the record by
    # default, because the last authorised restore was destroyed by the next enrichment.
    class RestoreDescriptionTool < BaseTool
      tool_name "restore_description"
      title "Restore a replaced description"
      description "List or restore the descriptions an automated pass replaced on a record. Call without `restore` to see what is available, with the previous wording and when it was replaced. Call with restore=true to put the most recent previous wording back on the company (or index 1, 2… for older ones). The restored text must clear the publication gate, the record is locked against further automated description changes unless you pass lock=false, and both the restore and what it replaced are recorded."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, title: "Restore description")
      input_schema(
        properties: {
          proposal_id: { type: "integer", description: "Proposal whose description history to read." },
          slug: { type: "string", description: "Company to restore onto. Defaults to the proposal's own company." },
          restore: { type: "boolean", description: "false (default) lists what is available; true writes the chosen wording." },
          index: { type: "integer", description: "Which entry to restore, 0 being the most recently replaced. Default 0." },
          reason: { type: "string", description: "Required when restoring." },
          lock: { type: "boolean", description: "Default true: stop later automated passes replacing the restored text." }
        },
        required: %w[proposal_id]
      )

      def self.call(server_context:, proposal_id:, slug: nil, restore: false, index: 0, reason: nil, lock: nil)
        proposal = CompanyProposal.find_by(id: proposal_id)
        return not_found("Proposal #{proposal_id} not found") unless proposal

        history = Array(proposal.agent_details["description_history"])
        available = history.each_with_index.map do |entry, position|
          { "index" => history.size - 1 - position, "replaced_at" => entry["replaced_at"], "replaced_by" => entry["replaced_by"], "previous" => entry["previous"] }
        end.sort_by { |entry| entry["index"] }

        unless ActiveModel::Type::Boolean.new.cast(restore)
          return json_response("result" => "listed", "proposal_id" => proposal.id, "available" => available,
                               "note" => available.empty? ? "No description has been replaced on this record since history recording began." : "Call again with restore=true and a reason to write one of these back.")
        end

        return error_response("result" => "blocked", "retryable" => false, "error" => "reason is required when restoring.") if reason.to_s.strip.blank?

        chosen = available.find { |entry| entry["index"] == index.to_i }
        return not_found("No replaced description at index #{index}. Available: #{available.map { |e| e['index'] }.inspect}") unless chosen

        company = slug.present? ? find_company(slug) : proposal.company
        return not_found("No company to restore onto — pass slug.") unless company

        verdict = CompanyProposalEnrichmentService.description_critic_for(chosen["previous"])
        unless verdict["verdict"] == "pass"
          return error_response("result" => "blocked", "retryable" => false,
                                "error" => "The stored wording does not clear the publication gate (#{Array(verdict['issues']).to_sentence}). Edit it by hand with update_company_field.")
        end

        UpdateCompanyFieldTool.call(
          server_context: server_context, slug: company.id.to_s,
          fields: { "description" => chosen["previous"] },
          reason: reason, lock_description: lock.nil? ? true : lock
        )

        audit!(action: "restore_description", summary: "Restored description on #{company.name}", records_processed: 1,
               details: { "company_id" => company.id, "proposal_id" => proposal.id, "index" => index.to_i, "reason" => reason })

        json_response("result" => "restored", "company_id" => company.id, "proposal_id" => proposal.id,
                      "restored_from" => chosen["replaced_at"], "description" => chosen["previous"],
                      "description_locked" => lock.nil? ? true : ActiveModel::Type::Boolean.new.cast(lock))
      end
    end
  end
end
