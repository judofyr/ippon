require 'ippon'

module Ippon::Validate

  Error = Struct.new(:path, :step) do
    def message
      step.message
    end
  end

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

    def add_error(step)
      @errors << Error.new(@path, step)
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
      @props.fetch(:message) { default_message }
    end

    def self.transform(&blk)
      define_method(:process) do |result|
        new_value = instance_exec(result.value, &blk)
        if Error.equal?(new_value)
          result.halt
          result.add_error(self)
        else
          result.value = new_value
        end
      end
    end

    def self.validate(&blk)
      define_method(:process) do |result|
        is_valid = instance_exec(result.value, &blk)
        if !is_valid
          result.halt
          result.add_error(self)
        end
      end
    end
  end

  class Field < Step
    def key
      @props.fetch(:key)
    end

    transform do |value|
      value[key]
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

    def default_message
      "is required"
    end
  end

  class Optional < Step
    def predicate
      @predicate ||= @props.fetch(:predicate) { :nil?.to_proc }
    end

    def process(result)
      if predicate === result.value
        result.value = nil
        result.halt
      end
    end
  end

  class Boolean < Step
    transform do |value|
      !!value
    end
  end

  class Number < Step
    def char_regex(pattern)
      case pattern
      when Regexp
        pattern
      when String
        /[#{Regexp.escape(pattern)}]/
      else
        raise ArgumentError, "unknown pattern: #{pattern}"
      end
    end

    def ignore_regex
      @ignore_regex ||= char_regex(@props.fetch(:ignore, / /))
    end

    def decimal_separator
      @props[:decimal_separator]
    end

    def scaling
      @props[:scaling]
    end

    def convert
      @props.fetch(:convert) { :integer }
    end

    transform do |value|
      value = value.gsub(ignore_regex, "")

      if sep = decimal_separator
        value = value.sub(sep, ".")
      end

      begin
        num = Rational(value)
      rescue ArgumentError
        next Error
      end

      if s = scaling
        num *= s
      end

      case convert
      when :integer
        if num.denominator == 1
          num.numerator
        else
          Error
        end
      when :round
        num.round
      when :floor
        num.floor
      when :ceil
        num.ceil
      when :float
        num.to_f
      when :rational
        num
      when :decimal
        BigDecimal.new(num, value.size)
      else
        raise ArgumentError, "unknown convert: #{convert.inspect}"
      end
    end

    def default_message
      "must be a number"
    end
  end

  class Match < Step
    def predicate
      @props.fetch(:predicate)
    end

    validate do |value|
      predicate === value
    end

    def default_message
      "must match #{predicate}"
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

  class ForEach < Schema
    def initialize(element_schema)
      @element_schema = element_schema
    end

    def process(result)
      results = result.value.each_with_index.map do |element, idx|
        element_result = result.dup.push_path(idx)
        element_result.value = element
        @element_schema.process(element_result)
        element_result
      end

      results.each do |element_result|
        if element_result.halted?
          result.halt
        end

        result.add_errors_from(element_result)
      end

      result.value = results.map(&:value)
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

    def optional(**props, &blk)
      if blk
        Optional.new(predicate: blk, **props)
      else
        Optional.new(**props)
      end
    end

    def number(**props)
      Number.new(**props)
    end

    def float(**props)
      number(convert: :float, **props)
    end

    def form(fields)
      Form.new(fields)
    end

    def match(predicate, **props)
      Match.new(predicate: predicate, **props)
    end

    def for_each(schema)
      ForEach.new(schema)
    end

    def validate(**props, &blk)
      match(blk, **props)
    end

    def transform(**props, &blk)
      Transform.new(handler: blk, **props)
    end
  end
end

