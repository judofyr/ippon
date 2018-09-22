require 'ippon'

module Ippon::Validate

  Error = Struct.new(:path, :message)

  class Result
    attr_accessor :value
    attr_reader :errors, :path

    def initialize(value)
      @value = value
      @is_halted = false
      @errors = []
      @path = [].freeze
    end

    def error?
      @errors.any?
    end

    def success?
      !error?
    end

    alias valid? success?

    def halted?
      @is_halted
    end

    def halt
      @is_halted = true
      self
    end

    def unhalt
      @is_halted = false
      self
    end

    def push_path(key)
      @path = [*@path, key].freeze
      self
    end

    def add_error(message)
      @errors << Error.new(@path, message)
      self
    end

    def add_errors_from(result)
      @errors.concat(result.errors)
      self
    end

    private

    def initialize_copy(source)
      @errors = source.errors.dup
    end
  end

  class Schema
    def validate(value)
      result = Result.new(value)
      process(result)
      result
    end

    def validate!(value)
      result = validate(value)
      raise if result.error?
      result.value
    end

    def |(other)
      Sequence.new(self, other)
    end

    def &(other)
      Merge.new(self, other)
    end

    def unhalt
      Unhalt.new(self)
    end
  end

  class Unhalt < Schema
    def initialize(child)
      @child = child
    end

    def process(result)
      @child.process(result)
      result.unhalt
    end
  end

  class Sequence < Schema
    def initialize(left, right)
      @left = left
      @right = right
    end

    def process(result)
      @left.process(result)
      return if result.halted?
      @right.process(result)
    end
  end

  class Step < Schema
    attr_reader :props

    def initialize(props = {})
      @props = props.freeze
    end

    def message
      @props.fetch(:message) { self.class.default_message }
    end

    def self.transform(&blk)
      define_method(:process) do |result|
        result.value = instance_exec(result.value, &blk)
      end
    end

    def self.transform_catch(*errors, &blk)
      define_method(:process) do |result|
        begin
          result.value = instance_exec(result.value, &blk)
        rescue *errors
          result.halt
          result.add_error(message)
        end
      end
    end

    def self.validate(&blk)
      define_method(:process) do |result|
        is_valid = instance_exec(result.value, &blk)
        if !is_valid
          result.halt
          result.add_error(message)
        end
      end
    end

    def self.halt(&blk)
      define_method(:process) do |result|
        should_halt = instance_exec(result.value, &blk)
        if should_halt
          result.halt
        end
      end
    end
  end

  class Field < Step
    transform do |value|
      value[props.fetch(:key)]
    end
  end

  class Trim < Step
    transform do |value|
      if value
        value = value.strip
        value = nil if value.empty?
      end
      value
    end
  end

  class Required < Step
    validate do |value|
      !value.nil?
    end

    def self.default_message
      "is required"
    end
  end

  class Optional < Step
    halt do |value|
      value.nil?
    end
  end

  class Boolean < Step
    transform do |value|
      !!value
    end
  end

  class Integer < Step
    transform_catch(ArgumentError) do |value|
      Integer(value)
    end

    def self.default_message
      "must be an integer"
    end
  end

  class Float < Step
    transform_catch(ArgumentError) do |value|
      Float(value)
    end

    def self.default_message
      "must be float"
    end
  end

  class Match < Step
    def predicate
      props.fetch(:predicate)
    end

    validate do |value|
      predicate === value
    end

    def self.default_message
      "must match"
    end
  end

  class Transform < Step
    def handler
      @props.fetch(:handler)
    end

    transform do |value|
      handler.call(value)
    end
  end

  class Halt < Step
    def predicate
      props.fetch(:predicate)
    end

    halt do |value|
      predicate === value
    end
  end

  class Form < Schema
    attr_reader :fields

    def initialize(fields)
      @fields = fields
    end

    def process(result)
      values = {}

      # Process all fields:
      results = @fields.map do |key, field|
        field_result = result.dup.push_path(key)
        field.process(field_result)
        [key, field_result]
      end

      # Propgate state:
      results.each do |key, field_result|
        if field_result.halted?
          result.halt
        else
          values[key] = field_result.value
        end
        
        result.add_errors_from(field_result)
      end

      result.value = values
    end
  end

  class Merge < Schema
    def initialize(left, right)
      @left = left
      @right = right
    end

    def process(result)
      left_result = result.dup
      right_result = result.dup

      @left.process(left_result)
      @right.process(right_result)

      result.add_errors_from(left_result)
      result.add_errors_from(right_result)

      result.value = {}
      result.value.update(left_result.value) if !left_result.halted?
      result.value.update(right_result.value) if !right_result.halted?
      result.halt if left_result.halted? || right_result.halted?
      result
    end
  end

  module Builder
    def field(key, **props)
      Field.new(key: key, **props)
    end

    def trim(**props)
      Trim.new(**props)
    end

    def required(**props)
      Required.new(**props)
    end

    def optional(**props)
      Optional.new(**props)
    end

    def integer(**props)
      Integer.new(**props)
    end

    def float(**props)
      Float.new(**props)
    end

    def form(fields)
      Form.new(fields)
    end

    def halt_if(**props, &blk)
      Halt.new(predicate: blk, **props)
    end

    def match(predicate, **props)
      Match.new(predicate: predicate, **props)
    end

    def match_with(**props, &blk)
      match(blk, **props)
    end

    def transform(**props, &blk)
      Transform.new(handler: blk, **props)
    end
  end
end

