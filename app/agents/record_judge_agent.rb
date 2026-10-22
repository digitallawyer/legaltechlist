require "timeout"

# Decides, from what the server read on a company's own site and nothing else, whether the
# company belongs in the index, and writes its entry. Toolless and schema-bound: the model
# has no way to fetch, so it cannot misread a page it never saw; RecordJudgeService does the
# fetching, the quote check and the bookkeeping.
class RecordJudgeAgent < RubyLLM::Agent
  include LlmResponseSupport
  model "gpt-5.4-mini"
  instructions
  schema RecordJudgeSchema

  DEFAULT_MODEL = "gpt-5.4-mini".freeze

  def self.default_model = ENV.fetch("RUBYLLM_JUDGE_MODEL", DEFAULT_MODEL)

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(company:, pages:, model: nil, feedback: nil)
    @company = company
    @pages = pages
    @feedback = feedback
    @model = model.presence || self.class.default_model
  end

  def call
    provider = model.start_with?("claude") ? :anthropic : :openai
    chat = self.class.chat(model: model, provider: provider, assume_model_exists: unknown_model?(model))
    response = Timeout.timeout(ENV.fetch("RECORD_JUDGE_TIMEOUT_SECONDS", "90").to_i) { chat.ask(prompt) }
    parsed = response.parsed || JSON.parse(response.content.to_s[/\{.*\}/m].to_s)
    parsed.merge("model" => response_model(response, model),
                 "usage" => usage_payload(response).slice("input_tokens", "output_tokens", "cached_tokens"),
                 "cost_usd" => estimated_cost(response))
  rescue StandardError => e
    Rails.logger.warn("[RecordJudgeAgent] #{model} failed: #{e.class}: #{e.message}")
    nil
  end

  private

  attr_reader :company, :pages, :model, :feedback

  def prompt
    {
      record: { name: company.name, website: company.main_url },
      pages: pages.map do |page|
        { url: page[:url], final_url: page[:final_url], fetched: page.fetch(:fetched, true), renders_text: page[:renders_text], title: page[:title], meta_description: page[:meta_description], text: page[:text].to_s.first(3500) }
      end,
      feedback_on_your_previous_answer: feedback
    }.compact.to_json
  end

end
