require 'ippon'
require 'bigdecimal'

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
#       name: fetch("name") | trim | required,
#       email: fetch("email") | trim | optional | match(/@/),
#       karma: fetch("karma") | trim | optional | number | match(1..1000),
#     )
#   end
#
#   # How to use them:
#   result = Schemas::User.validate({
#     "name" => " Magnus ",
#     "email" => "",
#     "karma" => "100",
#   })
#
#   result.valid?  # => true
#   result.value   # =>
#     {
#       name: "Magnus",
#       email: nil,
#       karma: 100,
#     }
#
#   result = Schemas::User.validate({
#     "name" => " Magnus ",
#     "email" => "bob",
#     "karma" => "",
#   })
#   result.valid?             # => false
#   result.errors[0].message  # => "email: must match /@/"
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
# Everything you saw in the introductory example was an instance of {Schema} and
# thus you can call {Schema#validate} (or {Schema#validate!}) on any part or
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
#     (fetch("age") | number).validate!({"age" => "123"})
#     # => 123
#
#     form(
#       age: fetch("age") | trim | number
#     ).validate!({"age" => " 123 "})
#     # => { age: 123 }
#   end
#
# {Schema#validate} will always return a {Result} object, while
# {Schema#validate!} will return the output value, but raise a {ValidationError}
# if an error occurs.
#
# == {Step}: The most basic schema
#
# The smallest schema in Ippon::Validate is a {Step} and you create them with
# the helper methods in {Builder}:
#
#   module Schemas
#     extend Ippon::Validate::Builder
#
#     step = number(
#       convert: :round,
#       html: { required: true },
#       message: "must be numerical",
#     )
#
#     step.class           # => Ippon::Validate::Step
#     step.type            # => :number
#     step.message         # => "must be numerical"
#     step.props[:message] # => "must be numerical"
#     step.props[:html]    # => { required: true }
#   end
#
# Every step is configured with a Hash called {Step#props props}. The purpose is
# for you to be able to include custom data you need in order to present a
# reasonable error message or form interface. In the example above we have
# attached a custom +:html+ prop which we intend to use while rendering the form
# field in HTML. The +:message+ prop is what decides the error message, and the
# +:convert+ prop is used by the {Builder.number number} step internally.
#
# The most general step methods are {Builder.transform transform} and
# {Builder.validate validate}. +transform+ changes the value according to the
# block, while +validate+ will cause an error if the block returns falsey.
#
#   module Schemas
#     extend Ippon::Validate::Builder
#
#     is_date = validate { |val| val =~ /^\d{4}-\d{2}-\d{2}$/ }
#     to_date = transform { |val| Date.parse(val) }
#   end
#
# Instead of +validate+ you will often end up using one of the other helper methods:
#
# - {Builder.required required} checks for nil. (We'll cover {Builder.optional
#   optional} in the next section since it's quite a different beast.)
# - {Builder.match match} uses the +===+ operator which allows you to easily
#   match against constants, regexes and classes.
#
# And instead of +transform+ you might find these useful:
#
# - {Builder.number number} (and {Builder.float float}) for parsing strings as numbers.
# - {Builder.boolean boolean} for converting to booleans.
# - {Builder.fetch fetch} for fetching a field.
# - {Builder.trim trim} removes whitespace from the beginning/end and converts
#   it to nil if it's empty.
#
# == Combining schemas
#
# You can use the {Schema#| pipe} operator to combine two schemas. The resulting
# schema will first try to apply the left-hand side and then apply the
# right-hand side.  This let's you build quite complex validation rules in a
# straight forward way:
#
#   module Schemas
#     extend Ippon::Validate::Builder
#
#     Karma = fetch("karma") | trim | optional | number | match(1..1000)
#
#     Karma.validate!({"karma" => " 500 "}) # => 500
#   end
#
# A common pattern you will see is the combination of +fetch+ and +trim+. This
# will fetch the field from the input value and automatically convert
# empty-looking fields into +nil+. Assuming your input is from a text field you
# most likely want to treat empty text as a +nil+ value.
#
# == Halting and +optional+
#
# Whenever an error is produced the validation is _halted_. This means that
# further schemas combined will _not_ be executed. Continuing from the example
# in the previous section:
#
#   result = Schemas::Karma.validate({"karma" => " abc "})
#   result.error?   # => true
#   result.halted?  # => true
#
#   result.errors.size        # => 1
#   result.errors[0].message  # => "must be number"
#
# Once the {Builder.number number} schema was processed it produced an error and
# halted the result. Since the result was halted the {Step#| pipe} operator did
# not apply the right-hand side, +match(1..1000)+. This is good, because there
# is no number to validate against.
#
# {Builder.optional optional} is a schema which, if the value is +nil+, halts
# without producing an error:
#
#   result = Schemas::Karma.validate({"karma" => " "})
#   result.error?   # => false
#   result.halted?  # => true
#
#   result.value    # => nil
#
# Although we might think about +optional+ as having the meaning "this value can
# be +nil+", it's more precise to think about it as "when the value *is* +nil+,
# don't touch or validate it any further". +required+ and +optional+ are
# surprisingly similar with this approach: Both halts the result if the value is
# +nil+, but +required+ produces an error in addition.
#
# == Building forms
#
# We can use {Builder.form form} when we want to validate multiple distinct
# values in one go:
#
#   module Schemas
#     extend Ippon::Validate::Builder
#
#     User = form(
#       name: fetch("name") | trim | required,
#       email: fetch("email") | trim | optional | match(/@/),
#       karma: fetch("karma") | trim | optional | number | match(1..1000),
#     )
#
#     result = User.validate({
#       "name" => " Magnus ",
#       "email" => "",
#       "karma" => "100",
#     })
#
#     result.value   # =>
#       {
#         name: "Magnus",
#         email: nil,
#         karma: 100,
#       }
#
#
#     result = User.validate({
#       "name" => " Magnus ",
#       "email" => "bob",
#       "karma" => "",
#     })
#
#     result.valid?             # => false
#
#     result.errors[0].message  # => "email: must match /@/"
#   end
#
#
# It's important to know that the keys of the +form+ doesn't dictate anything
# about the keys in the input data. You must explicitly use +fetch+ if you want
# to access a specific field. At first this might seem like unneccesary
# duplication, but this is a crucical feature in order to decouple the input
# data from the output data. Often you'll find it useful to be able to rename
# internal identifiers without breaking the forms, or you'll find that the form
# data doesn't match perfectly with the internal data model.
#
# Here's an example for how you can write a schema which accepts a single string
# and then splits it up into a title (the first line) and a body (the rest of
# the text):
#
#   module Schemas
#     extend Ippon::Validate::Builder
#
#     Post = form(
#       title: transform { |val| val[/\A.*/] } | required,
#       body: transform { |val| val[/\n.*\z/m] } | trim,
#     )
#
#     Post.validate!("Hello")
#     # => { title: "Hello", body: nil }
#
#     Post.validate!("Hello\n\nTesting")
#     # => { title: "Hello", body: "Testing" }
#   end
#
# This might seem like a contrived example, but the purpose here is to show that no
# matter how complicated the input data is Ippon::Validate will be able to
# handle it. The implementation might not look very nice, but you will be able
# to integrate it into your regular schemas without writing a separate "clean up
# input" phase.
#
# In addition there is the {Schema#& merge} operator for merging two forms. This
# is useful when the same fields are used in multiple forms, or if the fields
# available depends on context (e.g. admins might have access to edit more
# fields).
#
#   module Schemas
#     extend Ippon::Validate::Builder
#
#     Basic = form(
#       username: fetch("username") | trim | required,
#     )
#
#     Advanced = form(
#       karma: fetch("karma") | optional | number,
#     )
#
#     Both = Basic & Advanced
#   end
#
# == Partial forms
#
# At first the following example might look a bit confusing:
#
#   module Schemas
#     extend Ippon::Validate::Builder
#
#     User = form(
#       name: fetch("name") | trim | required,
#       email: fetch("email") | trim | optional | match(/@/),
#       karma: fetch("karma") | trim | optional | number | match(1..1000),
#     )
#
#     result = User.validate({
#       "name" => " Magnus ",
#     })
#
#     result.error? # => true
#
#     result.errors[0].message  # => "email: must be present"
#   end
#
# We've marked the +:email+ field as optional, yet it seems to be required by
# the schema. This is because all fields of a form must be _present_. The
# {Builder.optional optional} schema allows the value to take a +nil+
# value, but it must still be present in the input data.
#
# When you declare a form with +:name+, +:email+ and +:karma+, you are
# guaranteed that the output value will _always_ contain +:name+, +:email+ and
# +:karma+. This is a crucial feature so you can always trust the output data.
# If you misspell the email field as "emial" you will get a validation error
# early on instead of the data magically not appearing in the output data (or it
# being set to +nil+).
#
# There are some use-cases where you want to be so strict about the presence of
# fields. For instance, you might have an endpoint for updating some of the
# fields of a user. For this case, you can use a {Builder.partial_form
# partial_form}:
#
#   module Schemas
#     extend Ippon::Validate::Builder
#
#     User = partial_form(
#       name: fetch("name") | trim | required,
#       email: fetch("email") | trim | optional | match(/@/),
#       karma: fetch("karma") | trim | optional | number | match(1..1000),
#     )
#
#     result = User.validate({
#       "name" => " Magnus ",
#     })
#
#     result.valid? # => true
#     result.value  # => { name: "Magnus" }
#
#     result = User.validate({
#     })
#
#     result.valid? # => true
#     result.value  # => {}
#   end
#
# {Builder.partial_form partial_form} works similar to {Builder.form form}, but
# if there's a {Builder.fetch fetch} validation error for a field, it will be
# ignored in the output data.
#
# == Working with lists
#
# If your input data is an array you can use {Builder.for_each for_each} to
# validate every element:
#
#   module Schemas
#     extend Ippon::Validate::Builder
#
#     User = form(
#       username: fetch("username") | trim | required,
#     )
#
#     Users = for_each(User)
#
#     result = Users.validate([{"username" => "a"}, {"username" => "  "}])
#     result.error?  # => true
#     result.errors[0].message  # => "1.username: is required"
#   end
module Ippon::Validate

  # Value used to represent that an error has occured.
  StepError = Object.new.freeze

  # Stores information about errors.
  class Errors
    # @return [Arary<Step>] steps that produced an error
    attr_reader :steps

    # @return [Hash] child results
    # @api private
    attr_reader :children

    # @api private
    def initialize
      @steps = []
      @children = {}
    end

    # Deeply freezes the object.
    # @api private
    def deep_freeze
      @steps.freeze
      @children.freeze
      freeze
      self
    end

    # @return [Boolean] +true+ if there are no errors.
    def empty?
      @steps.empty? && @children.empty?
    end

    # @param key
    # @return [Errors | nil] a nested error
    def [](key)
      if result = @children[key]
        result.errors
      end
    end

    # Yields all steps (including nested steps) that caused an error.
    # @yield [step, path]
    # @yieldparam [Step] step
    # @yieldparam [Array] path
    # @return [self | Enumerator] an enumerator if no block is given.
    def each_step_with_path
      return enum_for(:each_step_with_path) if !block_given?

      @steps.each do |step|
        yield step, []
      end

      @children.each do |key, result|
        result.errors.each_step_with_path do |step, path|
          yield step, [key, *path]
        end
      end
    end

    # Adds a step as an error.
    # @param step [Step]
    # @api private
    def add_step(step)
      @steps << step
      self
    end

    # Adds another +Errors+ object as a child error.
    # @param key
    # @param other [Errors]
    # @api private
    def add_child(key, result)
      if @children.has_key?(key)
        raise ArgumentError, "a result with key #{key.inspect} already exists"
      end
      @children[key] = result
      self
    end

    # Merges another +Errors+ object into this one.
    # @param other [Errors]
    # @api private
    def merge!(other)
      @steps.concat(other.steps)
      @children.merge!(other.children) do |key|
        raise ArgumentError, "duplicate errors for key #{key.inspect}"
      end
      self
    end
  end

  # An +Errors+ object which is empty and immutable.
  EMPTY_ERRORS = Errors.new.deep_freeze

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
    # @return [Array<StepError | NestedError>]
    def errors
      @result.errors
    end
  end

  # Represents a result from a validation ({Schema#validate}).
  #
  # A result consists of a {#value} and a list of {#errors} (of {StepError} or
  # {NestedError}). A result which contains *zero* errors is considered
  # {#valid?} (or a {#success?}), while a result which has *some* errors is an
  # {#error?}.
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

    # @return [Array<StepError | NestedError>] the errors
    attr_reader :errors

    # Creates a new Result with the given +value+.
    def initialize(value)
      @value = value
      @is_halted = false
      @errors = EMPTY_ERRORS
    end

    # @api private
    def mutable_errors
      if EMPTY_ERRORS.equal?(@errors)
        @errors = Errors.new
      end

      @errors
    end

    # Adds the state from a nested result:
    #
    # - If the +result+ has any errors, it will be addded as a nested error under the given key.
    # - If the +result+ is halted, this result will be halted as well.
    #
    # @param key
    # @param result [Result]
    # @return [self]
    def add_nested(key, result)
      if result.error?
        mutable_errors.add_child(key, result)
      end

      if result.halted?
        halt
      end

      self
    end

    # Yields every step which has produced an error, together with the path
    # where it happened.
    #
    # @yield [step, path]
    # @yieldparam [Step] step
    # @yieldparam [Array] path
    # @return [self | Enumerator] an enumerator if no block is given.
    def each_step_error(&blk)
      return enum_for(:each_step_error) if blk.nil?
      @errors.each_step_with_path(&blk)
      self
    end

    # Returns a flat array of all steps which has produced an error, together
    # with the path where it happened.
    def step_errors
      each_step_error.to_a
    end

    # @return [Array<String>] array of error messages.
    def error_messages
      each_step_error.map do |step, path|
        if path.any?
          "#{path.join('.')}: #{step.message}"
        else
          step.message
        end
      end
    end

    # @return [Boolean] true if the result contains any errors.
    def error?
      !@errors.empty?
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
    #       username: fetch("username") | trim | required,
    #     )
    #
    #     Advanced = form(
    #       karma: fetch("karma") | optional | number,
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
      result = @child.process(result)
      result.unhalt
      result
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
      result = @left.process(result)
      return result if result.halted?
      @right.process(result)
    end
  end

  # Step is the common class for all schemas that does actual validation
  # and transformation on the value (as opposed to just combining other
  # schemas).
  #
  # Every Step class take a +props+ Hash in their constructor and you are free
  # to store arbitrary data here. You can later access this data from the
  # {StepError} object (through {StepError#step}) and for instance use it to
  # customize error reporting.
  #
  # The +:message+ property will override the default error message
  # produced by {StepError#message} and {Step#message}.
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
    # @return [Hash] properties for this step.
    attr_reader :props

    # @param props [Hash] properties for this step.
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

    # The type of this step.
    #
    # This will return the +:type+ property, failing back to +nil+ if it's
    # missing.
    #
    # @return [String, nil] The error message.
    def type
      @props[:type]
    end

    # Implements the {Schema#process} interface.
    def process(result)
      @processor.call(result)
    end
  end

  # @see Builder.form
  class Form < Schema
    Field = Struct.new(:key, :setter, :schema)

    def initialize(&blk)
      @constructor = blk || proc { Hash.new }
      @fields = []
    end

    def with_key(key, schema)
      setter = proc { |obj, val| obj[key] = val }
      @fields << Field.new(key, setter, schema)
      self
    end

    def with_keys(hash)
      hash.each { |key, schema| with_key(key, schema) }
      self
    end

    def with_attr(name, schema)
      setter_method_name = :"#{name}="
      setter = proc { |obj, val| obj.send(setter_method_name, val) }
      @fields << Field.new(name, setter, schema)
      self
    end

    def with_attrs(hash)
      hash.each { |name, schema| with_attr(name, schema) }
      self
    end

    def process(result)
      old_value = result.value
      new_value = result.value = @constructor.call

      @fields.each do |field|
        field_result = field.schema.validate(old_value)
        field.setter.call(new_value, field_result.value)
        result.add_nested(field.key, field_result)
      end

      result
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
      left_result = @left.validate(result.value)
      right_result = @right.validate(result.value)

      result.mutable_errors.merge!(left_result.errors) if left_result.error?
      result.mutable_errors.merge!(right_result.errors) if right_result.error?

      result.value = {}
      result.value.update(left_result.value) if !left_result.halted?
      result.value.update(right_result.value) if !right_result.halted?
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
      new_value = []

      result.value.each_with_index.map do |element, idx|
        element_result = @element_schema.validate(element)
        new_value << element_result.value
        result.add_nested(idx, element_result)
      end

      result.value = new_value
      result
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

    # The fetch schema extracts a field (given by +key+) from a value by
    # using +#fetch+.
    #
    # This is strictly equivalent to:
    #
    #   transform { |value| value.fetch(key) { error_is_produced } }
    #
    # @param key The key which will be extracted. This value is stored under
    #   the +:key+ parameter in the returned {Step#props}.
    # @option props :type (:fetch)
    # @option props :message ("must be present")
    # @return [Step]
    def fetch(key, **props, &blk)
      blk ||= proc { StepError }
      transform(type: :fetch, key: key, message: "must be present", **props) do |value|
        value.fetch(key, &blk)
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
        result
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
          next StepError
        end

        if scale = props[:scale]
          num *= scale
        end

        case convert = props.fetch(:convert, :integer)
        when :integer
          if num.denominator == 1
            num.numerator
          else
            StepError
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
          BigDecimal(num, value.size)
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
    def form(fields = {}, &blk)
      Form.new(&blk).with_keys(fields)
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
          result.mutable_errors.add_step(step)
        end
        result
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
        if StepError.equal?(new_value)
          result.halt
          result.mutable_errors.add_step(step)
        else
          result.value = new_value
        end
        result
      end
    end
  end
end

