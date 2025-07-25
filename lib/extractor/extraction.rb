require 'json'
require 'os'
require 'mime/types'
require 'mimemagic'
require 'mimemagic/overlay'
require 'zip'
require 'zlib'
require 'ffi-libarchive'
require 'rubygems/package'
require 'config'
require 'logger'
require 'ruby-filemagic'

require_relative 'extraction_status'
require_relative 'extraction_type'
require_relative 'peek_type'
require_relative 'error_type'
require_relative 'mime_type'

class Extraction

  attr_accessor :binary_name, :storage_path, :status, :peek_type, :peek_text, :id, :nested_items, :error, :mime_type
  ALLOWED_CHAR_NUM = 1024 * 8
  ALLOWED_DISPLAY_BYTES = ALLOWED_CHAR_NUM * 8
  STDOUT.sync = true
  LOGGER = Logger.new(STDOUT)
  def initialize(binary_name, storage_path, id, mime_type)
    @binary_name = binary_name
    @storage_path = storage_path
    @id = id
    @mime_type = mime_type
    @nested_items = []
    @error = []
  end

  def process
    begin
      features_extracted = extract_features
      if features_extracted
        @status = ExtractionStatus::SUCCESS
      else
        @status = ExtractionStatus::ERROR
      end
    rescue StandardError => error
      @status = ExtractionStatus::ERROR
      @peek_type = PeekType::NONE
      report_problem(error.message)
    ensure
      if @peek_text && @peek_text.encoding.name != 'UTF-8'
        begin
          @peek_text.encode('UTF-8')
        rescue Encoding::UndefinedConversionError
          @peek_text = nil
          @peek_type = PeekType::NONE
          report_problem('invalid encoding for peek text')
        rescue Exception => ex
          report_problem("invalid encoding and problem character: #{ex.class}, #{ex.message}")
        end
      end
    end
  end

  def report_problem(report)
    @error.push({"error_type" => ErrorType::EXTRACTION, "report" => report})
  end

  def extract_features
    mime_parts = @mime_type.split("/")
    subtype = mime_parts[1].downcase

    if MimeType::ZIP.include?(subtype)
      return extract_zip
    elsif MimeType::NON_ZIP_ARCHIVE.include?(subtype)
      return extract_archive
    elsif MimeType::GZIP.include?(subtype)
      return extract_gzip
    else
      return extract_default
    end
  end


  def mime_from_path(path)
    file = File.open("#{path}")
    file_mime_response = MimeMagic.by_path(file).to_s
    file.close

    if file_mime_response.length > 0
      file_mime_response
    else
      file_mime_response = `file --mime -b "#{path}"`
      if file_mime_response
        response_parts = file_mime_response.split(";")
        return response_parts[0]
      else
        nil
      end
    end
  end

  def mime_from_filename(filename)
    mime_type = MIME::Types.type_for(filename).first
    mime_guesses = mime_type.nil? ? nil : mime_type.content_type
    if mime_guesses.nil? || mime_guesses.empty?
      nil
    else
      mime_guesses
    end
  end

  def create_item(item_path, item_name, item_size, media_type, is_directory)
    item = {"item_name" => item_name, "item_path" => item_path, "item_size" => item_size, "media_type" => media_type,
            "is_directory" => is_directory}
    @nested_items.push(item)
  end

  def extract_zip
    begin
      LOGGER.info("Extracting zip file #{@binary_name}")
      entry_paths = []
      Zip::File.open(@storage_path) do |zip_file|
        zip_file.each do |entry|
          if entry.name_safe?
            entry_paths = extract_entry(entry, entry.name, entry_paths, ExtractionType::ZIP)
          end
        end
      end
      handle_entry_paths(entry_paths)
      return true
    rescue StandardError => ex
      @status = ExtractionStatus::ERROR
      @peek_type = PeekType::NONE
      report_problem("problem extracting zip listing for task: #{ex.message}")
      #return false
      raise ex
    end
  end

  def extract_archive
    begin
      LOGGER.info("Extracting archive file #{@binary_name}")
      entry_paths = []
      Archive.read_open_filename(@storage_path) do |ar|
        while entry = ar.next_header
          entry_paths = extract_entry(entry, entry.pathname, entry_paths, ExtractionType::ARCHIVE)
        end
      end
      handle_entry_paths(entry_paths)
    rescue Archive::Error => e
      LOGGER.error("Archive Error: #{e}")
      @status = ExtractionStatus::ERROR
      @peek_type = PeekType::NONE
      report_problem("problem extracting archive listing for task #{@id}: #{e.message}")
      return false
    rescue StandardError => ex
      LOGGER.error(ex)
      @status = ExtractionStatus::ERROR
      @peek_type = PeekType::NONE
      report_problem("problem extracting archive listing for task #{@id}: #{ex.message}")
      return false
    end
  end

  def extract_gzip
    begin
      LOGGER.info("Extracting gzip file #{@binary_name}")
      entry_paths = []
      gzip_extract = Zlib::GzipReader.open(@storage_path)
      extracted_mime = FileMagic.new(FileMagic::MAGIC_MIME).buffer(gzip_extract.readline)
      mime_parts = extracted_mime.split(";")[0].split("/")
      subtype = mime_parts[1].downcase
      gzip_extract.rewind
      if MimeType::TAR.include?(subtype)
        LOGGER.info("Processing tar gzip #{@binary_name}")
        begin
          tar_extract = Gem::Package::TarReader.new(gzip_extract)
          tar_extract.rewind # The extract has to be rewound after every iteration
          tar_extract.each do |entry|
            entry_paths = extract_entry(entry, entry.full_name, entry_paths, ExtractionType::GZIP)
          end

        ensure
          tar_extract.close
        end
      else
        LOGGER.info("Processing non tar gzip #{@binary_name}")
        entry_name = gzip_extract.orig_name
        entry_path = valid_entry_path(entry_name)
        if entry_path && !is_ds_store(entry_path) && !is_mac_thing(entry_path) && !is_mac_tar_thing(entry_path)
          entry_paths << entry_path
          gzip_extract.readpartial((1024**2)*400) while !gzip_extract.eof?
          entry_size = gzip_extract.tell
          mime_guess = mime_from_filename(entry_name) || 'application/octet-stream'
          create_item(entry_path,
                      name_part(entry_path),
                      entry_size,
                      mime_guess,
                      false)
        end
      end
      handle_entry_paths(entry_paths)

    rescue StandardError => ex
      @status = ExtractionStatus::ERROR
      @peek_type = PeekType::NONE

      report_problem("problem extracting gzip listing for task #{@id}: #{ex.message}")
      return false
    end
  ensure
    gzip_extract.close
  end

  def extract_entry(entry, entry_name, entry_paths, type)
    entry_path = valid_entry_path(entry_name)
    if entry_path && !is_ds_store(entry_path) && !is_mac_thing(entry_path) && !is_mac_tar_thing(entry_path)
      entry_paths << entry_path
      if entry.directory? || is_directory(entry_name)
        create_item(entry_path,
                    name_part(entry_path),
                    entry.size,
                    'directory',
                    true)
      else
        storage_dir = File.dirname(@storage_path)
        extracted_entry_path = File.join(storage_dir, entry_path)
        extracted_entry_dir = File.dirname(extracted_entry_path)
        FileUtils.mkdir_p extracted_entry_dir

        raise Exception.new("extracted entry somehow already there?!!?!") if File.exist?(extracted_entry_path)

        file = nil
        case type
        when ExtractionType::ZIP
          entry.extract(extracted_entry_path)
        else
          file = File.open(extracted_entry_path, 'wb')
        end
        raise("extracting #{type} entry not working!") unless File.exist?(extracted_entry_path)

        mime_guess = mime_from_path(extracted_entry_path) ||
          mime_from_filename(entry_name) ||
          'application/octet-stream'

        create_item(entry_path,
                    name_part(entry_path),
                    entry.size,
                    mime_guess,
                    false)
        file.close if file
        File.delete(extracted_entry_path) if File.exist?(extracted_entry_path)
      end
    end
    entry_paths
  end

  def handle_entry_paths(entry_paths)
    if entry_paths.length > 0
      @peek_type = PeekType::LISTING
      @peek_text = entry_paths_arr_to_html(entry_paths)
      return true
    else
      @peek_type = PeekType::NONE
      report_problem("no items found for archive listing for task #{@id}")
      return false
    end
  end

  def extract_default
    LOGGER.info("Default extraction for #{@binary_name}")
    begin
      @peek_type = PeekType::NONE
      return true
    rescue StandardError => ex
      @status = ExtractionStatus::ERROR
      @peek_type = PeekType::NONE
      report_problem("problem creating default peek for task #{@id}: #{ex}")
      return false
    end
  end

  def valid_entry_path(entry_path)
    if ends_in_slash(entry_path)
      return entry_path[0...-1]
    elsif entry_path.length > 0
      return entry_path
    end
  end

  def is_directory(path)
    File.directory?(path) || (ends_in_slash(path) && !is_ds_store(path) && !is_mac_thing(path))
  end

  def is_mac_thing(path)
    entry_parts = path.split('/')
    entry_parts.include?('__MACOSX')
  end

  def is_mac_tar_thing(path)
    entry_parts = path.split('/')
    entry_parts[-1].chars.first(2).join == '._' || entry_parts.include?('PaxHeader') || entry_parts.include?('@LongLink')
  end

  def ends_in_slash(path)
    return path[-1] == '/' || path[-1] =='\\'
  end

  def is_ds_store(path)
    name_part(path).strip() == '.DS_Store'
  end

  def name_part(path)
    valid_path = valid_entry_path(path)
    if valid_path
      entry_parts = valid_path.split('/')
      if entry_parts.length > 1
        entry_parts[-1]
      else
        valid_path
      end
    end
  end

  def entry_paths_arr_to_html(entry_paths)
    return_string = '<span class="glyphicon glyphicon-folder-open"></span> '

    return_string << @binary_name

    entry_paths.each do |entry_path|

      if !(entry_path.include? '__MACOSX') && !(entry_path.include? '.DS_Store')

        name_arr = entry_path.split("/")

        name_arr.length.times do
          return_string << '<div class="indent">'
        end

        if entry_path[-1] == "/" # means directory
          return_string << '<span class="glyphicon glyphicon-folder-open"></span> '

        else
          return_string << '<span class="glyphicon glyphicon-file"></span> '
        end

        return_string << name_arr.last
        name_arr.length.times do
          return_string << "</div>"
        end
      end

    end

    return return_string.gsub("\"", "'")

  end

end
