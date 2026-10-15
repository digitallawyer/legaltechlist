require "test_helper"

class OutOfScopeStatusRestorerTest < ActiveSupport::TestCase
  test "restores status on scope-hidden records with a working URL, and leaves the hide and everything else alone" do
    restored = companies(:one)
    restored.update_columns(visible: false, status: "inactive", verification_verdict: "out_of_scope_review", url_status: "ok")
    broken = companies(:two)
    broken.update_columns(visible: false, status: "inactive", verification_verdict: "out_of_scope_review", url_status: "broken")

    assert_equal [restored.id], OutOfScopeStatusRestorer.call(dry_run: true)
    assert_equal "inactive", restored.reload.status, "a dry run changes nothing"

    OutOfScopeStatusRestorer.call(dry_run: false)
    restored.reload
    assert_equal "active", restored.status
    assert_not restored.visible?
    assert_equal "lifecycle:restore_out_of_scope_status", restored.quality_review["field_edits"].last["via"]
    assert_equal "inactive", broken.reload.status, "a broken URL is a curator's call"
  end
end
