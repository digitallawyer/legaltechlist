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
    output = response.raw&.body&.fetch("output", []) || []
    citations = RubyLLM::ResponsesAPI::BuiltInTools.extract_citations(output.flat_map { |item| Array(item["content"]) })
    search_calls = RubyLLM::ResponsesAPI::BuiltInTools.parse_web_search_results(output)

    {
      content: response.content.to_s,
      search_urls: extract_search_urls(citations, search_calls),
      raw_search_call_count: search_calls.size,
      citations: citations,
      search_calls: search_calls,
      response: response
    }
  end

  private

  def chat
    self.class.chat(model: @model, provider: :openai_responses, assume_model_exists: true)
             .with_params(tools: [RubyLLM::ResponsesAPI::BuiltInTools.web_search(search_context_size: @search_context_size)])
  end

  def extract_search_urls(citations, search_calls)
    citation_urls = Array(citations).filter_map { |citation| citation["url"] }
    call_urls = Array(search_calls).flat_map { |call| Array(call[:results] || call["results"]) }.filter_map { |result| result[:url] || result["url"] }
    (citation_urls + call_urls).compact.uniq
  end
end
