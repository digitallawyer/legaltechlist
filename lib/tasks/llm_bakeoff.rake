namespace :llm do
  # Compare candidate models on the real description-drafting prompt so we can
  # decide, on evidence, whether a cheaper model matches gpt-5.5's quality.
  #
  #   MODELS="gpt-5.5,gpt-5.4,gpt-5.4-mini" bin/rails llm:description_bakeoff
  desc "Bake off models on the enrichment description prompt (quality + cost)"
  task description_bakeoff: :environment do
    models = ENV.fetch("MODELS", "gpt-5.5,gpt-5.4,gpt-5.4-mini").split(",").map(&:strip).reject(&:blank?)

    samples = [
      {
        name: "Ironclad",
        candidate: { "name" => "Ironclad", "website" => "https://ironcladapp.com", "location" => "San Francisco, USA", "industries" => ["Contract Management", "Legal Tech", "SaaS"] },
        source_evidence: { "short_description" => "Contract lifecycle management platform with workflow automation and embedded AI for legal, procurement, and sales teams.", "website" => "https://ironcladapp.com" }
      },
      {
        name: "Axiom",
        candidate: { "name" => "Axiom", "website" => "https://www.axiomlaw.com", "location" => "New York, USA", "industries" => ["Legal Services", "Alternative Legal Services"] },
        source_evidence: { "short_description" => "Flexible legal talent and managed legal services for corporate legal departments.", "website" => "https://www.axiomlaw.com" }
      },
      {
        name: "Brightflag",
        candidate: { "name" => "Brightflag", "website" => "https://www.brightflag.com", "location" => "Dublin, Ireland", "industries" => ["Legal Operations", "Legal Spend Management"] },
        source_evidence: { "short_description" => "Legal operations platform for matter management, legal spend control, AI invoice review, and vendor benchmarking.", "website" => "https://www.brightflag.com" }
      },
      {
        name: "Naseh (thin evidence)",
        candidate: { "name" => "Naseh", "website" => "https://naseh.example", "location" => "Riyadh, Saudi Arabia", "industries" => ["Legal Tech"] },
        source_evidence: { "short_description" => "Online legal consultation platform connecting individuals with lawyers.", "website" => "https://naseh.example" }
      },
      {
        name: "Jus Mundi",
        candidate: { "name" => "Jus Mundi", "website" => "https://jusmundi.com", "location" => "Paris, France", "industries" => ["Legal Research", "Arbitration", "AI"] },
        source_evidence: { "short_description" => "AI-powered legal research search engine for international law and arbitration.", "website" => "https://jusmundi.com" }
      }
    ]

    totals = Hash.new { |h, k| h[k] = { cost: 0.0, in: 0, out: 0, ms: 0.0, pass: 0, words: 0, n: 0 } }

    samples.each do |sample|
      puts "\n" + ("=" * 100)
      puts "COMPANY: #{sample[:name]}   evidence: #{sample[:source_evidence]['short_description']}"
      puts("=" * 100)

      prompt = CompanyProposalEnrichmentService.description_prompt_for(
        candidate: sample[:candidate],
        source_evidence: sample[:source_evidence],
        web_research: {}
      )

      models.each do |model|
        started = Time.current
        begin
          chat = RubyLLM.chat(model: model, provider: :openai, assume_model_exists: true)
          response = chat.ask(prompt)
          ms = ((Time.current - started) * 1000).round
          parsed = safe_json(response.content)
          raw = parsed["proposed_description"].to_s
          cleaned = CompanyProposalEnrichmentService.clean_description(raw)
          critic = CompanyProposalEnrichmentService.description_critic_for(cleaned, source_description: sample[:source_evidence]["short_description"])
          in_tok = response.input_tokens.to_i
          out_tok = response.output_tokens.to_i
          cost = model_cost(response.model_id.presence || model, in_tok, out_tok)
          words = cleaned.split.size

          t = totals[model]
          t[:cost] += cost; t[:in] += in_tok; t[:out] += out_tok; t[:ms] += ms
          t[:pass] += (critic["verdict"] == "pass" ? 1 : 0); t[:words] += words; t[:n] += 1

          puts "\n-- #{model}  [#{critic['verdict'].upcase}]  #{words}w  #{in_tok}+#{out_tok}tok  $#{format('%.5f', cost)}  #{ms}ms"
          puts "   #{cleaned}"
          puts "   issues: #{critic['issues'].join('; ')}" if critic["issues"].any?
        rescue StandardError => e
          puts "\n-- #{model}  ERROR: #{e.class}: #{e.message}"
        end
      end
    end

    puts "\n\n" + ("#" * 100)
    puts "SUMMARY (per description, averaged over #{samples.size} companies)"
    puts("#" * 100)
    printf("%-16s %8s %8s %10s %10s %8s\n", "model", "pass", "avg words", "avg cost", "proj/1k", "avg ms")
    models.each do |model|
      t = totals[model]
      next if t[:n].zero?

      avg_cost = t[:cost] / t[:n]
      printf("%-16s %6d/%d %9.1f %9s %9s %8d\n", model, t[:pass], t[:n], (t[:words].to_f / t[:n]), "$#{format('%.5f', avg_cost)}", "$#{format('%.2f', avg_cost * 1000)}", (t[:ms] / t[:n]).round)
    end
    puts "\nproj/1k = projected cost to draft 1,000 descriptions at this evidence size (excludes web-search tokens)."
  end

  # Compare candidate models on taxonomy classification accuracy against a small
  # labeled sample, using the real CompanyProposalTaxonomySuggestionService (so the
  # controlled vocabulary and DB mapping match production exactly).
  #
  #   MODELS="gpt-5.4-nano,gpt-5.4-mini,gpt-5.4" bin/rails llm:taxonomy_bakeoff
  desc "Bake off models on taxonomy classification accuracy"
  task taxonomy_bakeoff: :environment do
    models = ENV.fetch("MODELS", "gpt-5.4-nano,gpt-5.4-mini,gpt-5.4").split(",").map(&:strip).reject(&:blank?)
    original_model = ENV["RUBYLLM_TAXONOMY_MODEL"]
    ENV["PROPOSAL_TAXONOMY_USE_LLM"] = "true"

    samples = [
      { name: "Ironclad", industries: ["Contract Management", "SaaS", "AI"], desc: "Contract lifecycle management platform with workflow automation and embedded AI for legal, procurement, and sales teams.", website: "https://ironcladapp.com",
        categories: ["Contract Management"], revenues: ["Subscription"], targets: ["Corporate Legal", "Law Firms"] },
      { name: "Axiom", industries: ["Legal Services", "Alternative Legal Services"], desc: "Flexible legal talent and managed legal services for corporate legal departments.", website: "https://www.axiomlaw.com",
        categories: ["Marketplace and ALSPs"], revenues: ["Services"], targets: ["Corporate Legal", "Legal Service Providers"] },
      { name: "Brightflag", industries: ["Legal Operations", "Legal Spend Management"], desc: "Legal operations platform for matter management, legal spend control, AI invoice review, and vendor benchmarking.", website: "https://www.brightflag.com",
        categories: ["Legal Operations / ELM", "Analytics & Insights"], revenues: ["Subscription"], targets: ["Corporate Legal"] },
      { name: "Jus Mundi", industries: ["Legal Research", "Arbitration", "AI"], desc: "AI-powered legal research search engine for international law and arbitration.", website: "https://jusmundi.com",
        categories: ["Knowledge & Research"], revenues: ["Subscription"], targets: ["Law Firms", "Corporate Legal"] },
      { name: "Relativity", industries: ["eDiscovery", "Litigation Support"], desc: "eDiscovery platform for processing, reviewing, and analyzing electronically stored information in litigation and investigations.", website: "https://www.relativity.com",
        categories: ["eDiscovery & Investigations"], revenues: ["Subscription"], targets: ["Law Firms", "Corporate Legal"] },
      { name: "Rocket Lawyer", industries: ["Legal Documents", "Consumer Legal"], desc: "Online legal service offering document automation, e-signature, and on-demand attorney advice for individuals and small businesses.", website: "https://www.rocketlawyer.com",
        categories: ["Document Management and Automation", "Practice Management", "Access to Justice & Public Sector"], revenues: ["Subscription"], targets: ["Consumers"] }
    ]

    totals = Hash.new { |h, k| h[k] = { cat: 0, rev: 0, tgt: 0, acc: 0, n: 0 } }

    samples.each do |s|
      puts "\n" + ("=" * 100)
      puts "#{s[:name]}  |  gold cat: #{s[:categories].join(' / ')}  rev: #{s[:revenues].join(', ')}  target: #{s[:targets].join(' / ')}"
      puts("=" * 100)

      source_payload = { "name" => s[:name], "industries" => s[:industries], "source_description" => s[:desc], "website" => s[:website] }

      models.each do |model|
        ENV["RUBYLLM_TAXONOMY_MODEL"] = model
        begin
          result = CompanyProposalTaxonomySuggestionService.call(source_payload: source_payload, final_changes: {})
          pred_cat = result.dig("category", "name")
          pred_rev = Array(result.dig("revenue_models", "names"))
          pred_tgt = ([result.dig("target_client", "name")] + Array(result.dig("target_clients", "names"))).compact.uniq

          cat_ok = s[:categories].include?(pred_cat)
          rev_ok = (pred_rev & s[:revenues]).any?
          tgt_ok = (pred_tgt & s[:targets]).any?
          accepted = result["accepted"] ? 1 : 0

          t = totals[model]
          t[:cat] += cat_ok ? 1 : 0; t[:rev] += rev_ok ? 1 : 0; t[:tgt] += tgt_ok ? 1 : 0; t[:acc] += accepted; t[:n] += 1

          flag = [cat_ok ? "cat" : "CAT✗", rev_ok ? "rev" : "REV✗", tgt_ok ? "tgt" : "TGT✗"].join(" ")
          puts "  #{model.ljust(14)} [#{flag}] #{result['accepted'] ? 'accepted' : 'held'}  => cat:#{pred_cat}  rev:#{pred_rev.join('/')}  tgt:#{pred_tgt.join('/')}"
        rescue StandardError => e
          puts "  #{model.ljust(14)} ERROR: #{e.class}: #{e.message}"
        end
      end
    end

    ENV["RUBYLLM_TAXONOMY_MODEL"] = original_model

    puts "\n\n" + ("#" * 100)
    puts "TAXONOMY ACCURACY (matches / #{samples.size})"
    puts("#" * 100)
    printf("%-16s %10s %10s %12s %10s\n", "model", "category", "revenue", "target", "accepted")
    models.each do |model|
      t = totals[model]
      next if t[:n].zero?

      printf("%-16s %8d/%d %8d/%d %10d/%d %8d/%d\n", model, t[:cat], t[:n], t[:rev], t[:n], t[:tgt], t[:n], t[:acc], t[:n])
    end
  end
end

def safe_json(content)
  return content if content.is_a?(Hash)

  text = content.to_s
  JSON.parse(text[/\{.*\}/m] || text)
rescue JSON::ParserError
  { "proposed_description" => content.to_s }
end

# Per 1M tokens [input, output], from OpenAI pricing (verified 2026-07).
BAKEOFF_PRICES = {
  "gpt-5.5" => [5.0, 30.0],
  "gpt-5.4" => [2.5, 15.0],
  "gpt-5.4-mini" => [0.75, 4.5],
  "gpt-5.4-nano" => [0.2, 1.25]
}.freeze

def model_cost(model_id, input_tokens, output_tokens)
  key = BAKEOFF_PRICES.keys.find { |k| model_id.to_s.start_with?(k) }
  if key
    pin, pout = BAKEOFF_PRICES[key]
    return (input_tokens * pin + output_tokens * pout) / 1_000_000.0
  end

  info = RubyLLM.models.find(model_id)
  return 0.0 unless info&.input_price_per_million && info&.output_price_per_million

  (input_tokens * info.input_price_per_million + output_tokens * info.output_price_per_million) / 1_000_000.0
rescue StandardError
  0.0
end
