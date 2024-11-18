if Rails.env.production?
  Rails.application.config.active_storage.service = :bucketeer
else
  Rails.application.config.active_storage.service = :local
end
