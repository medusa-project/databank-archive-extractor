# frozen_string_literal: true
require_relative 'test_helper'

class TestArchiveExtractor < Minitest::Test
  Config.load_and_set_settings(Config.setting_files("#{ENV['RUBY_HOME']}/config", 'test'))
  def setup
    bucket_name = 'test-bucket'
    object_key = 'test-key'
    binary_name = 'test'
    web_id = 'test-id'
    mime_type = 'application/zip'
    @sqs = Minitest::Mock.new
    @s3 = Minitest::Mock.new
    @archive_extractor = ArchiveExtractor.new(bucket_name, object_key, binary_name, web_id, mime_type, @sqs, @s3)
  end

  def test_extract
    # setup
    @archive_extractor.binary_name = 'test.zip'
    @archive_extractor.web_id = 'test-zip'
    @archive_extractor.mime_type = 'application/zip'
    @archive_extractor.object_key = 'test.zip'
    del_path = "#{Settings.aws.efs.mount_point}#{@archive_extractor.bucket_name}_#{@archive_extractor.web_id}"
    local_path = "#{del_path}/#{@archive_extractor.object_key}"
    file_path = "#{ENV['RUBY_HOME']}/test/test.zip"
    dirname = File.dirname(local_path)
    unless File.directory?(dirname)
      FileUtils.mkdir_p(dirname)
    end
    FileUtils.cp(file_path, local_path)
    @s3.expect(:get_object, nil, [{response_target: local_path, bucket: @archive_extractor.bucket_name,
                                                   key: @archive_extractor.object_key}])
    peek_text = "<span class='glyphicon glyphicon-folder-open'></span> test.zip<div class='indent'><span class='glyphicon glyphicon-file'></span> test.txt</div>"
    items = [{'item_name' => 'test.txt', 'item_path' => 'test.txt', 'item_size' => 12, 'media_type' => 'text/plain', 'is_directory' => false}]
    return_value = {'web_id' => 'test-zip', 'status' => ExtractionStatus::SUCCESS, 'error' => [], 'peek_type' => PeekType::LISTING, 'peek_text' => peek_text, 'nested_items' => items}
    s3_path = 'messages/test-zip.json'
    @s3.expect(:put_object, [], [{body: return_value.to_json, bucket: Settings.aws.s3.json_bucket, key: s3_path}])
    return_value = {'bucket_name' => 'test-bucket', 'object_key' => s3_path, 's3_status' => ExtractionStatus::SUCCESS, 'error' => []}
    @sqs.expect(:send_message, nil, [{queue_url: Settings.aws.sqs.queue_url,
                                      message_body: return_value.to_json,
                                      message_attributes:{}}])

    # test
    @archive_extractor.extract

    # verify
    assert_mock(@s3)
    assert_mock(@sqs)
  end

  def test_get_object
    # setup
    local_path = 'test/path'
    @s3.expect(:get_object, nil, [{response_target: local_path, bucket: @archive_extractor.bucket_name,
                                                    key: @archive_extractor.object_key}])
    # test
    error = @archive_extractor.get_object(local_path, [])

    # verify
    assert_mock(@s3)
    assert_empty(error)
  end

  def test_get_object_error
    # setup
    stub_s3 = Aws::S3::Client.new(region: Settings.aws.region)
    @archive_extractor.s3 = stub_s3
    local_path = "test/path"
    raises_exception = -> { raise StandardError.new }

    # test and verify
    stub_s3.stub :get_object, raises_exception do
      error = @archive_extractor.get_object(local_path, [])
      assert(error.first.value?(ErrorType::S3_GET))
    end
  end

  def test_perform_extraction
    # setup
    binary_name = 'test.zip'
    web_id = 'test-zip'
    mime_type = 'application/zip'
    local_path = "#{ENV['RUBY_HOME']}/test/test.zip"
    extraction = Extraction.new(binary_name, local_path, web_id, mime_type)

    #test
    return_value = @archive_extractor.perform_extraction(extraction, [])

    # verify
    assert(return_value.value?(PeekType::LISTING))
    exp_peek_text = "<span class='glyphicon glyphicon-folder-open'></span> test.zip<div class='indent'><span class='glyphicon glyphicon-file'></span> test.txt</div>"
    assert(return_value.value?(exp_peek_text))

  end

  def test_perform_extraction_error
    # setup
    binary_name = 'test.zip'
    web_id = 'test-zip'
    mime_type = 'application/zip'
    local_path = "#{ENV['RUBY_HOME']}/test/test.zip"
    stub_extraction = Extraction.new(binary_name, local_path, web_id, mime_type)
    raises_exception = -> { raise StandardError.new }

    # test and verify
    stub_extraction.stub :process, raises_exception do
      return_value = @archive_extractor.perform_extraction(stub_extraction, [])
      assert(return_value.value?(PeekType::NONE))
      assert(return_value.value?(ExtractionStatus::ERROR))
    end
  end

  def test_send_sqs_message
    # setup
    return_value = {'test' => 'retVal'}
    @sqs.expect(:send_message, nil, [{queue_url: Settings.aws.sqs.queue_url,
                                                      message_body: return_value.to_json,
                                                      message_attributes:{}}])

    # test
    @archive_extractor.send_sqs_message(return_value)

    # verify
    assert_mock(@sqs)
  end

  def test_put_json_response
    # setup
    return_value = {'test' => 'retVal'}
    s3_path = 'test/s3/key'
    @s3.expect(:put_object, nil, [{body: return_value.to_json, bucket: Settings.aws.s3.json_bucket, key: s3_path}])

    # test
    s3_put_status, s3_put_error = @archive_extractor.put_json_response(return_value, s3_path)

    # verify
    assert_mock(@s3)
    assert_equal(ExtractionStatus::SUCCESS, s3_put_status)
    assert_empty(s3_put_error)
  end

  def test_put_json_response_error
    # setup
    return_value = {'test' => 'error'}
    s3_path = 'test/s3/error'
    stub_s3 = Aws::S3::Client.new(region: Settings.aws.region)
    @archive_extractor.s3 = stub_s3
    raises_exception = -> { raise StandardError.new }

    # test and verify
    stub_s3.stub :put_object, raises_exception do
      s3_put_status, s3_put_error = @archive_extractor.put_json_response(return_value, s3_path)
      assert_equal(ExtractionStatus::ERROR, s3_put_status)
      assert(!s3_put_error.empty?)
    end
  end
end

