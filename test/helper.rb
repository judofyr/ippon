if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start
  SimpleCov.minimum_coverage 100
end

require 'minitest/autorun'

