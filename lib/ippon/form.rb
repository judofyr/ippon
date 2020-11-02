require 'ippon/validate'

module Ippon
  module Form
    class Field
      attr_accessor :input, :output, :error

      def fill_from_data(data, key)
        raise NotEmplementedError, "#{self.class} is unable to fill from data"
      end

      def each_param(key)
        yield key, @input
      end
    end

    class StringField < Field
      def initialize
        @input = ""
      end

      def input=(val)
        @input = val.to_s
      end

      def fill_from_data(data, key)
        @input = data.fetch(key) { "" }
        self
      end
    end

    class StringsField < Field
      def initialize
        @input = []
      end

      def fill_from_data(data, key)
        @input = data.fetch_all(key)
        self
      end

      def each_param(key)
        @input.each do |val|
          yield key, val
        end
      end
    end

    class BooleanField < Field
      def initialize
        @input = false
      end

      def fill_from_data(data, key)
        @input = !!data[key]
        self
      end
    end

    class HashField < Field    
      def initialize
        @input = {}
      end

      def [](key)
        @input[key]
      end

      def []=(key, field)
        @input[key] = field
      end

      def get(key, klass)
        if field = @input[key]
          raise TypeError, "#{key.inspect} is already of class #{field.class}" if !field.is_a?(klass)
          field
        else
          @input[key] = klass.new
        end
      end

      def fill_output_from_children
        @output = {}
        input.each do |child_key, child_field|
          @output[child_key] = child_field.output
        end
        self
      end

      [
        [:string, StringField],
        [:strings, StringsField],
        [:boolean, BooleanField],
        [:hash, HashField],
      ].each do |name, klass|
        define_method(name) { |key| get(key, klass) }
      end

      def each_param(key, &blk)
        @input.each do |child_key, child_field|
          child_field.each_param(key[child_key], &blk)
        end
      end
    end

    class FormBuilder
      def initialize(schema_builder:)
        @schema_builder = schema_builder
        @pre_steps = []
        @post_steps = []
      end

      [:string, :strings, :boolean].each do |type|
        define_method(type) do |name, &blk|
          schema = blk.call(@schema_builder) if blk
          @pre_steps << proc { |field, form_processor|
            form_processor.fill(field.send(type, name), from: name, schema: schema)
          }
          self
        end
      end

      def nested(name, &blk)
        raise ArgumentError, "block required" if !blk

        @pre_steps << proc { |field, form_processor|
          form_processor.with_nested(name) do
            form_processor.instance_exec(field.hash(name), &blk)
          end
        }
      end

      def output(&blk)
        raise ArgumentError, "block required" if !blk

        schema = blk.call(@schema_builder)
        @post_steps << proc { |field, form_processor|
          form_processor.validate_output(field, schema)
        }
        self
      end

      def process(field, form_processor)
        @pre_steps.each do |step|
          step.call(field, form_processor)
        end

        return if !form_processor.valid?

        field.fill_output_from_children

        @post_steps.each do |step|
          step.call(field, form_processor)
        end
      end
    end

    class Processor
      def self.schema_builder
        @schema_builder ||= Ippon::Validate::Builder
      end

      class << self; attr_writer :schema_builder; end

      def self.form(name, &blk)
        if method_defined?(name)
          raise ArgumentError, "method already exists: ##{name}"
        end

        form_builder = FormBuilder.new(schema_builder: schema_builder)
        define_method(name) { |field| form_builder.process(field, self) }
        form_builder.instance_eval(&blk) if blk
        form_builder
      end

      def initialize(data, key)
        @data = data
        @key = key
        @is_valid = true
      end

      def valid?
        @is_valid
      end

      def with_nested(name)
        old_key = @key
        @key = @key[name]
        yield
      ensure
        @key = old_key
      end

      def fill(field, from: nil, schema: nil)
        key = from ? @key[from] : @key
        field.fill_from_data(@data, key)
        validate_input(field, schema) if schema
        field
      end

      def validate(field, schema, value)
        result = schema.validate(value)
        field.output = result.value
        field.error = result_to_error(result)
        @is_valid = false if result.error?
        field
      end

      def validate_input(field, schema)
        validate(field, schema, field.input)
      end

      def validate_output(field, schema)
        validate(field, schema, field.output)
      end

      def result_to_error(result)
        result.error_messages
      end
    end
  end
end