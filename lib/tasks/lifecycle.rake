namespace :lifecycle do
  desc "Restore status=active on records hidden by the old scope pass whose URL is ok. DRY_RUN=false to apply"
  task restore_out_of_scope_status: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    ids = OutOfScopeStatusRestorer.call(dry_run: dry_run)
    puts "#{dry_run ? 'Would restore' : 'Restored'} #{ids.size} records to active: #{ids.join(', ')}"
  end
end
