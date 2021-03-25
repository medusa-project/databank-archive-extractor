require 'aws-sdk-sqs'
require 'aws-sdk-s3'
require 'fileutils'
require 'json'

require_relative 'extractor/extraction.rb'
require_relative 'extractor/extraction_status.rb'

class Extractor
  def self.extract(bucket_name, object_key, binary_name, web_id)
    begin

      region = 'us-east-2'
      s3_client = Aws::S3::Client.new(region: region)
      del_path = "./mnt/efs/#{bucket_name}_#{web_id}"
      local_path = "#{del_path}/#{object_key}"

      dirname = File.dirname(local_path)
      unless File.directory?(dirname)
        FileUtils.mkdir_p(dirname)
      end

      begin
        s3_client.get_object(
            response_target: local_path,
            bucket: bucket_name,
            key: object_key,
        )
        puts "Getting object #{object_key} from #{bucket_name}"
      rescue StandardError => e
        puts "Error getting object #{object_key} from S3 bucket #{bucket_name}: #{e.message}"
      end

      extraction = Extraction.new(binary_name, local_path, web_id)
      extraction.process
      puts "status: #{extraction.status}"
      puts "error: #{extraction.error}" if extraction.error == ExtractionStatus::ERROR
      items = extraction.nested_items.map { |o| Hash[o.each_pair.to_a] }
      retVal = {"web_id" => web_id, "status" => extraction.status, "error" => extraction.error, "peek_type" => extraction.peek_type, "peek_text" => extraction.peek_text, "nested_items" => items}


      s3_path = "messages/#{web_id}.json"
      begin
        s3_client.put_object({
             body: retVal.to_json,
             bucket: "databank-demo-main",
             key: s3_path,
         })
        puts "Putting json response for object #{object_key} in S3 bucket #{bucket_name} with key #{s3_path}"
      rescue StandardError => e
        puts "Error putting json response for object #{object_key} in S3 bucket #{bucket_name}: #{e.message}"
      end

      retVal = {"bucket_name" => bucket_name, "object_key" => s3_path}

      sqs = Aws::SQS::Client.new(region: region)

      # Send a message to a queue.
      queue_name = "extractor-to-databank-demo"
      queue_url = sqs.get_queue_url(queue_name: queue_name).queue_url

      begin
        # Create and send a message.
        sqs.send_message({
           queue_url: queue_url,
           message_body: retVal.to_json,
           message_attributes: {}
         })
        puts "Sending message in queue #{queue_name} for object #{object_key}"
      rescue StandardError => e
      puts "Error sending message in queue #{queue_name} for object #{object_key}: #{e.message}"
      end


    ensure
      FileUtils.rm_rf(dirname, :secure => true)
      FileUtils.rm_rf(del_path, :secure => true)

    end
   end

end