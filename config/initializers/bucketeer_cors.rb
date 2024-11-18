if Rails.env.production?
  s3 = Aws::S3::Client.new(
    access_key_id: ENV['BUCKETEER_AWS_ACCESS_KEY_ID'],
    secret_access_key: ENV['BUCKETEER_AWS_SECRET_ACCESS_KEY'],
    region: ENV['BUCKETEER_AWS_REGION']
  )

  # Configure CORS
  s3.put_bucket_cors(
    bucket: ENV['BUCKETEER_BUCKET_NAME'],
    cors_configuration: {
      cors_rules: [
        {
          allowed_headers: ["*"],
          allowed_methods: ["GET"],
          allowed_origins: ["*"],
          expose_headers: ["ETag"],
          max_age_seconds: 3600
        }
      ]
    }
  )
rescue => e
  Rails.logger.error("Failed to configure Bucketeer CORS: #{e.message}")
end
