require 'ippon'
require 'uri'

module Ippon::FormData
  class DotScope
    def initialize(prefix = nil)
      @prefix = prefix
    end

    def expand_name(name)
      if @prefix
        @prefix + name
      else
        name
      end
    end

    def child(name)
      DotScope.new("#{@prefix}#{name}.")
    end
  end

  class URLEncoded
    def self.parse(str)
      new(URI.decode_www_form(str))
    end

    def initialize(pairs = [])
      @pairs = pairs
    end

    def each_for(name, scope = nil)
      full_name = scope ? scope.expand_name(name) : name
      @pairs.each do |k, v|
        yield v if full_name == k
      end
      self
    end

    def [](name, scope = nil)
      fetch(name, scope) { nil }
    end

    def fetch(name, scope = nil)
      each_for(name, scope) do |value|
        return value
      end

      if block_given?
        yield
      else
        raise KeyError, "name not found: #{name}"
      end
    end

    def fetch_all(name, scope = nil)
      result = []
      each_for(name, scope) do |value|
        result << value
      end
      result
    end
  end
end

