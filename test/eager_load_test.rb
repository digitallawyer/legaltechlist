require "test_helper"

# Production eager-loads app/. The test and development environments do not, so a constant
# that no longer exists (RubyLLM 2 removed acts_as_model) loads fine everywhere except the one
# place that matters, and takes every dyno down at boot. This loads everything.
class EagerLoadTest < ActiveSupport::TestCase
  test "every application constant loads" do
    assert_nothing_raised { Rails.application.eager_load! }
  end
end
