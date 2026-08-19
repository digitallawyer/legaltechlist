module Mcp
  module Tools
    # Lists the flagged duplicate-candidate PAIRS behind get_stats' aggregate counts so
    # a curator can review and merge them. Pairs are derived from companies sharing a
    # normalized name and/or a canonical domain; a pair matching both is reported once
    # with match_type "name+domain".
    class ListDuplicateCandidatesTool < BaseTool
      MAX_LIMIT = 200
      DEFAULT_LIMIT = 50
      CONFIDENCE = { "name" => 0.8, "domain" => 0.95, "name+domain" => 0.98 }.freeze

      tool_name "list_duplicate_candidates"
      title "List duplicate candidates"
      description "Return the flagged duplicate-candidate pairs (paginated) so they can be reviewed and merged: each pair is {company_id_a, company_id_b, name_a, name_b, match_type ('name'|'domain'|'name+domain'), matched_value, confidence}. get_stats only reports the aggregate; this lists the actual pairs. The detector only compares live rows (visible, non-rejected), so once you resolve a pair with merge_companies (or by hiding the loser) it drops out of this queue instead of re-surfacing. Filter by match_type ('name' or 'domain') to focus a pass. Page with offset until has_more is false. Resolve a pair with merge_companies(keep_id, merge_ids) to fold fields into the survivor and delete the duplicate."
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, title: "List duplicate candidates")
      input_schema(
        properties: {
          match_type: { type: "string", description: "Optional filter: 'name' (shared normalized name) or 'domain' (shared canonical domain). Omit for all pairs." },
          limit: { type: "integer", description: "Page size (1-200, default 50)." },
          offset: { type: "integer", description: "Pairs to skip for pagination (default 0)." }
        },
        required: []
      )

      def self.call(server_context:, match_type: nil, limit: DEFAULT_LIMIT, offset: 0)
        capped = [[limit.to_i, 1].max, MAX_LIMIT].min
        skip = [offset.to_i, 0].max

        pairs = build_pairs
        pairs = pairs.select { |pair| pair[:match_types].include?(match_type.to_s) } if %w[name domain].include?(match_type.to_s)

        total = pairs.size
        page = pairs.slice(skip, capped) || []
        names = company_name_index(page)

        json_response(
          "total" => total,
          "offset" => skip,
          "limit" => capped,
          "count" => page.size,
          "has_more" => (skip + page.size) < total,
          "match_type" => (%w[name domain].include?(match_type.to_s) ? match_type.to_s : "all"),
          "pairs" => page.map { |pair| serialize(pair, names) }
        )
      end

      # Merge name and domain groups into deduplicated pairs keyed by the id pair, so a
      # pair matching on both dimensions is reported once as "name+domain".
      def self.build_pairs
        pairs = {}

        Company.duplicate_name_groups.each do |group|
          group["ids"].combination(2).each do |a, b|
            entry = (pairs[[a, b]] ||= { ids: [a, b], match_types: [], matched_values: {} })
            entry[:match_types] |= ["name"]
            entry[:matched_values]["name"] = group["value"]
          end
        end

        Company.duplicate_domain_groups.each do |group|
          group["ids"].combination(2).each do |a, b|
            entry = (pairs[[a, b]] ||= { ids: [a, b], match_types: [], matched_values: {} })
            entry[:match_types] |= ["domain"]
            entry[:matched_values]["domain"] = group["value"]
          end
        end

        pairs.values.sort_by { |pair| [-confidence_for(pair[:match_types]), pair[:ids]] }
      end

      def self.confidence_for(match_types)
        CONFIDENCE[combined_match_type(match_types)] || 0.8
      end

      def self.combined_match_type(match_types)
        match_types.include?("name") && match_types.include?("domain") ? "name+domain" : match_types.first
      end

      def self.company_name_index(page)
        ids = page.flat_map { |pair| pair[:ids] }.uniq
        Company.where(id: ids).pluck(:id, :name, :slug).each_with_object({}) do |(id, name, slug), memo|
          memo[id] = { "name" => name, "slug" => slug }
        end
      end

      def self.serialize(pair, names)
        a, b = pair[:ids]
        combined = combined_match_type(pair[:match_types])
        matched_value = pair[:matched_values]["domain"] || pair[:matched_values]["name"]
        {
          "company_id_a" => a,
          "company_id_b" => b,
          "name_a" => names.dig(a, "name"),
          "name_b" => names.dig(b, "name"),
          "slug_a" => names.dig(a, "slug"),
          "slug_b" => names.dig(b, "slug"),
          "match_type" => combined,
          "matched_value" => matched_value,
          "confidence" => confidence_for(pair[:match_types])
        }
      end
    end
  end
end
