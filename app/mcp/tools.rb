module Mcp
  module Tools
    module_function

    # Ordered list of curator tool classes exposed to Claude Tag.
    def all
      [
        # Read / context
        SearchCompaniesTool,
        ListCompaniesTool,
        GetCompanyTool,
        ListReviewQueueTool,
        GetProposalTool,
        DuplicateCheckTool,
        ListDuplicateCandidatesTool,
        GetTaxonomyTool,
        GetStatsTool,
        # Discovery
        DiscoverCompaniesTool,
        GetDiscoveryRunTool,
        # Proposal curation (tiered)
        EnrichProposalTool,
        AssessProposalTool,
        UpdateProposalTool,
        CuratePendingTool,
        ApproveProposalTool,
        RejectProposalTool,
        # Maintenance of existing entries
        CreateCompanyTool,
        RunCompanyReviewTool,
        ProposeCompanyUpdateTool,
        UpdateCompanyFieldTool,
        RecordAcquisitionTool,
        BackfillFoundedDatesTool,
        GetBackfillRunTool,
        CheckUrlHealthTool,
        ApplySafeFieldsTool,
        MarkReviewTool,
        SuggestTaxonomyTool,
        # Meta
        SuggestImprovementTool
      ]
    end
  end
end
