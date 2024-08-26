# frozen_string_literal: true
require 'aws-sdk-sqs'
require 'aws-sdk-s3'
require 'fileutils'
require 'json'
require 'config'
require 'logger'


require_relative 'extractor/extraction'
require_relative 'extractor/extraction_status'
require_relative 'extractor/error_type'

class ArchiveExtractor
  attr_accessor :s3, :sqs, :bucket_name, :object_key, :binary_name, :web_id, :mime_type, :extraction
  Config.load_and_set_settings(Config.setting_files("#{ENV['RUBY_HOME']}/config", ENV['RUBY_ENV']))
  STDOUT.sync = true
  LOGGER = Logger.new(STDOUT)
  GIGABYTE = 2**30

  def initialize(bucket_name, object_key, binary_name, web_id, mime_type, sqs, s3)
    @bucket_name = bucket_name
    @object_key = object_key
    @binary_name = binary_name
    @web_id = web_id
    @mime_type = mime_type
    @sqs = sqs
    @s3 = s3
  end

  def extract
    begin
      error = []

      storage_path = get_storage_path
      LOGGER.info("Storage path: #{storage_path}")
      del_path = "#{storage_path}#{@bucket_name}_#{@web_id}"
      local_path = "#{del_path}/#{@object_key}"

      dirname = File.dirname(local_path)
      unless File.directory?(dirname)
        FileUtils.mkdir_p(dirname)
      end

      get_object(local_path, error)

      extraction = Extraction.new(@binary_name, local_path, @web_id, @mime_type)
      extraction_return_value = perform_extraction(extraction, error)
      s3_path = "messages/#{@web_id}.json"
      s3_put_status, s3_put_error = put_json_response(extraction_return_value, s3_path)

      s3_put_errors = s3_put_error.map {|o| Hash[o.each_pair.to_a]}

      s3_message = {"bucket_name" => @bucket_name, "object_key" => s3_path, "s3_status" => s3_put_status, "error" => s3_put_errors}
      send_sqs_message(s3_message)

    ensure
      FileUtils.rm_rf(dirname, :secure => true)
      FileUtils.rm_rf(del_path, :secure => true)
    end
  end

  def get_storage_path
    resp = @s3.get_object_attributes({
                                       bucket: @bucket_name,
                                       key: @object_key,
                                       object_attributes: ['ObjectSize']
                                     })
    object_size = resp.object_size
    LOGGER.info("#{@web_id} size:  #{object_size}")
    object_size > 15 * GIGABYTE ? Settings.aws.efs.mount_point : Settings.ephemeral_storage_path
  end

  def get_object(local_path, error)
    begin
      @s3.get_object({
                      response_target: local_path,
                      bucket: @bucket_name,
                      key: @object_key,
                     })
      LOGGER.info("Getting object #{@object_key} with ID #{@web_id} from #{@bucket_name}")
    rescue StandardError => e
      s3_error = "Error getting object #{@object_key} with ID #{@web_id} from S3 bucket #{@bucket_name}: #{e.message}"
      LOGGER.error(s3_error)
      error.push({"error_type" => ErrorType::S3_GET, "report" => s3_error})
    end
    return error
  end

  def perform_extraction(extraction, error)
    begin
      extraction.process
      status = extraction.status
      LOGGER.info("status: #{status}")
      LOGGER.error("error: #{extraction.error}") if status == ExtractionStatus::ERROR
      error.concat(extraction.error)
      items = extraction.nested_items.map { |o| Hash[o.each_pair.to_a] }
      errors = error.map {|o| Hash[o.each_pair.to_a]}
      extraction_return_value = {"web_id" => @web_id, "status" => status, "error" => errors, "peek_type" => extraction.peek_type, "peek_text" => extraction.peek_text, "nested_items" => items}
    rescue  StandardError => e
      error.push({"task_id" => @web_id, "extraction_process_report" => "Error extracting #{@object_key} with ID #{@web_id}: #{e.message}"})
      errors = error.map {|o| Hash[o.each_pair.to_a]}
      extraction_return_value = {"web_id" => @web_id, "status" => ExtractionStatus::ERROR, "error" => errors, "peek_type" => PeekType::NONE, "peek_text" => nil, "nested_items" => []}
    end
    return extraction_return_value
  end

  def send_sqs_message(s3_message)
    # Send a message to a queue.
    queue_name = Settings.aws.sqs.queue_name
    queue_url = Settings.aws.sqs.queue_url

    begin
      # Create and send a message.
      @sqs.send_message({
                          queue_url: queue_url,
                          message_body: s3_message.to_json,
                          message_attributes: {}
                        })
      LOGGER.info("Sending message in queue #{queue_name} for object #{@object_key} with ID #{@web_id}")
    rescue StandardError => e
      LOGGER.error("Error sending message in queue #{queue_name} for object #{@object_key} with ID #{@web_id}: #{e.message}")
    end
  end

  def put_json_response(extraction_return_value, s3_path)
    s3_put_error = []
    json_bucket = Settings.aws.s3.json_bucket
    begin
      @s3.put_object({
                       body: extraction_return_value.to_json,
                       bucket: json_bucket,
                       key: s3_path,
                     })
      LOGGER.info(extraction_return_value.to_json)
      LOGGER.info("Putting json response for object #{@object_key} with ID #{@web_id} in S3 bucket #{json_bucket} with key #{s3_path}")
      s3_put_status = ExtractionStatus::SUCCESS
    rescue StandardError => e
      s3_put_status = ExtractionStatus::ERROR
      s3_put_error_message = "Error putting json response for object #{@object_key} with ID #{@web_id} in S3 bucket #{json_bucket}: #{e.message}"
      s3_put_error.push({"error_type" => ErrorType::S3_PUT, "report" => s3_put_error_message})
      LOGGER.error(s3_put_error_message)
    end
    return s3_put_status, s3_put_error
  end


end
