# Carries the queue a reviewer came from through the record and back again, so
# finishing one record returns them to the same filtered, sorted, paginated list
# instead of the default view they then have to rebuild.
#
# The state travels as an allowlisted set of query params under `queue`, never as a
# raw return URL: a redirect target taken from a request parameter is an open-redirect
# waiting to happen, and rebuilding the path from permitted values cannot leave the app.
module ReviewQueueContext
  extend ActiveSupport::Concern

  # Every filter, sort and page key either queue understands. Anything else is dropped.
  QUEUE_KEYS = %i[
    q status visibility category_id business_model_id target_client_id
    review_state review_signal updated_since sort page
  ].freeze

  included do
    # Row links are built in the view, so the list's own state has to be reachable there.
    helper_method :queue_context
  end

  # The state of the list currently being rendered, for embedding in row links.
  def queue_context
    @queue_context ||= request.query_parameters.symbolize_keys.slice(*QUEUE_KEYS).compact_blank
  end

  # The state handed back by a record, for redirecting after an action.
  def returning_queue_context
    @returning_queue_context ||= begin
      raw = params[:queue]
      raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h.symbolize_keys.slice(*QUEUE_KEYS).compact_blank : {}
    end
  end

  def came_from_queue?
    returning_queue_context.any?
  end

  # Where to send the reviewer once they are done with a record. The caller supplies
  # the right tab's list path; this puts their filters back on it. Falls back to the
  # bare default when they reached the record directly rather than from a list.
  def queue_redirect_path(default_path)
    return default_path unless came_from_queue?

    "#{default_path.split('?').first}?#{returning_queue_context.to_query}"
  end
end
