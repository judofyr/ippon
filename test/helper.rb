if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start
end

require 'minitest/autorun'

