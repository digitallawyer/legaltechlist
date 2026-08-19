module Admin
  class AgentReviewsController < BaseController
    # Bookkeeping fields. Applying them never changes public text, so they are
    # always offered when the packet proposes them.
    METADATA_APPLY_FIELDS = %w[
      quality_status
      verification_verdict
      quality_score
      canonical_domain
      fingerprint
    ].freeze

    # Public-text fields. A review packet may only write these through
    # applicable_description, which fails closed unless a critic verdict
    # authorises a specific string. Keyed by company attribute, not by the
    # packet's own key names (the packet calls the description
    # "proposed_description").
    CONTENT_APPLY_FIELDS = %w[description].freeze

    APPLY_FIELDS = (METADATA_APPLY_FIELDS + CONTENT_APPLY_FIELDS).freeze

    def show
      load_review
    end

    def apply
      load_review
      return redirect_to custom_admin_agent_review_path(@pipeline_run), alert: "This review is not linked to a company." unless @company

      selected_fields = Array(params[:fields]) & @applicable_corrections.keys
      return redirect_to custom_admin_agent_review_path(@pipeline_run), alert: apply_nothing_selected_alert if selected_fields.empty?

      applied_changes = selected_fields.each_with_object({}) do |field, changes|
        value = cast_proposed_value(field, @applicable_corrections[field])
        @company.public_send("#{field}=", value)
        changes[field] = value
      end

      @company.save!
      record_decision!("applied", applied_changes: applied_changes, selected_fields: selected_fields)

      redirect_to custom_admin_agent_review_path(@pipeline_run), notice: "Applied #{applied_changes.keys.map(&:humanize).map(&:downcase).to_sentence} to #{@company.name}."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to custom_admin_agent_review_path(@pipeline_run), alert: "Could not apply: #{e.record.errors.full_messages.to_sentence}."
    end

    def reject
      load_review
      record_decision!("rejected")

      redirect_to custom_admin_agent_review_path(@pipeline_run), notice: "Agent review rejected without changing company data."
    end

    def follow_up
      load_review
      record_decision!("needs_follow_up")

      redirect_to custom_admin_agent_review_path(@pipeline_run), notice: "Agent review marked for follow-up."
    end

    private

    def load_review
      @pipeline_run = PipelineRun.find(params[:id])
      @details = @pipeline_run.details || {}
      @company = Company.find_by(id: @details["company_id"])
      @evidence = Array(@details["evidence"])
      @tool_results = @details["tool_results"] || {}
      @proposed_corrections = @details["proposed_corrections"] || @details["proposed_changes"] || {}
      @description_draft = @details["description_draft"] || {}
      @description_critic = @details["description_critic"] || {}
      @review_coordinator = @details["review_coordinator"] || {}
      @duplicate_review = @details["duplicate_review"] || {}
      @risks = Array(@details["risks"])
      load_applicable_corrections
    end

    # Split the packet's proposed corrections into what an admin can apply here
    # (keyed by company attribute) and what stays informational. The description
    # is resolved separately because which string is authorised depends on the
    # critic verdict, and because a blocked description must explain itself
    # rather than silently vanish from the form.
    def load_applicable_corrections
      @applicable_corrections = @proposed_corrections.slice(*METADATA_APPLY_FIELDS)
      @description_apply_source = nil
      @description_apply_block = nil

      candidate = applicable_description
      if candidate
        @applicable_corrections["description"] = candidate[:value]
        @description_apply_source = candidate[:source]
      end

      @review_only_proposed_corrections = @proposed_corrections.except(*METADATA_APPLY_FIELDS, "proposed_description")
      @review_only_proposed_corrections["proposed_description"] = @proposed_corrections["proposed_description"] if @proposed_corrections.key?("proposed_description") && candidate.nil?
    end

    # The description string this packet authorises an admin to publish, or nil
    # with @description_apply_block set to the reason. Two gates, both required:
    #
    #   1. The stored critic verdict must name a specific string — the draft when
    #      the critic passed it, the critic's own narrower rewrite when it asked
    #      for a revision. A missing or rejecting verdict authorises nothing.
    #   2. That exact string must then clear the same deterministic description
    #      gate the publish path enforces, computed live. A stored verdict alone
    #      is never sufficient: the packet may predate later prompt or gate
    #      changes, and the text is about to become public.
    def applicable_description
      candidate = critic_authorised_description
      return nil if candidate.nil?

      verdict = CompanyProposalEnrichmentService.description_critic_for(candidate[:value])
      return candidate if verdict["verdict"] == "pass"

      issues = Array(verdict["issues"]).map(&:to_s).map(&:downcase).to_sentence.presence
      @description_apply_block = if issues
        "The #{candidate[:source]} does not clear the publication gate (#{issues}). Edit the company description directly instead."
      else
        "The #{candidate[:source]} does not clear the publication gate. Edit the company description directly instead."
      end
      nil
    end

    def critic_authorised_description
      proposed = @proposed_corrections["proposed_description"].to_s.strip
      suggested = @description_critic["suggested_revision"].to_s.strip
      verdict = @description_critic["verdict"].to_s

      case verdict
      when "pass"
        return { value: proposed, source: "critic-approved draft" } if proposed.present?

        @description_apply_block = "The critic passed this record but no proposed description was recorded."
      when "revise"
        return { value: suggested, source: "critic's suggested revision" } if suggested.present?

        @description_apply_block = "The critic asked for a revision but did not supply replacement text. Revise the description by hand."
      when ""
        @description_apply_block = "No description critic verdict is recorded on this review, so no description can be applied. Re-run the review first." if proposed.present?
      else
        @description_apply_block = "The critic returned #{verdict}, so its draft cannot be published. Revise the description by hand."
      end

      nil
    end

    def apply_nothing_selected_alert
      return "Select at least one correction to apply." if @applicable_corrections.any?

      @description_apply_block.presence || "This review has no corrections that can be applied here."
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
      # Provenance for the one change that alters public text: record which
      # string the admin published and why it was authorised.
      details["admin_decision"]["description_source"] = @description_apply_source if applied_changes.key?("description") && @description_apply_source.present?

      @pipeline_run.update!(details: details)
    end
  end
end
