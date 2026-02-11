# frozen_string_literal: true
require 'bundler/setup'
require 'simplecov'
SimpleCov.start

require 'minitest/autorun'
require 'mocha/minitest'
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

Mocha.configure do |c|
  c.strict_keyword_argument_matching = true
end