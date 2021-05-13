require 'aws-sdk-sqs'
require 'aws-sdk-s3'
require 'fileutils'
require 'json'

require_relative 'extractor/extraction.rb'
require_relative 'extractor/extraction_status.rb'
require_relative 'extractor/error_type.rb'

class Extractor
  def self.extract(bucket_name, object_key, binary_name, web_id, mime_type)
    begin
      Aws.config[:s3] ={
          endpoint: 'http://minio:9000',
          access_key_id: 'minioadmin',
          secret_access_key: 'minioadmin',
          force_path_style: true,
          region: 'us-east-2'
      }

      status = ExtractionStatus::ERROR
      error = Array.new
      s3_put_status = ExtractionStatus::SUCCESS
      s3_put_error = Array.new

      region = 'elasticmq'
      s3_client = Aws::S3::Client.new

      del_path = "/mnt/efs/#{bucket_name}_#{web_id}"
      local_path = "#{del_path}/#{object_key}"
      s3_path = "messages/#{web_id}.json"

      dirname = File.dirname(local_path)
      unless File.directory?(dirname)
        FileUtils.mkdir_p(dirname)
      end

      begin
        FileUtils.cp(binary_name, local_path)
        puts "Getting object #{object_key} with ID #{web_id} from #{bucket_name}"
      rescue StandardError => e
        s3_error = "Error getting object #{object_key} with ID #{web_id} from S3 bucket #{bucket_name}: #{e.message}"
        error.push({"error_type" => ErrorType::S3_GET, "report" => s3_error})
        puts s3_error
      end

      begin
        extraction = Extraction.new(binary_name, local_path, web_id, mime_type)
        extraction.process
        status = extraction.status
        puts "status: #{status}"
        puts "error: #{extraction.error}" if status == ExtractionStatus::ERROR
        error.concat(extraction.error)
        items = extraction.nested_items.map { |o| Hash[o.each_pair.to_a] }
        errors = error.map {|o| Hash[o.each_pair.to_a]}
        return_value = {"web_id" => web_id, "status" => status, "error" => errors, "peek_type" => extraction.peek_type, "peek_text" => extraction.peek_text, "nested_items" => items}
      rescue
        error.push({"task_id" => web_id, "extraction_process_report" => "Error extracting #{object_key} with ID #{web_id}: #{e.message}"})
        errors = error.map {|o| Hash[o.each_pair.to_a]}
        return_value = {"web_id" => web_id, "status" => ExtractionStatus::ERROR, "error" => errors, "peek_type" => PeekType::NONE, "peek_text" => null, "nested_items" => []}
      end

      begin
        s3_client.put_object({
                                 body: return_value.to_json,
                                 bucket: "databank-local-main",
                                 key: s3_path,
                             })
        puts "Putting json response for object #{object_key} with ID #{web_id} in S3 bucket #{bucket_name} with key #{s3_path}"
      rescue StandardError => e
        s3_put_status = ExtractionStatus::ERROR
        s3_put_error_message = "Error putting json response for object #{object_key} with ID #{web_id} in S3 bucket #{bucket_name}: #{e.message}"
        s3_put_error.push({"error_type" => ErrorType::S3_PUT, "report" => s3_put_error_message})
        puts s3_put_error_message
      end


      s3_put_errors = s3_put_error.map {|o| Hash[o.each_pair.to_a]}
      return_value = {"bucket_name" => bucket_name, "object_key" => s3_path, "s3_status" => s3_put_status, "error" => s3_put_errors}

      endpoint = "http://sqs-mock:9324";
      sqs = Aws::SQS::Client.new(region: region, endpoint: endpoint, access_key_id: 'x', secret_access_key: 'x')

      # Send a message to a queue.
      queue_name = "extractor-to-databank"
      queue_url = "http://sqs-mock:9324/queue/#{queue_name}"

      begin
        # Create and send a message.
        sqs.send_message({
                             queue_url: queue_url,
                             message_body: return_value.to_json,
                             message_attributes: {}
                         })
        puts "Sending message in queue #{queue_name} for object #{object_key} with ID #{web_id}"
      rescue StandardError => e
        puts "Error sending message in queue #{queue_name} for object #{object_key} with ID #{web_id}: #{e.message}"
      end

    ensure
      FileUtils.rm_rf(dirname, :secure => true)
      FileUtils.rm_rf(del_path, :secure => true)

    end
  end

end