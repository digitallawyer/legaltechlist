require "timeout"

# Single entry point for OpenAI Responses API web-search calls. Centralizes the
# provider/tool construction and citation/result extraction that used to be
# triplicated across discovery, proposal research, founded-year research, and
# enrichment. Callers pass their own model (so per-task model routing stays with the
# caller) and receive a normalized hash of the text content plus the citations/search
# results the model actually saw (used for cite-only gating and evidence hosts).
class WebSearchAgent < RubyLLM::Agent
  DEFAULT_TIMEOUT_SECONDS = 180

  def self.search(prompt, model:, timeout: DEFAULT_TIMEOUT_SECONDS, search_context_size: "medium")
    new(model: model, timeout: timeout, search_context_size: search_context_size).search(prompt)
  end

  def initialize(model:, timeout: DEFAULT_TIMEOUT_SECONDS, search_context_size: "medium")
    @model = model
    @timeout = timeout.to_i
    @search_context_size = search_context_size
  end

  def search(prompt)
    response = Timeout.timeout(@timeout) { chat.ask(prompt) }
    citations = Array(response.citations).map { |citation| { "url" => citation.url, "title" => citation.title, "text" => citation.cited_text }.compact }
    search_calls = Array(response.server_tool_calls).select { |call| call.type.to_s.include?("web_search") || call.name.to_s == "web_search" }.map do |call|
      { type: call.type, query: query_of(call.input), results: sources_in(call.raw) }
    end

    {
      content: response.content.to_s,
      search_urls: extract_search_urls(citations, search_calls),
      raw_search_call_count: search_calls.count { |call| call[:type].to_s.match?(/web_search_call|server_tool_use/) || call[:results].empty? },
      citations: citations,
      search_calls: search_calls,
      response: response
    }
  end

  private

  # OpenAI Responses is RubyLLM 2's default for OpenAI models; web search is a named provider tool.
  def chat
    self.class.chat(model: @model, provider: :openai, assume_model_exists: true)
             .with_provider_tools(web_search: { search_context_size: @search_context_size })
  end

  def query_of(input)
    input.is_a?(Hash) ? (input["query"] || input[:query]) : input
  end

  # Every { url:, title: } the provider put in a search step, wherever it nests them.
  def sources_in(node, found = [])
    case node
    when Hash
      url = node["url"] || node[:url]
      found << { url: url, title: node["title"] || node[:title] } if url.is_a?(String) && url.start_with?("http")
      node.each_value { |value| sources_in(value, found) }
    when Array
      node.each { |value| sources_in(value, found) }
    end
    found.uniq
  end

  def extract_search_urls(citations, search_calls)
    citation_urls = Array(citations).filter_map { |citation| citation["url"] }
    call_urls = Array(search_calls).flat_map { |call| Array(call[:results] || call["results"]) }.filter_map { |result| result[:url] || result["url"] }
    (citation_urls + call_urls).compact.uniq
  end
end
