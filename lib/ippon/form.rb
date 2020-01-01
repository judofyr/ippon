require 'ippon'
require 'ippon/validate'

module Ippon::Form
  class Parametric
    def self.make(klass, &blk)
      cache = {}
      klass.class_eval do
        class << self
          alias _parametric_new new
          undef new
        end

        define_singleton_method(:[]) do |**options|
          cache[options] ||= Class.new(self) {
            instance_exec(options, &blk) if blk
            class << self
              alias new _parametric_new
            end
            self
          }
        end
      end
      nil
    end
  end

  class Entry
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
    Parametric.make(self) do |options|
      @element_class = options.fetch(:of)
    end

    class << self
      attr_reader :element_class
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
    Parametric = Parametric

    def self.fields
      @fields ||= {}
    end

    def self.field(name, klass)
      if fields.has_key?(name)
        raise "duplicate field #{name.inspect}"
      end

      if method_defined?(name)
        raise "cannot define field #{name.inspect} because it clashes with a method"
      end

      fields[name] = klass
    end

    def self.finalized_fields
      finalize
      fields
    end

    def self.finalize
      return if defined?(@finalized)
      @finalized = true
      fields.freeze
      fields.each do |name, klass|
        attr_reader name
      end
      self
    end

    def self.validate(&blk)
      schema = GroupBuilder.instance_eval(&blk)
      define_method(:_validate) do
        schema.validate(self)
      end
    end

    def setup
      @entries = []

      self.class.finalized_fields.each do |name, klass|
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

    def _validate
      ::Ippon::Validate::Result.new(self)
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