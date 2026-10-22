# What every agent does with a model response besides reading it: name the model that
# answered, count tokens, price the call, and tell RubyLLM about a model its registry does
# not list yet. Written once, on RubyLLM 2's own readers (response.tokens, response.cost),
# instead of copied into each agent.
module LlmResponseSupport
  private

  def response_model(response, requested)
    response.model.to_s.presence || requested
  end

  def usage_payload(response)
    tokens = response.tokens
    {
      "input_tokens" => tokens&.input,
      "output_tokens" => tokens&.output,
      "cached_tokens" => tokens&.cache_read,
      "cache_creation_tokens" => tokens&.cache_write,
      "thinking_tokens" => tokens&.thinking,
      "total_tokens" => [tokens&.input, tokens&.output].compact.sum
    }
  end

  # Dollars for this call at the registry's price, or nil when the registry has none.
  def estimated_cost(response)
    response.cost&.total&.round(8)
  rescue StandardError
    nil
  end

  def unknown_model?(model_id)
    RubyLLM.models.find(model_id)
    false
  rescue RubyLLM::ModelNotFoundError
    true
  end
end
