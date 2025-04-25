# frozen_string_literal: true
require_relative 'test_helper'

class TestExtraction < Minitest::Test
  Config.load_and_set_settings(Config.setting_files("#{ENV['RUBY_HOME']}/config", 'test'))
  def setup
    binary_name = 'test-binary'
    web_id = 'test-id'
    storage_path = "#{Settings.aws.efs.mount_point}test-bucket_#{web_id}/test-key"
    mime_type = 'application/zip'
    @extraction = Extraction.new(binary_name, storage_path, web_id, mime_type)
  end

  def test_process
    # setup
    @extraction.binary_name = 'test.txt.gz'
    @extraction.storage_path = "#{ENV['RUBY_HOME']}/test/test.txt.gz"
    @extraction.id = 'test-gzip'
    @extraction.mime_type = 'application/gzip'

    # test
    @extraction.process

    # verify
    assert_equal(ExtractionStatus::SUCCESS, @extraction.status)
    assert_equal(PeekType::LISTING, @extraction.peek_type)
  end

  def test_report_problem
    # setup
    report = 'Test report'

    # test
    @extraction.report_problem(report)

    # verify
    error = @extraction.error
    assert_equal(true, error.include?({'error_type' => ErrorType::EXTRACTION, 'report' => report}))
  end

  def test_extract_features_gzip
    # setup
    @extraction.binary_name = 'test.tgz'
    @extraction.storage_path = "#{ENV['RUBY_HOME']}/test/test.tgz"
    @extraction.id = 'test-gzip'
    @extraction.mime_type = 'application/gzip'

    # test
    @extraction.extract_features

    # verify
    assert_equal(PeekType::LISTING, @extraction.peek_type)
    exp_peek_text = "<span class='glyphicon glyphicon-folder-open'></span> test.tgz<div class='indent'><span class='glyphicon glyphicon-file'></span> test.txt</div>"
    assert_equal(exp_peek_text, @extraction.peek_text)
  end

  def test_extract_features_zip
    # setup
    @extraction.binary_name = 'test.zip'
    @extraction.storage_path = "#{ENV['RUBY_HOME']}/test/test.zip"
    @extraction.id = 'test-zip'
    @extraction.mime_type = 'application/zip'

    # test
    @extraction.extract_features

    # verify
    assert_equal(PeekType::LISTING, @extraction.peek_type)
    exp_peek_text = "<span class='glyphicon glyphicon-folder-open'></span> test.zip<div class='indent'><span class='glyphicon glyphicon-file'></span> test.txt</div>"
    assert_equal(exp_peek_text, @extraction.peek_text)
  end

  def test_extract_features_default
    # setup
    @extraction.binary_name = 'test'
    @extraction.storage_path = "#{ENV['RUBY_HOME']}/test"
    @extraction.id = 'test-default'
    @extraction.mime_type = 'application/directory'

    # test
    @extraction.extract_features

    # verify
    assert_equal(PeekType::NONE, @extraction.peek_type)
  end

  def test_mime_from_path
    # setup
    ruby_path = "#{ENV['RUBY_HOME']}/bin/set-test-vars.rb"

    # test
    ruby_mime = @extraction.mime_from_path(ruby_path)

    # verify
    assert_equal('application/x-ruby', ruby_mime)
  end

  def test_mime_from_filename
    # setup
    zip_filename = 'test.zip'

    # test
    zip_mime = @extraction.mime_from_filename(zip_filename)

    # verify
    assert_equal('application/zip', zip_mime)
  end

  def test_create_item
    # setup
    item_path = 'test/item/path/thing'
    item_name = 'thing'
    item_size = 123
    media_type = 'directory'
    is_directory = true

    # test
    @extraction.create_item(item_path, item_name, item_size, media_type, is_directory)

    # verify
    nested_items = @extraction.nested_items
    assert(nested_items.include?({'item_name' => item_name, 'item_path' => item_path, 'item_size' => item_size,
                                  'media_type' => media_type, 'is_directory' => is_directory}))
  end

  def test_extract_zip
    # setup
    @extraction.binary_name = 'test.zip'
    @extraction.storage_path = "#{ENV['RUBY_HOME']}/test/test.zip"
    @extraction.id = 'test-zip'
    @extraction.mime_type = 'application/zip'

    # test
    @extraction.extract_zip

    # verify
    assert_equal(PeekType::LISTING, @extraction.peek_type)
    exp_peek_text = "<span class='glyphicon glyphicon-folder-open'></span> test.zip<div class='indent'><span class='glyphicon glyphicon-file'></span> test.txt</div>"
    assert_equal(exp_peek_text, @extraction.peek_text)
  end

  def test_extract_archive
    # setup
    @extraction.binary_name = 'test.tar'
    @extraction.storage_path = "#{ENV['RUBY_HOME']}/test/test.tar"
    @extraction.id = 'test-tar'
    @extraction.mime_type = 'application/x-tar'
    @extraction.peek_type = nil

    # test
    @extraction.extract_archive

    # verify
    assert_equal(PeekType::LISTING, @extraction.peek_type)
    exp_peek_text = "<span class='glyphicon glyphicon-folder-open'></span> test.tar<div class='indent'><span class='glyphicon glyphicon-file'></span> test.txt</div>"
    assert_equal(exp_peek_text, @extraction.peek_text)
  end

  def test_extract_gzip_tar
    # setup
    @extraction.binary_name = 'test.tgz'
    @extraction.storage_path = "#{ENV['RUBY_HOME']}/test/test.tgz"
    @extraction.id = 'test-gzip'
    @extraction.mime_type = 'application/gzip'

    # test
    @extraction.extract_gzip

    # verify
    assert_equal(PeekType::LISTING, @extraction.peek_type)
    exp_peek_text = "<span class='glyphicon glyphicon-folder-open'></span> test.tgz<div class='indent'><span class='glyphicon glyphicon-file'></span> test.txt</div>"
    assert_equal(exp_peek_text, @extraction.peek_text)
  end

  def test_extract_gzip_not_tar
    # setup
    @extraction.binary_name = 'test.txt.gz'
    @extraction.storage_path = "#{ENV['RUBY_HOME']}/test/test.txt.gz"
    @extraction.id = 'test-gzip'
    @extraction.mime_type = 'application/gzip'

    # test
    @extraction.extract_gzip

    # verify
    assert_equal(PeekType::LISTING, @extraction.peek_type)
    exp_peek_text = "<span class='glyphicon glyphicon-folder-open'></span> test.txt.gz<div class='indent'><span class='glyphicon glyphicon-file'></span> test.txt</div>"
    assert_equal(exp_peek_text, @extraction.peek_text)
  end

  def test_extract_entry
    # setup
    mock_entry = Minitest::Mock.new
    entry_name = "#{ENV['RUBY_HOME']}/bin/set-test-vars.rb"
    type = ExtractionType::GZIP
    mock_entry.expect(:directory?, false)
    mock_entry.expect(:size, 123)

    # test
    entry_paths = @extraction.extract_entry(mock_entry, entry_name, [], type)

    # verify
    assert_mock(mock_entry)
    assert(entry_paths.include?(entry_name))
    expect_item = {'item_name' => 'set-test-vars.rb', 'item_path' => entry_name, 'item_size' => 123,
                   'media_type' => 'application/x-ruby', 'is_directory' => false}
    assert(@extraction.nested_items.include?(expect_item))

  end

  def test_handle_entry_paths
    # setup
    entry_paths = ['test/path']

    # test
    resp = @extraction.handle_entry_paths(entry_paths)

    # verify
    assert(resp)
    exp_peek_text = "<span class='glyphicon glyphicon-folder-open'></span> test-binary<div class='indent'><div class='indent'><span class='glyphicon glyphicon-file'></span> path</div></div>"
    assert_equal(exp_peek_text, @extraction.peek_text)
    assert_equal(PeekType::LISTING, @extraction.peek_type)
  end

  def test_handle_entry_paths_empty
    # setup
    entry_paths = []

    # test
    resp = @extraction.handle_entry_paths(entry_paths)

    # verify
    assert_equal(false, resp)
    assert_equal(PeekType::NONE, @extraction.peek_type)
    assert(@extraction.error.include?({'error_type' => ErrorType::EXTRACTION,
                                       'report' => "no items found for archive listing for task #{@extraction.id}"}))
  end

  def test_extract_default
    # test
    @extraction.extract_default
    # verify
    peek_type = @extraction.peek_type
    assert_equal(PeekType::NONE, peek_type)
  end

  def test_valid_entry_path
    # setup
    valid_path = 'test/path'
    invalid_path = ""

    # test
    path = @extraction.valid_entry_path(valid_path)
    path_slash = @extraction.valid_entry_path("#{valid_path}/")
    path_nil = @extraction.valid_entry_path(invalid_path)

    # verify
    assert_equal(valid_path, path)
    assert_equal(valid_path, path_slash)
    assert_nil(path_nil)
  end

  def test_is_directory
    # setup
    ruby_home = ENV['RUBY_HOME']
    object_path = 'test/path'
    slash_path = 'test/path/'
    mac_path = 'this/is/a/mac/._path'
    ds_store_path = 'test/path/.DS_Store'

    # test
    ruby_home_dir = @extraction.is_directory(ruby_home)
    object_path_dir = @extraction.is_directory(object_path)
    slash_path_dir = @extraction.is_directory(slash_path)
    mac_path_dir = @extraction.is_directory(mac_path)
    ds_store_path_dir = @extraction.is_directory(ds_store_path)

    # verify
    assert_equal(true, ruby_home_dir)
    assert_equal(true, slash_path_dir)
    assert_equal(false, object_path_dir)
    assert_equal(false, mac_path_dir)
    assert_equal(false, ds_store_path_dir)
  end

  def test_is_mac_thing
    # setup
    mac_path = 'this/is/a/mac/path/__MACOSX'
    path = 'this/is/not/a/mac/path'
    # test
    mac = @extraction.is_mac_thing(mac_path)
    not_mac = @extraction.is_mac_thing(path)
    # verify
    assert_equal(true, mac)
    assert_equal(false, not_mac)
  end

  def test_is_mac_tar_thing
    # setup
    mac_path = 'this/is/a/mac/._path'
    paxheader_mac_path = 'PaxHeader/this/is/a/mac/path'
    longlink_mac_path = 'this/is/a/mac/path/@LongLink'
    path = 'this/is/not/a/mac/path'
    # test
    mac_underscore = @extraction.is_mac_tar_thing(mac_path)
    mac_paxheader = @extraction.is_mac_tar_thing(paxheader_mac_path)
    mac_longlink = @extraction.is_mac_tar_thing(longlink_mac_path)
    not_mac = @extraction.is_mac_tar_thing(path)
    # verify
    assert_equal(true, mac_underscore)
    assert_equal(true, mac_paxheader)
    assert_equal(true, mac_longlink)
    assert_equal(false, not_mac)
  end

  def test_ends_in_slash
    # setup
    path_ends_in_slash = 'test/path/'
    path_does_not_end_in_slash = 'test/path'

    # test
    ends_in_slash = @extraction.ends_in_slash(path_ends_in_slash)
    does_not_end_in_slash = @extraction.ends_in_slash(path_does_not_end_in_slash)

    # verify
    assert_equal(true, ends_in_slash)
    assert_equal(false, does_not_end_in_slash)
  end

  def test_is_ds_store
    # setup
    ds_store_path = 'test/path/.DS_Store'
    path = 'test/path'

    # test
    ds_store = @extraction.is_ds_store(ds_store_path)
    not_ds_store = @extraction.is_ds_store(path)

    # verify
    assert_equal(true, ds_store)
    assert_equal(false, not_ds_store)
  end

  def test_name_part
    # setup
    path = 'test/path'
    name = 'test'
    invalid_path = ""

    # test
    path_name = @extraction.name_part(path)
    test_name = @extraction.name_part(name)
    invalid_name = @extraction.name_part(invalid_path)

    # verify
    assert_equal('path', path_name)
    assert_equal('test', test_name)
    assert_nil(invalid_name)
  end

  def test_entry_paths_arr_to_html
    # setup
    entry_paths = ['test/path']

    # test
    return_string = @extraction.entry_paths_arr_to_html(entry_paths)

    # verify
    exp_peek_text = "<span class='glyphicon glyphicon-folder-open'></span> test-binary<div class='indent'><div class='indent'><span class='glyphicon glyphicon-file'></span> path</div></div>"
    assert_equal(exp_peek_text, return_string)
  end
end
