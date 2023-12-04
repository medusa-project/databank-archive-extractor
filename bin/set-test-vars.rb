#!/usr/bin/env ruby

ENV['RUBY_ENV'] = 'test'
ENV['RUBY_HOME'] = ENV['IS_DOCKER'] == 'true' ? '/extractor' : '/Users/gschmitt/workspace/databank-archive-extractor'
ENV['RUBY_TEST_HOME'] = "#{ENV['RUBY_HOME']}/test"
