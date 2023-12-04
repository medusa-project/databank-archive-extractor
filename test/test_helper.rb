# frozen_string_literal: true

require 'simplecov'
SimpleCov.start

require 'minitest/autorun'
require 'config'
require 'csv'
require 'json'
require_relative '../lib/archive_extractor'
require_relative '../lib/extractor'
require_relative '../lib/extractor/error_type'
require_relative '../lib/extractor/extraction'
require_relative '../lib/extractor/extraction_status'
require_relative '../lib/extractor/extraction_type'
require_relative '../lib/extractor/mime_type'
require_relative '../lib/extractor/peek_type'