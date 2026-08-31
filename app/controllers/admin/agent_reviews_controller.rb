module Admin
  class AgentReviewsController < BaseController
    # The apply rules and the packet shape live in AgentReviewPacket, so the company
    # draft can render and act on the same findings without this controller.
    delegate :metadata_apply_fields, to: :class

    def self.metadata_apply_fields = AgentReviewPacket::METADATA_APPLY_FIELDS

    def show
      load_review
    end

    def apply
      load_review
      return redirect_back_to_review(alert: "This review is not linked to a company.") unless @company

      selected_fields = Array(params[:fields]) & @packet.applicable_corrections.keys
      return redirect_back_to_review(alert: apply_nothing_selected_alert) if selected_fields.empty?

      applied_changes = selected_fields.each_with_object({}) do |field, changes|
        value = cast_proposed_value(field, @packet.applicable_corrections[field])
        @company.public_send("#{field}=", value)
        changes[field] = value
      end

      @company.save!
      record_decision!("applied", applied_changes: applied_changes, selected_fields: selected_fields)

      redirect_back_to_review(notice: "Applied #{applied_changes.keys.map(&:humanize).map(&:downcase).to_sentence} to #{@company.name}.")
    rescue ActiveRecord::RecordInvalid => e
      redirect_back_to_review(alert: "Could not apply: #{e.record.errors.full_messages.to_sentence}.")
    end

    def reject
      load_review
      record_decision!("rejected")

      redirect_back_to_review(notice: "Agent review rejected without changing company data.")
    end

    def follow_up
      load_review
      record_decision!("needs_follow_up")

      redirect_back_to_review(notice: "Agent review marked for follow-up.")
    end

    private

    # Acting on findings shown inside a company draft returns to that draft, so the
    # reviewer never loses the record they were working on.
    def redirect_back_to_review(**flash_args)
      if params[:return_to] == "company" && @company
        redirect_to custom_admin_company_review_path(@company.id, anchor: "agent-review"), **flash_args
      else
        redirect_to custom_admin_agent_review_path(@pipeline_run), **flash_args
      end
    end

    def load_review
      @pipeline_run = PipelineRun.find(params[:id])
      @packet = AgentReviewPacket.new(@pipeline_run)
      @details = @packet.details
      @company = @packet.company
    end

    def apply_nothing_selected_alert
      return "Select at least one correction to apply." if @packet.applicable_corrections.any?

      @packet.description_apply_block.presence || "This review has no corrections that can be applied here."
    end

    def cast_proposed_value(field, value)
      return value.to_i if field == "quality_score" && value.present?

      value
    end

    def record_decision!(decision, applied_changes: {}, selected_fields: [])
      details = @details.deep_dup
      details["admin_decision"] = {
        "decision" => decision,
        "admin_user_id" => current_admin_user.id,
        "admin_user_email" => current_admin_user.email,
        "decided_at" => Time.current.utc.iso8601,
        "selected_fields" => selected_fields,
        "applied_changes" => applied_changes
      }
      # Provenance for the one change that alters public text: record which string the
      # admin published and why it was authorised.
      details["admin_decision"]["description_source"] = @packet.description_apply_source if applied_changes.key?("description") && @packet.description_apply_source.present?

      @pipeline_run.update!(details: details)
    end
  end
end
