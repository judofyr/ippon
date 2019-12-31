require 'ippon'
require 'ippon/validate'

module Ippon::Form
  class Entry
    class << self
      def options
        @options ||= {}
      end
    end

    def self.[](**options)
      _subclass_cache[options] ||= Class.new(self) {
        @options = options
        self
      }
    end

    def self._subclass_cache
      @_subclass_cache ||= {}
    end

    attr_reader :key

    def initialize(key)
      @key = key
      setup
    end

    def setup
    end

    attr_reader :result

    def validate
      @result ||= _validate
    end

    def error?
      defined?(@result) && @result.error?
    end

    def errors
      defined?(@result) ? @result.errors : ::Ippon::Validate::EMPTY_ERRORS
    end
  end

  class Text < Entry
    attr_accessor :value

    def setup
      @value = nil
    end

    def from_input(input)
      @value = input[key]
    end

    def serialize
      yield key.to_s, @value
    end

    def _validate
      ::Ippon::Validate::Result.new(@value)
    end
  end

  class TextList < Entry
    attr_accessor :values

    def setup
      @values = []
    end

    def from_input(input)
      @values = input.fetch_all(key)
    end

    def serialize
      @values.each do |value|
        yield key.to_s, value
      end
    end

    def _validate
      ::Ippon::Validate::Result.new(@values)
    end

    def each(&blk)
      @values.each(&blk)
    end

    include Enumerable
  end

  class Flag < Entry
    attr_writer :checked

    def setup
      @checked = nil
    end

    def checked?
      @checked
    end

    def from_input(input)
      if value = input[key]
        @checked = (value == "1")
      end
    end

    def serialize
      case @checked
      when true
        yield key.to_s, "1"
      when false
        yield key.to_s, "0"
      end
    end

    def _validate
      ::Ippon::Validate::Result.new(@checked)
    end
  end

  class List < Entry
    def self.element_class
      @element_class ||= options.fetch(:of)
    end

    def setup
      @entries = {}
    end

    def from_input(input)
      input.each_for(key) do |id|
        entry = add(id)
        entry.from_input(input)
      end
    end

    def serialize(&blk)
      @entries.each do |name, entry|
        yield key.to_s, name
        entry.serialize(&blk)
      end
    end

    def _validate
      value = []
      result = ::Ippon::Validate::Result.new(value)
      
      each_with_index do |entry, idx|
        element_result = entry.validate
        value << element_result.value
        result.add_nested(idx, element_result)
      end
      
      result
    end

    def add(id = @entries.size.to_s)
      subkey = key[id]
      @entries[id] = entry = self.class.element_class.new(subkey)
    end

    def each(&blk)
      @entries.each_value(&blk)
    end

    include Enumerable

    def each_with_id
      @entries.each do |id, entry|
        yield entry, key.to_s, id
      end
    end
  end

  class Group < Entry
    # Re-export common entries
    Text = Text
    TextList = TextList
    Flag = Flag
    List = List

    def self.field_spec
      if !defined?(@field_spec)
        raise "#fields not defined"
      end

      @field_spec
    end

    def self.fields(field_spec)
      if defined?(@field_spec)
        raise "#fields already defined earlier"
      end

      @field_spec = field_spec

      # Define getters
      field_spec.each do |name, klass|
        if method_defined?(name)
          raise "cannot define field #{name.inspect} because it clashes with a method"
        end

        attr_reader name
      end
    end

    def self.validate(&blk)
      schema = GroupBuilder.instance_eval(&blk)

      define_method(:_validate) do
        schema.validate(self)
      end
    end

    def setup
      @entries = []

      self.class.field_spec.each do |name, klass|
        ivar = :"@#{name}"
        entry = klass.new(key[name])
        instance_variable_set(ivar, entry)
        @entries << entry
      end
    end

    def from_input(input)
      @entries.each do |entry|
        entry.from_input(input)
      end
    end

    def serialize(&blk)
      @entries.each do |entry|
        entry.serialize(&blk)
      end
    end
  end

  module GroupBuilder
    extend ::Ippon::Validate::Builder
    module_function

    def field(name)
      ::Ippon::Validate::Step.new do |result|
        entry = result.value.send(name)
        entry.validate
      end
    end
  end
end