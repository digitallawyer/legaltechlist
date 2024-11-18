if Rails.env.production? && ENV['BUCKETEER_AWS_ACCESS_KEY_ID'].present?
  begin
    s3 = Aws::S3::Client.new(
      access_key_id: ENV['BUCKETEER_AWS_ACCESS_KEY_ID'],
      secret_access_key: ENV['BUCKETEER_AWS_SECRET_ACCESS_KEY'],
      region: ENV['BUCKETEER_AWS_REGION']
    )

    # Check if bucket exists first
    s3.head_bucket(bucket: ENV['BUCKETEER_BUCKET_NAME'])

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
  rescue Aws::S3::Errors::ServiceError => e
    Rails.logger.error("Bucketeer CORS configuration failed: #{e.message}")
  rescue StandardError => e
    Rails.logger.error("Unexpected error configuring Bucketeer CORS: #{e.message}")
  end
end
