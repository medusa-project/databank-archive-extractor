require 'aws-sdk-sqs'
require 'aws-sdk-s3'
require 'config'

require_relative 'archive_extractor'

class Extractor
  Config.load_and_set_settings(Config.setting_files("#{ENV['RUBY_HOME']}/config", ENV['RUBY_ENV']))

  def self.extract(bucket_name, object_key, binary_name, web_id, mime_type)
    region = Settings.aws.region
    s3_client = Aws::S3::Client.new(region: region)
    s3_resource = Aws::S3::Resource.new(client: s3_client)
    sqs = Aws::SQS::Client.new(region: region)
    archive_extractor = ArchiveExtractor.new(bucket_name, object_key, binary_name, web_id, mime_type, sqs, s3_client, s3_resource)
    archive_extractor.extract
  end

end