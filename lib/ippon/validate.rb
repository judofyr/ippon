require 'ippon'

# Ippon::Validate provides a composable validation system which let's
# you accept *untrusted* input and process it into *trusted* data.
#
# == Introductory example
#
#   # How to structure schemas:
#   require 'ippon/validate'
#
#   module Schemas
#     extend Ippon::Validate::Builder
#
#     User = form(
#       name: field("name") | trim | required,
#       email: field("email") | trim | optional | match(/@/),
#       karma: field("karma") | trim | optional | number | match(1..1000),
#     )
#   end
#
#   # How to use them:
#   result = Schemas::User.validate({"name" => " Magnus ", "karma" => "100"})
#   result.valid?  # => true
#   result.value   # =>
#     {
#       name: "Magnus",
#       karma: 100,
#     }
#
#   result = Schemas::User.validate({"name" => " Magnus ", "email" => "bob"})
#   result.valid?             # => false
#   result.errors[0].path     # => [:email]
#   result.errors[0].message  # => "must match /@/"
#
# == Available schemas
#
# - {Builder.required required} and {Builder.optional optional} for handling nils.
# - {Schema#| pipe} for combining schemas in order.
# - {Builder.number number} (and {Builder.float float}) for parsing strings as numbers.
# - {Builder.boolean boolean} for converting to booleans.
# - {Builder.match match} for validating with +===+.
# - {Builder.validate validate} for validating with a block.
# - {Builder.field field} for fetching a field.
# - {Builder.transform transform} for arbitrary transformation.
# - {Builder.form form} for validating multiple values.
# - {Schema#& merge} for merging two forms.
# - {Builder.for_each for_each} for validating arrays.
# - {Schema#unhalt unhalt} for validating multiple errors.
#
# == General usage
#
# Most validation libraries has a concept of _form_ which
# contains multiple _fields_. In Ippon::Validate there is no such
# distinction; there is only schemas that you can combine together.
#
# You can think about a schema as a pipeline: You have an untrusted
# value that's coming in and as it travels through the steps it can be
# _transformed_, _halted_, or produce _errors_. If the data is
# well-formed you will end up with a final value that has been correctly
# parsed and is ready to be used.
#
# Everything you saw in the introductory example was an instance of
# {Schema} and thus you can call {Schema#validate} on any part or
# combination:
#
#   module Schemas
#     extend Ippon::Validate::Builder
#
#     trim.validate!("  123  ")
#     # => "123"
#
#     (trim | number).validate!("  123 ")
#     # => 123
#
#     (field("age") | number).validate!({"age" => "123"})
#     # => 123
#
#     form(
#       age: field("age") | trim | number
#     ).validate!({"age" => " 123 "})
#     # => { age: 123 }
#   end
#
# Here we see examples of some common schemas:
#
# 1. {Builder.trim trim} accepts a string and removes leading/trailing
#    whitespace.
# 2. The {Schema#| pipe} operator applies two schemas in order. In this
#    case we _first_ trim, and _then_ we parse it as a number.
# 3. {Builder.field field} uses +#[]+ to access the field.
# 4. {Builder.form form} combines multiple schemas to build a Hash.
module Ippon::Validate

  # Represents an error which can happen during validation.
  Error = Struct.new(:path, :step) do
    # @!attribute [r] path
    #   @return [Array] the path where the error occured

    # @!attribute [r] step
    #   @return [Step] the step which caused the error

    # Returns an error message.
    #
    # This is produced by {Step#message}.
    #
    # @return [String]
    def message
      step.message
    end
  end

  # An exception class which is raised by {Schema#validate!} when a
  # validation error occurs.
  class ValidationError < StandardError
    # @return [Result] the result object
    attr_reader :result

    def initialize(result)
      @result = result
    end

    # A shortcut for {Result#errors +result.errors+}.
    #
    # @return [Array<Error>] the errors.
    def errors
      @result.errors
    end
  end

  # Represents a result from a validation ({Schema#validate}).
  #
  # A result consists of a {#value} and a list of {#errors} (of
  # {Error}). A result which contains *zero* errors is considered
  # {#valid?} (or a {#success?}), while a result which has *some* errors
  # is an {#error?}.
  #
  # In addition, a result may or may not be {#halted?}. This is used by
  # various schemas (e.g. {Builder.form Form} and {Schema#| Sequence})
  # to avoid continue processing. See {Schema#unhalt} for how to avoid
  # halting in schemas.
  #
  #   module Schemas
  #     extend Ippon::Validate::Builder
  #
  #     MaybeNumber = trim | optional | number
  #
  #     result = MaybeNumber.validate(" ")
  #     result.valid?   # => true; there are no errors
  #     result.halted?  # => true; but it was halted by `optional`
  #     result.value    # => nil
  #
  #     result = MaybeNumber.validate("123")
  #     result.valid?   # => true; there are no errors
  #     result.halted?  # => false; nothing caused this to halt
  #     result.value    # => 123
  #
  #     result = MaybeNumber.validate("  12b3")
  #     result.valid?   # => false; it's not a valid number
  #     result.halted?  # => true; and thus it was halted
  #     result.value    # => "12b3"; and the value is not fully formed
  #   end
  class Result
    # @return the current value
    attr_accessor :value

    # @return [Array<Error>] the errors
    attr_reader :errors

    # @return [Array] the current path
    # @api private
    attr_reader :path

    # Creates a new Result with the given +value+.
    def initialize(value)
      @value = value
      @is_halted = false
      @errors = []
      @path = [].freeze
    end

    # @return [Boolean] true if the result contains any errors.
    def error?
      @errors.any?
    end

    # @return [Boolean] true if the result contains zero errors.
    def success?
      !error?
    end

    alias valid? success?

    # @return [Boolean] true if the result has been halted.
    def halted?
      @is_halted
    end

    # Halt the result.
    #
    # @return [self]
    # @api private
    def halt
      @is_halted = true
      self
    end

    # Unhalt the result.
    #
    # @return [self]
    # @api private
    def unhalt
      @is_halted = false
      self
    end

    # Push a new element to the {#path}.
    #
    # @return [self]
    # @api private
    def push_path(key)
      @path = [*@path, key].freeze
      self
    end

    # Add an error from a step.
    #
    # @param step [Step]
    # @return [self]
    # @api private
    def add_error(step)
      @errors << Error.new(@path, step)
      self
    end

    # Copy over errors from another result.
    #
    # @param result [Result]
    # @return [self]
    # @api private
    def add_errors_from(result)
      @errors.concat(result.errors)
      self
    end

    private

    def initialize_copy(source)
      @errors = source.errors.dup
    end
  end

  # The base class for all schemas.
  #
  # @see Ippon::Validate
  class Schema
    # Validates the input value and return a result.
    #
    # @param value An untrusted input value
    # @return [Result]
    def validate(value)
      result = Result.new(value)
      process(result)
      result
    end

    # Validates the input value and return the output value, raising an
    # exception if an error occurs.
    #
    # @param value An untrusted input value
    # @raise [ValidationError] if a validation error occur
    # @return output value
    def validate!(value)
      result = validate(value)
      raise ValidationError.new(result) if result.error?
      result.value
    end

    # Process a result for the given schema. This must be overriden by
    # subclasses to provide the expected behvior.
    #
    # @abstract
    def process(result)
      # :nocov:
      raise NotImplementedError
      # :nocov:
    end

    # The pipe operator applies its left schema first and if the result
    # is not halted then it applies the right schema as well.
    #
    # This let's chain together multiple schemas that will be applied in
    # order while short-circuiting when an error is produced.
    #
    #   (required | number).validate!(nil)  # => Error from required
    #   (required | number).validate!("a")  # => Error from number
    #   (required | number).validate!("1")  # => 1
    #
    # @return [Sequence]
    def |(other)
      Sequence.new(self, other)
    end

    # The merge operator applies its left and right schema (which must
    # return Hashes) and merges the result into a combined value.
    #
    # This is most commonly used together with {Builder.form form}.
    #
    #   module Schemas
    #     extend Ippon::Validate::Builder
    #
    #     Basic = form(
    #       username: field("username") | trim | required,
    #     )
    #
    #     Advanced = form(
    #       karma: field("karma") | optional | number,
    #     )
    #
    #     Both = Basic & Advanced
    #   end
    #
    # If either the left or the right schema causes the result to be
    # halted, the final result will be halted as well.
    #
    # @return [Merge]
    def &(other)
      Merge.new(self, other)
    end

    # The unhalt schema applies its child schema and immediately unhalts
    # the result.
    #
    # This can be useful if you have non-critical validations and want
    # to be able to provide multiple errors for the same value.
    #
    #   module Schemas
    #     extend Ippon::Validate::Builder
    #
    #     Even = number | match(1..20).unhalt | validate { |val| val.even? }
    #   end
    #
    #   result = Schemas::Even.validate("44")
    #   result.errors.size  # => 2
    #
    # In the example above the +match(1..20)+ schema produced an error
    # and halted the result, but due to the unhalt schema it was undone
    # and validation continued.
    #
    # @return [Unhalt]
    def unhalt
      Unhalt.new(self)
    end
  end

  # @see Schema#unhalt
  class Unhalt < Schema
    # @return [Schema]
    attr_reader :child

    def initialize(child)
      @child = child
    end

    # Implements the {Schema#process} interface.
    def process(result)
      @child.process(result)
      result.unhalt
    end
  end

  # @see Schema#|
  class Sequence < Schema
    # @return [Schema]
    attr_reader :left
    # @return [Schema]
    attr_reader :right

    def initialize(left, right)
      @left = left
      @right = right
    end

    # Implements the {Schema#process} interface.
    def process(result)
      @left.process(result)
      return if result.halted?
      @right.process(result)
    end
  end

  # Step is the common class for all schemas that does actual validation
  # and transformation on the value (as opposed to just combining other
  # schemas).
  #
  # Every Step class take a +props+ Hash in their constructor and you
  # are free to store arbitrary data here. You can later access this data
  # from the {Error} object (through {Error#step}) and for instance use
  # it to customize error reporting.
  #
  # The +:message+ property will override the default error message
  # produced by {Error#message} and {Step#message}.
  #
  # @example How to access custom properties from the error object
  #   module Schemas
  #     extend Ippon::Validate::Builder
  #
  #     Even = trim |
  #       required |
  #       number(custom: 123) |
  #       validate(message: "must be even") { |v| v % 2 == 0 }
  #
  #   end
  #
  #   result = Schemas::Even.validate(" 1a1")
  #   result.errors[0].step.class           # => Ippon::Validate::Step
  #   result.errors[0].step.props[:type]    # => :number
  #   result.errors[0].step.props[:custom]  # => 123
  class Step < Schema
    # @return [Hash] Properties for this step.
    attr_reader :props

    # @param props [Hash] Properties for this step.
    def initialize(props = {}, &processor)
      @props = props.freeze
      @processor = processor
    end

    # The error message for this step.
    #
    # This will return the +:message+ property, failing back to +"must be
    # valid"+ if it's missing.
    #
    # @return [String] The error message.
    def message
      @props.fetch(:message, "must be valid")
    end

    # Implements the {Schema#process} interface.
    def process(result)
      @processor.call(result)
    end
  end

  # @see Builder.form
  class Form < Schema
    attr_reader :fields

    def initialize(fields)
      @fields = fields
    end

    # Implements the {Schema#process} interface.
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

  # @see Schema#&
  class Merge < Schema
    # @return [Schema]
    attr_reader :left
    # @return [Schema]
    attr_reader :right

    def initialize(left, right)
      @left = left
      @right = right
    end

    # Implements the {Schema#process} interface.
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

  # @see Builder.for_each
  class ForEach < Schema
    # @return [Schema]
    attr_reader :element_schema

    def initialize(element_schema)
      @element_schema = element_schema
    end

    # Implements the {Schema#process} interface.
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

  # The Builder module contains helper methods for creating {Schema}
  # objects. All the methods are available as +module_function+s which
  # means you can both +extend+ and +include+ this class as you see fit.
  #
  # Any helper method which accepts +props+ as keyword paramter will
  # pass them along to {Step}.
  #
  # @example Aliasing Builder
  #   b = Ippon::Validate::Builder
  #   even = b.trim | b.required | b.number | b.validate { |v| v % 2 == 0 }
  #
  # @example Extending Builder to use it inside a moudle
  #   module Schemas
  #     extend Ippon::Validate::Builder
  #
  #     Even = trim | required | number | validate { |v| v % 2 == 0 }
  #   end
  #
  # @example Including Builder to use it inside a class
  #   class SchemaBuilder
  #     include Ippon::Validate::Builder
  #
  #     def even
  #       trim | required | number | validate { |v| v % 2 == 0 }
  #     end
  #   end
  #
  #   SchemaBuilder.new.even
  module Builder
    module_function

    # The field schema extracts a field (given by +key+) from a value by
    # using +#[]+.
    #
    # This is strictly equivalent to:
    #
    #   transform { |value| value[key] }
    #
    # and thus the input value must respond to +#[]+.
    #
    # @param key The key which will be extracted. This value is stored under
    #   the +:key+ parameter in the returned {Step#props}.
    # @option props :type (:field)
    # @return [Step]
    def field(key, **props)
      transform(type: :field, key: key, **props) do |value|
        value[key]
      end
    end

    # The trim schema trims leading and trailing whitespace and then
    # converts the value to nil if it's empty. The input data must
    # either be a String or nil (in which case nothing happens).
    #
    # @option props :type (:trim)
    # @return [Step]
    def trim(**props)
      transform(type: :trim, **props) do |value|
        if value
          value = value.strip
          value = nil if value.empty?
        end
        value
      end
    end

    # The required schema produces an error if the input value is
    # non-nil.
    #
    # @option props :type (:required)
    # @option props :message ("is required")
    # @return [Step]
    def required(**props)
      validate(type: :required, message: "is required", **props) do |value|
        !value.nil?
      end
    end

    # The optional schema halts on +nil+ input values.
    #
    # @overload optional(**props)
    #   Halts the execution if the input value is +nil+
    #
    # @overload optional(**props)
    #   @yield [value] The input value
    #   @yieldreturn Boolean
    #
    #   Halts the execution and sets the value to +nil+ if the block
    #   yields true
    #
    # @option props :type (:optional)
    # @return [Step]
    def optional(**props, &blk)
      Step.new(type: :optional, **props) do |result|
        value = result.value
        should_halt = blk ? blk.call(value) : value.nil?
        if should_halt
          result.value = nil
          result.halt
        end
      end
    end

    # The number schema converts a String into a number.
    #
    # The input value *must* be a String. You should use {.required},
    # {.optional} or {.match +match(String)+} to enforce this.
    #
    # By default the number schema will ignore spaces and convert the
    # number to an Integer. If the value contains a fractional part,
    # a validation error is produced.
    #
    #   number.validate!("1 000")     # => 1000
    #   number.validate!("1 000.00")  # => 1000
    #   number.validate!("1 000.05")  # => Error
    #
    # You can change the set of ignored characters with the +:ignore+
    # option. This can either be a string (in which case all characters
    # in the string will be removed) or a regexp (in which case all
    # matches of the regexp will be removed).
    #
    #   # Also ignore commas
    #   number(ignore: ", ").validate!("1,000")  # => 1000
    #
    #   # Remove dashes, but only in the middle by using a negative lookbehind
    #   with_dash = number(ignore: / |(?<!\A)-/)
    #   with_dash.validate!("-10")       # => -10
    #   with_dash.validate!("10-10-10")  # => 101010
    #
    # The +:convert+ option instructs how to handle fractional parts.
    # The following values are supported:
    #
    # - +:integer+: Return an Integer, but produce an error if it has a fractional part.
    # - +:round+: Return an Integer by rounding it to the nearest integer.
    # - +:ceil+: Return an Integer by rounding it down.
    # - +:floor+: Return an Integer by rounding it up.
    # - +:float+: Return a Float.
    # - +:decimal+: Return a BigDecimal.
    # - +:rational+: Return a Rational.
    #
    # You can change the decimal separator as well:
    #
    #   # Convention for writing numbers in Norwegian
    #   nor_number = number(decimal_separator: ",", ignore: " .", convert: :float)
    #   nor_number.validate!("1.000,50")  # => 1000.50
    #
    # If you're dealing with numbers where there's a smaller, fractional
    # unit, you can provide the +:scale+ option in order to represent
    # the number exactly as an Integer:
    #
    #   dollars = number(ignore: " $,", scale: 100)
    #   dollars.validate!("$100")      # => 10000
    #   dollars.validate!("$100.33")   # => 10033
    #   dollars.validate!("$100.333")  # => Error
    #
    # +:scale+ works together with +:convert+ as expected. For instance,
    # if you want to round numbers that are smaller than the fractional
    # unit, you can combine it with +convert: :round+.
    #
    # @option props [String, Regexp] :ignore (" ") Characters to ignore
    #   while parsing number
    # @option props [Symbol] :convert (:integer) Technique to convert the final number
    # @option props [Integer] :scale Scaling factor
    # @option props [String] :decimal_separator (".") decimal separator
    # @option props [String] :message ("must be a number")
    # @option props [Symbol] :type (:number)
    # @return [Step]
    def number(**props)
      transform(type: :number, message: "must be a number", **props) do |value|
        ignore = props.fetch(:ignore, / /)

        ignore_regex = case ignore
        when Regexp
          ignore
        when String
          /[#{Regexp.escape(ignore)}]/
        else
          raise ArgumentError, "unknown pattern: #{ignore}"
        end

        value = value.gsub(ignore_regex, "")

        if sep = props[:decimal_separator]
          value = value.sub(sep, ".")
        end

        begin
          num = Rational(value)
        rescue ArgumentError
          next Error
        end

        if scale = props[:scale]
          num *= scale
        end

        case convert = props.fetch(:convert, :integer)
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
    end

    # @return [Step] a number schema with +convert: :float+
    def float(**props)
      number(convert: :float, **props)
    end

    # The boolean schema converts falsy values (+false+ and +nil+) to
    # +false+ and all other values to +true+.
    #
    #   boolean.validate!(nil)    # => false
    #   boolean.validate!("123")  # => true
    #
    # @option props [Symbol] :type (:boolean)
    # @return [Step]
    def boolean(**props)
      transform(type: :boolean, **props) do |value|
        !!value
      end
    end

    # @return [Form] a form schema
    def form(fields)
      Form.new(fields)
    end

    # The match schema produces an error if +predicate === value+
    # is false.
    #
    # This is a versatile validator which you can use for many different
    # purposes:
    #
    #   # Number is within range
    #   match(1..20)
    #
    #   # Value is of type
    #   match(String)
    #
    #   # String matches regexp
    #   match(/@/)
    #
    # @param predicate An object which responds to +===+. This value is stored
    #   under the +:predicate+ parameter in the returned {Step#props}.
    # @option props :type (:match)
    # @option props :message ("must match #{predicate}")
    # @return [Step]
    def match(predicate, **props)
      validate(type: :match, predicate: predicate, message: "must match #{predicate}", **props) do |value|
        predicate === value
      end
    end

    # The for-each schema applies the given +schema+ to each element of
    # the input data.
    #
    # @param schema [Schema] The scheme which will be applied to every element
    # @return [ForEach]
    def for_each(schema)
      ForEach.new(schema)
    end

    # The validate schema produces an error if the yielded block returns
    # false.
    #
    #   validate { |num| num.even? }
    #
    # @yield value
    # @yieldreturn Boolean
    # @return [Step]
    def validate(**props, &blk)
      step = Step.new(**props) do |result|
        is_valid = yield result.value
        if !is_valid
          result.halt
          result.add_error(step)
        end
      end
    end

    # The transform schema yields the value and updates the result with
    # the returned value.
    #
    #   transform { |val| val * 2 }.validate!(2)  # => 4
    #
    # @yield value
    # @return [Step]
    def transform(**props, &blk)
      step = Step.new(**props) do |result|
        new_value = yield result.value
        if Error.equal?(new_value)
          result.halt
          result.add_error(step)
        else
          result.value = new_value
        end
      end
    end
  end
end

