require 'ippon'

module Ippon::Validate
  class Result
    attr_accessor :value
    attr_reader :errors

    def initialize(value)
      @value = value
      @errors = []
      @is_halted = false
    end

    def error?
      @errors.any?
    end

    def success?
      !error?
    end

    def halted?
      @is_halted
    end

    def halt
      @is_halted = true
    end

    def add_errors_from(result, key)
      result.errors.each do |error|
        @errors << error
      end
    end
  end

  Error = Struct.new(:step)

  class Schema
    attr_reader :id, :steps

    def initialize(id)
      @id = id
      @steps = []
    end

    def validate(obj)
      process(Result.new(obj))
    end

    def process(result)
      @steps.each do |step|
        step.process(result)
        break if result.halted?
      end
      result
    end

    def add(step)
      @steps << step
      self
    end

    def fetch(key = id, props = {})
      props[:key] = id
      add(Steps::Fetch.new(props))
    end

    def trim(props = {})
      add(Steps::Trim.new(props))
    end

    def required(props = {})
      add(Steps::Required.new(props))
    end

    def optional(props = {})
      add(Steps::Optional.new(props))
    end

    def integer(props = {})
      add(Steps::Integer.new(props))
    end

    def boolean(props = {})
      add(Steps::Boolean.new(props))
    end

    def match_with(props = {}, &blk)
      raise ArgumentError, "block required" if blk.nil?
      match(blk, props)
    end

    def match(predicate, props = {}, &blk)
      props[:predicate] = predicate
      add(Steps::Match.new(props))
    end

    def form(fields, props = {})
      props[:fields] = fields
      add(Steps::Form.new(props))
    end
  end

  class Step
    attr_reader :props

    def initialize(props = {})
      @props = props.freeze
    end

    # :nocov:
    def transform(obj)
      obj
    end

    def valid?(obj)
      true
    end
    # :nocov:

    def process(result)
      if valid?(result.value)
        result.value = transform(result.value)
      else
        result.errors << Error.new(self)
        result.halt
      end
    end
  end

  module Steps
    class Fetch < Step
      def transform(obj)
        key = props.fetch(:key)
        obj[key]
      end
    end

    class Trim < Step
      def transform(obj)
        if obj
          obj = obj.strip
          obj = nil if obj.empty?
        end

        obj
      end
    end

    class Required < Step
      def valid?(obj)
        !obj.nil?
      end
    end

    class Optional < Step
      def process(result)
        if result.value.nil?
          result.halt
        end
      end
    end

    class Integer < Step
      def valid?(obj)
        obj =~ /\A[+-]?\d+\z/
      end

      def transform(obj)
        obj.to_i
      end
    end

    class Boolean < Step
      def transform(obj)
        !!obj
      end
    end

    class Match < Step
      def valid?(obj)
        props.fetch(:predicate) === obj
      end
    end

    class Form < Step
      def process(result)
        fields = props.fetch(:fields)

        values = {}

        fields.each do |key, field|
          field_result = Result.new(result.value)
          field.process(field_result)
          values[key] = field_result.value
          if field_result.error?
            result.add_errors_from(field_result, field)
            result.halt
          end
        end

        result.value = values
      end
    end
  end
end

