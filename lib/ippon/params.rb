require 'ippon'
require 'uri'

module Ippon::Params
  class Base
    def one(key)
      many(key).first
    end

    alias [] one

    def many(key)
      raise NotImplementedError
    end
  end

  class URLEncoded < Base
    def initialize(data)
      @data = data
    end

    def many(key)
      pairs
        .select { |name, value| name == key }
        .map { |_, value| value }
    end

    private

    def pairs
      @pairs ||= URI.decode_www_form(@data)
    end
  end
end

