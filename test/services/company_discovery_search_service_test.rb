require "test_helper"
require "minitest/mock"

class CompanyDiscoverySearchServiceTest < ActiveSupport::TestCase
  StubSearchClient = lambda do |prompt|
    {
      content: {
        "companies" => [
          {
            "name" => "Funded Legal Co",
            "website" => "https://funded-legal.example",
            "location" => "Berlin, Germany",
            "founded_date" => "2021",
            "description" => "Contract review automation for legal teams.",
            "why_discovered" => "Raised Series A in 2024.",
            "funding_round_year" => "2024",
            "funding_round_type" => "Series A",
            "funding_amount_hint" => "$12M"
          }
        ]
      }.to_json,
      search_urls: ["https://funded-legal.example/about"],
      raw_search_call_count: 1
    }
  end

  test "funding_year discovery includes funding hints in company payload" do
    result = CompanyDiscoverySearchService.call(
      discovery_type: "funding_year",
      context: { funding_year: "2024" },
      exclusion_list: { "names" => [], "domains" => [] },
      limit: 5,
      search_client: StubSearchClient
    )

    company = result["companies"].first
    assert_equal "funding_year", company["discovery_type"]
    assert_equal "2024", company["funding_round_year"]
    assert_equal "Series A", company["funding_round_type"]
    assert_equal "$12M", company["funding_amount_hint"]
    assert_equal true, company["website_verified"]
  end

  test "year discovery builds founded-year query" do
    result = CompanyDiscoverySearchService.call(
      discovery_type: "year",
      context: { year: "2024" },
      exclusion_list: { "names" => [], "domains" => [] },
      limit: 5,
      search_client: StubSearchClient
    )

    assert_match(/founded in 2024/, result["query"])
  end

  test "country discovery builds country query" do
    result = CompanyDiscoverySearchService.call(
      discovery_type: "country",
      context: { country: "Germany" },
      exclusion_list: { "names" => [], "domains" => [] },
      limit: 5,
      search_client: StubSearchClient
    )

    assert_match(/headquartered in Germany/, result["query"])
  end

  test "captures controlled-vocab taxonomy and a cited founding-year source" do
    client = lambda do |_prompt|
      {
        content: {
          "companies" => [
            {
              "name" => "Taxo Legal Co",
              "website" => "https://taxo-legal.example",
              "location" => "Paris, France",
              "founded_date" => "2019",
              "description" => "Contract lifecycle management for law firms.",
              "why_discovered" => "matches",
              "category" => "Contract Management",
              "business_models" => ["Subscription"],
              "target_clients" => ["Law Firms"],
              "founded_year_source" => "https://linkedin.example/company/taxo"
            }
          ]
        }.to_json,
        search_urls: ["https://taxo-legal.example/about", "https://linkedin.example/company/taxo"],
        raw_search_call_count: 1
      }
    end

    result = CompanyDiscoverySearchService.call(discovery_type: "category", context: { category: "Contract Management" }, exclusion_list: { "names" => [], "domains" => [] }, limit: 5, search_client: client)
    company = result["companies"].first
    assert_equal "Contract Management", company["category_name"]
    assert_equal ["Subscription"], company["business_model_names"]
    assert_equal ["Law Firms"], company["target_client_names"]
    assert_equal "https://linkedin.example/company/taxo", company["founded_year_source"]
    assert_equal "2019", company["founded_date"], "a cited year should be kept"
  end

  test "captures a secondary category and tags from the discovery payload" do
    client = lambda do |_prompt|
      {
        content: {
          "companies" => [
            {
              "name" => "Multi Legal Co",
              "website" => "https://multi-legal.example",
              "location" => "Amsterdam, Netherlands",
              "description" => "Contract lifecycle management and analytics for corporate legal teams.",
              "why_discovered" => "matches",
              "category" => "Contract Management",
              "secondary_category" => "Analytics & Insights",
              "business_models" => ["Subscription"],
              "target_clients" => ["Corporate Legal"],
              "tags" => ["Redlining", "AI"]
            }
          ]
        }.to_json,
        search_urls: ["https://multi-legal.example/about"],
        raw_search_call_count: 1
      }
    end

    result = CompanyDiscoverySearchService.call(discovery_type: "category", context: { category: "Contract Management" }, exclusion_list: { "names" => [], "domains" => [] }, limit: 5, search_client: client)
    company = result["companies"].first
    assert_equal "Analytics & Insights", company["secondary_category_name"]
    assert_equal ["Redlining", "AI"], company["tag_names"]
  end

  test "drops an uncited founding-year source" do
    client = lambda do |_prompt|
      {
        content: {
          "companies" => [
            { "name" => "NoCite Co", "website" => "https://nocite.example", "description" => "Legal research tools.", "founded_date" => "2015", "category" => "Knowledge & Research", "founded_year_source" => "https://random.example/made-up" }
          ]
        }.to_json,
        search_urls: ["https://nocite.example/about"],
        raw_search_call_count: 1
      }
    end

    result = CompanyDiscoverySearchService.call(discovery_type: "category", context: { category: "Knowledge & Research" }, exclusion_list: { "names" => [], "domains" => [] }, limit: 5, search_client: client)
    company = result["companies"].first
    assert_nil company["founded_year_source"]
    assert_nil company["founded_date"], "an uncited year should be dropped, not stored"
  end

  test "retries once when search returns zero companies" do
    calls = 0
    retry_client = lambda do |_prompt|
      calls += 1
      if calls == 1
        { content: { "companies" => [] }.to_json, search_urls: [], raw_search_call_count: 1 }
      else
        StubSearchClient.call(_prompt)
      end
    end

    result = CompanyDiscoverySearchService.call(
      discovery_type: "year",
      context: { year: "2024" },
      exclusion_list: { "names" => [], "domains" => [] },
      limit: 5,
      search_client: retry_client
    )

    assert_equal 2, calls
    assert_equal true, result["empty_result_retry"]
    assert_equal 1, result["companies"].size
  end

  test "retries the web search on a transient timeout instead of failing the run" do
    calls = 0
    flaky_client = lambda do |_prompt|
      calls += 1
      raise Timeout::Error, "execution expired" if calls == 1

      StubSearchClient.call(_prompt)
    end

    service = CompanyDiscoverySearchService.new(
      discovery_type: "country",
      context: { country: "France" },
      exclusion_list: { "names" => [], "domains" => [] },
      limit: 5,
      search_client: flaky_client
    )

    result = nil
    service.stub(:sleep, nil) { result = service.call }

    assert_equal 2, calls, "should retry once after the transient timeout"
    assert_equal 1, result["companies"].size
    assert_equal "openai_responses_web_search", result["mode"]
  end

  test "gives up after exhausting transient retries and reports the error" do
    calls = 0
    always_timeout = lambda do |_prompt|
      calls += 1
      raise Timeout::Error, "execution expired"
    end

    service = CompanyDiscoverySearchService.new(
      discovery_type: "country",
      context: { country: "France" },
      exclusion_list: { "names" => [], "domains" => [] },
      limit: 5,
      search_client: always_timeout
    )

    result = nil
    service.stub(:sleep, nil) { result = service.call }

    assert_equal 3, calls, "1 initial attempt + 2 retries"
    assert_equal "openai_responses_web_search_error", result["mode"]
  end
end
