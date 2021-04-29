require 'json'
require 'os'
require 'mime/types'
require 'mimemagic'
require 'mimemagic/overlay'
require 'zip'
require 'zlib'
require 'libarchive'
require 'rubygems/package'

require_relative 'extraction_status.rb'
require_relative 'peek_type.rb'
require_relative 'error_type.rb'
require_relative 'mime_type.rb'

class Extraction

  attr_accessor :binary_name, :storage_path, :status, :peek_type, :peek_text, :id, :nested_items, :error, :mime_type

  def initialize(binary_name, storage_path, id, mime_type)
    @nested_items = Array.new
    @binary_name = binary_name
    @storage_path = storage_path
    @id = id
    @error = Array.new
    @mime_type = mime_type
  end

  ALLOWED_CHAR_NUM = 1024 * 8
  ALLOWED_DISPLAY_BYTES = ALLOWED_CHAR_NUM * 8

  def process
    begin
      features_extracted = extract_features
      if features_extracted
        self.status = ExtractionStatus::SUCCESS
      else
        self.status = ExtractionStatus::ERROR
      end
    rescue StandardError => error
      self.status = ExtractionStatus::ERROR
      self.peek_type = PeekType::NONE
      report_problem(error.message)
    ensure
      if self.peek_text && self.peek_text.encoding.name != 'UTF-8'
        begin
          self.peek_text.encode('UTF-8')
        rescue Encoding::UndefinedConversionError
          self.peek_text = nil
          self.peek_type = PeekType::NONE
          report_problem('invalid encoding for peek text')
        rescue Exception => ex
          report_problem("invalid encoding and problem character: #{ex.class}, #{ex.message}")
        end
      end
    end
  end

  def report_problem(report)
    self.error.push({"error_type" => ErrorType::EXTRACTION, "report" => report})
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

  def self.mime_from_path(path)

    file_mime_response = MimeMagic.by_path(File.open("#{path}")).to_s
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

  def self.mime_from_filename(filename)
    mime_guesses = MIME::Types.type_for(filename).first.content_type
    if mime_guesses.length > 0
      mime_guesses
    else
      nil
    end
  end

  def create_item(item_path, item_name, item_size, media_type, is_directory)
    item = {"item_name" => item_name, "item_path" => item_path, "item_size" => item_size, "media_type" => media_type, "is_directory" => is_directory}
    @nested_items.push(item)

  end

  def extract_zip
    begin
      puts "Extracting zip file #{binary_name}"
      entry_paths = []
      Zip::File.open(self.storage_path) do |zip_file|
        zip_file.each do |entry|

          if entry.name_safe?

            entry_path = valid_entry_path(entry.name)


            if entry_path && !is_ds_store(entry_path) && !is_mac_thing(entry_path)

              entry_paths << entry_path

              if is_directory(entry.name)

                create_item(entry_path,
                            name_part(entry_path),
                            entry.size,
                            'directory',
                            true)

              else

                storage_dir = File.dirname(storage_path)
                extracted_entry_path = File.join(storage_dir, entry_path)
                extracted_entry_dir = File.dirname(extracted_entry_path)
                FileUtils.mkdir_p extracted_entry_dir

                raise Exception.new("extracted entry somehow already there?!!?!") if File.exist?(extracted_entry_path)

                entry.extract(extracted_entry_path)

                raise Exception.new("extracting entry not working!") unless File.exist?(extracted_entry_path)

                mime_guess = Extraction.mime_from_path(extracted_entry_path) ||
                    Extraction.mime_from_filename(entry.name) ||
                    'application/octet-stream'

                create_item(entry_path,
                            name_part(entry_path),
                            entry.size,
                            mime_guess,
                            false)
                File.delete(extracted_entry_path) if File.exist?(extracted_entry_path)
              end


            end
          end
        end
      end


      if entry_paths.length > 0
        self.peek_type = PeekType::LISTING
        self.peek_text = entry_paths_arr_to_html(entry_paths)
      else
        self.peek_type = PeekType::NONE
        report_problem("no items found for zip listing for task #{self.id}")
      end

      return true
    rescue StandardError => ex
      self.status = ExtractionStatus::ERROR
      self.peek_type = PeekType::NONE
      report_problem("problem extracting zip listing for task: #{ex.message}")

      raise ex
    end
  end

  def extract_archive
    begin
      puts "Extracting archive file #{binary_name}"
      entry_paths = []

      Archive.read_open_filename(self.storage_path) do |ar|
        while entry = ar.next_header

          entry_path = valid_entry_path(entry.pathname)

          if entry_path

            if !is_ds_store(entry_path) && !is_mac_thing(entry_path)
              entry_paths << entry_path

              if is_directory(entry.pathname)

                create_item(entry_path,
                            name_part(entry_path),
                            entry.size,
                            'directory',
                            true)
              else

                storage_dir = File.dirname(storage_path)
                extracted_entry_path = File.join(storage_dir, entry_path)
                extracted_entry_dir = File.dirname(extracted_entry_path)
                FileUtils.mkdir_p extracted_entry_dir

                entry_size = 0

                File.open(extracted_entry_path, 'wb') do |entry_file|
                  ar.read_data(1024) do |x|
                    entry_file.write(x)
                    entry_size = entry_size + x.length
                  end
                end

                raise("extracting non-zip entry not working!") unless File.exist?(extracted_entry_path)

                mime_guess = Extraction.mime_from_path(extracted_entry_path) ||
                    mime_from_filename(entry.name) ||
                    'application/octet-stream'


                create_item(entry_path,
                            name_part(entry_path),
                            entry.size,
                            mime_guess,
                            false)

                File.delete(extracted_entry_path) if File.exist?(extracted_entry_path)
              end

            end

          end
        end
      end

      if entry_paths.length > 0
        self.peek_type = PeekType::LISTING
        self.peek_text = entry_paths_arr_to_html(entry_paths)
        return true
      else
        self.peek_type = PeekType::NONE
        report_problem("no items found for archive listing for task #{self.id}")
        return false
      end

    rescue StandardError => ex
      self.status = ExtractionStatus::ERROR
      self.peek_type = PeekType::NONE

      report_problem("problem extracting extract listing for task #{self.id}: #{ex.message}")
      return false
    end
  end

  def extract_gzip
    begin
      puts "Extracting gzip file #{binary_name}"
      entry_paths = []

      tar_extract = Gem::Package::TarReader.new(Zlib::GzipReader.open(self.storage_path))
      tar_extract.rewind # The extract has to be rewinded after every iteration
      tar_extract.each do |entry|

        entry_path = valid_entry_path(entry.full_name)
        if entry_path

          if !is_ds_store(entry_path) && !is_mac_thing(entry_path) && !is_mac_tar_thing(entry_path)
#            puts entry.full_name

            entry_paths << entry_path

            if entry.directory?

              create_item(entry_path,
                          name_part(entry_path),
                          entry.size,
                          'directory',
                          true)
            else

              storage_dir = File.dirname(storage_path)
              extracted_entry_path = File.join(storage_dir, entry_path)
              extracted_entry_dir = File.dirname(extracted_entry_path)
              FileUtils.mkdir_p extracted_entry_dir

              entry_size = 0

              File.open(extracted_entry_path, 'wb') do |entry_file|
                entry.read(1024) do |x|
                  entry_file.write(x)
                  entry_size = entry_size + x.length
                end
              end

              raise("extracting gzip entry not working!") unless File.exist?(extracted_entry_path)

              mime_guess = Extraction.mime_from_path(extracted_entry_path) ||
                  mime_from_filename(entry.name) ||
                  'application/octet-stream'


              create_item(entry_path,
                          name_part(entry_path),
                          entry.size,
                          mime_guess,
                          false)

              File.delete(extracted_entry_path) if File.exist?(extracted_entry_path)
            end

          end

        end
      end

      if entry_paths.length > 0
        self.peek_type = PeekType::LISTING
        self.peek_text = entry_paths_arr_to_html(entry_paths)
        return true
      else
        self.peek_type = PeekType::NONE
        report_problem("no items found for archive listing for task #{self.id}")
        return false
      end

    rescue StandardError => ex
      self.status = ExtractionStatus::ERROR
      self.peek_type = PeekType::NONE

      report_problem("problem extracting extract listing for task #{self.id}: #{ex.message}")
      return false

      tar_extract.close
    end

  end

  def extract_default
    puts "Default extraction for #{binary_name}"
    begin
      self.peek_type = PeekType::NONE
      return true
    rescue StandardError => ex
      self.status = ExtractionStatus::ERROR
      self.peek_type = PeekType::NONE
      report_problem("problem creating default peek for task #{self.id}")
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
    ends_in_slash(path) && !is_ds_store(path) && !is_mac_thing(path)
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
    return path[-1] == '/'
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

    return_string << self.binary_name

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
