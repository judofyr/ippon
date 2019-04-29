require 'ippon'
require 'uri'

# Tools for working with HTTP form data.
module Ippon::FormData
  # A key where nested fields are represented using a dot as a separator:
  #
  #   root = DotKey.new("user")
  #   root[:email].to_s # => "user.email"
  #
  #   address = root[:address]
  #   address[:zip].to_s # => "user.address.zip"
  class DotKey
    # Creates a new key.
    def initialize(value = "")
      @value = value.to_s
    end

    # Returns the full string representation.
    def to_s
      @value
    end

    # Creates a new subkey with a given name.
    def [](name)
      if @value.empty?
        DotKey.new(name)
      else
        DotKey.new("#{@value}.#{name}")
      end
    end
  end

  # A key where nested fields are represented using bracket notation:
  #
  #   root = DotKey.new
  #   root[:email].to_s # => "email"
  #
  #   address = root[:address]
  #   address[:zip].to_s # => "address[zip]"
  class BracketKey
    # Creates a new key.
    def initialize(value = "")
      @value = value.to_s
    end

    # Returns the full string representation.
    def to_s
      @value
    end

    # Creates a new subkey with a given name.
    def [](name)
      if @value.empty?
        BracketKey.new(name)
      else
        BracketKey.new("#{@value}[#{name}]")
      end
    end
  end

  # Represents a URL encoded (application/x-www-form-urlencoded) form.
  class URLEncoded
    # @param [String] str
    # @return [URLEncoded] a parsed version of 
    def self.parse(str)
      new(URI.decode_www_form(str))
    end

    # Creates a new instance. For now prefer {URLEncoded.parse}.
    #
    # @api private
    def initialize(pairs = [])
      @pairs = pairs
    end

    # Yields every value for a field.
    #
    # @param [#to_s] name
    # @yield [value] every value
    # @return self
    # @api private
    def each_for(name)
      name = name.to_s
      @pairs.each do |k, v|
        yield v if name == k
      end
      self
    end

    # Finds a field value; returning nil if it doesn't exist.
    #
    # @param [#to_s] name
    # @return [String | nil]
    def [](name)
      fetch(name) { nil }
    end

    # Finds a field value in a given scope; yielding the block if it doesn't
    # exist.
    #
    # @param [#to_s] name
    # @yield if the field doesn't exist.
    # @raise [KeyError] if the field doesn't exist and no block is given.
    # @return [String]
    def fetch(name)
      name = name.to_s
      each_for(name) do |value|
        return value
      end

      if block_given?
        yield
      else
        raise KeyError, "name not found: #{name}"
      end
    end

    # Returns all values for a field.
    #
    # @param [#to_s] name
    # @return [Array<String>]
    def fetch_all(name)
      result = []
      each_for(name) do |value|
        result << value
      end
      result
    end
  end
end

