require 'aws-sdk-s3'

Aws.config[:credentials] = Aws::Credentials.new(
  ENV['BUCKETEER_AWS_ACCESS_KEY_ID'],
  ENV['BUCKETEER_AWS_SECRET_ACCESS_KEY']
)
Aws.config[:region] = ENV['BUCKETEER_AWS_REGION'] || 'us-east-1'

S3 = Aws::S3::Client.new