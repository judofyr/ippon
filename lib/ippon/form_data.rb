require 'ippon'
require 'uri'

# Tools for working with HTTP form data.
module Ippon::FormData
  # A scope where nested fields are represented using a dot as a separator:
  #
  #   root = DotScope.new
  #   root.expand_name("email")  # => "email"
  #   address = root.child("address")
  #   address.expand_name("zip") # => "address.zip"
  class DotScope
    # Creates a new DotScope.
    def initialize(prefix = nil)
      @prefix = prefix
    end

    # Expands a field name for this scope.
    def expand_name(name)
      if @prefix
        @prefix + name
      else
        name
      end
    end

    # Creates a sub scope with a given name.
    def child(name)
      DotScope.new("#{@prefix}#{name}.")
    end
  end

  # Represents a URL encoded (application/x-www-form-urlencoded) form.
  class URLEncoded
    # @params [String] str
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

    # Yields every value for a field in a given scope.
    #
    # @param [String] name
    # @param [Scope | nil] scope
    # @yield [value] every value
    # @return self
    # @api private
    def each_for(name, scope = nil)
      full_name = scope ? scope.expand_name(name) : name
      @pairs.each do |k, v|
        yield v if full_name == k
      end
      self
    end

    # Finds a field value in a given scope; returning nil if it doesn't exist.
    #
    # @param [String] name
    # @param [Scope | nil] scope
    # @return [String | nil]
    def [](name, scope = nil)
      fetch(name, scope) { nil }
    end

    # Finds a field value in a given scope; yielding the block if it doesn't
    # exist.
    #
    # @param [String] name
    # @param [Scope | nil] scope
    # @yield if the field doesn't exist.
    # @raise [KeyError] if the field doesn't exist and no block is given.
    # @return [String]
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

    # Returns all values for a field.
    #
    # @param [String] name
    # @param [Scope | nil] scope
    # @return [Array<String>]
    def fetch_all(name, scope = nil)
      result = []
      each_for(name, scope) do |value|
        result << value
      end
      result
    end
  end
end

