require 'chef_compat/copied_from_chef'
class Chef
  module ::ChefCompat
    module CopiedFromChef
      #
      # Author:: John Keiser <jkeiser@chef.io>
      # Copyright:: Copyright 2015-2016, John Keiser.
      # License:: Apache License, Version 2.0
      #
      # Licensed under the Apache License, Version 2.0 (the "License");
      # you may not use this file except in compliance with the License.
      # You may obtain a copy of the License at
      #
      #     http://www.apache.org/licenses/LICENSE-2.0
      #
      # Unless required by applicable law or agreed to in writing, software
      # distributed under the License is distributed on an "AS IS" BASIS,
      # WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
      # See the License for the specific language governing permissions and
      # limitations under the License.
      #

      require 'chef_compat/copied_from_chef/chef/delayed_evaluator'

      class Chef < (defined?(::Chef) ? ::Chef : Object)
        #
        # Type and validation information for a property on a resource.
        #
        # A property named "x" manipulates the "@x" instance variable on a
        # resource.  The *presence* of the variable (`instance_variable_defined?(@x)`)
        # tells whether the variable is defined; it may have any actual value,
        # constrained only by validation.
        #
        # Properties may have validation, defaults, and coercion, and have full
        # support for lazy values.
        #
        # @see Chef::Resource.property
        # @see Chef::DelayedEvaluator
        #
        class Property < (defined?(::Chef::Property) ? ::Chef::Property : Object)
          #
          # Create a reusable property type that can be used in multiple properties
          # in different resources.
          #
          # @param options [Hash<Symbol,Object>] Validation options. See Chef::Resource.property for
          #   the list of options.
          #
          # @example
          #   Property.derive(default: 'hi')
          #
          def self.derive(**options)
            new(**options)
          end

          #
          # Create a new property.
          #
          # @param options [Hash<Symbol,Object>] Property options, including
          #   control options here, as well as validation options (see
          #   Chef::Mixin::ParamsValidate#validate for a description of validation
          #   options).
          #   @option options [Symbol] :name The name of this property.
          #   @option options [Class] :declared_in The class this property comes from.
          #   @option options [Symbol] :instance_variable_name The instance variable
          #     tied to this property. Must include a leading `@`. Defaults to `@<name>`.
          #     `nil` means the property is opaque and not tied to a specific instance
          #     variable.
          #   @option options [Boolean] :desired_state `true` if this property is part of desired
          #     state. Defaults to `true`.
          #   @option options [Boolean] :identity `true` if this property is part of object
          #     identity. Defaults to `false`.
          #   @option options [Boolean] :name_property `true` if this
          #     property defaults to the same value as `name`. Equivalent to
          #     `default: lazy { name }`, except that #property_is_set? will
          #     return `true` if the property is set *or* if `name` is set.
          #   @option options [Object] :default The value this property
          #     will return if the user does not set one. If this is `lazy`, it will
          #     be run in the context of the instance (and able to access other
          #     properties) and cached. If not, the value will be frozen with Object#freeze
          #     to prevent users from modifying it in an instance.
          #   @option options [Proc] :coerce A proc which will be called to
          #     transform the user input to canonical form. The value is passed in,
          #     and the transformed value returned as output. Lazy values will *not*
          #     be passed to this method until after they are evaluated. Called in the
          #     context of the resource (meaning you can access other properties).
          #   @option options [Boolean] :required `true` if this property
          #     must be present; `false` otherwise. This is checked after the resource
          #     is fully initialized.
          #
          def initialize(**options)
            super if defined?(::Chef::Property)
            options.each { |k, v| options[k.to_sym] = v; options.delete(k) if k.is_a?(String) }
            @options = options
            options[:name] = options[:name].to_sym if options[:name]
            options[:instance_variable_name] = options[:instance_variable_name].to_sym if options[:instance_variable_name]

            # Replace name_attribute with name_property
            if options.key?(:name_attribute)
              # If we have both name_attribute and name_property and they differ, raise an error
              if options.key?(:name_property)
                fail ArgumentError, "Cannot specify both name_property and name_attribute together on property #{self}."
              end
              # replace name_property with name_attribute in place
              options = Hash[options.map { |k, v| k == :name_attribute ? [:name_property, v] : [k, v] }]
              @options = options
            end

            # Only pick the first of :default, :name_property and :name_attribute if
            # more than one is specified.
            if options.key?(:default) && options[:name_property]
              if options[:default].nil? || options.keys.index(:name_property) < options.keys.index(:default)
                options.delete(:default)
                preferred_default = :name_property
              else
                options.delete(:name_property)
                preferred_default = :default
              end
              Chef.log_deprecation("Cannot specify both default and name_property together on property #{self}. Only one (#{preferred_default}) will be obeyed. In Chef 13, this will become an error. Please remove one or the other from the property.")
            end

            # Validate the default early, so the user gets a good error message, and
            # cache it so we don't do it again if so
            begin
              # If we can validate it all the way to output, do it.
              @stored_default = input_to_stored_value(nil, default, is_default: true)
            rescue Chef::Exceptions::CannotValidateStaticallyError
              # If the validation is not static (i.e. has procs), we will have to
              # coerce and validate the default each time we run
            end
          end

          def to_s
            "#{name || '<property type>'}#{declared_in ? " of resource #{declared_in.resource_name}" : ''}"
          end

          #
          # The name of this property.
          #
          # @return [String]
          #
          def name
            options[:name]
          end

          #
          # The class this property was defined in.
          #
          # @return [Class]
          #
          def declared_in
            options[:declared_in]
          end

          #
          # The instance variable associated with this property.
          #
          # Defaults to `@<name>`
          #
          # @return [Symbol]
          #
          def instance_variable_name
            if options.key?(:instance_variable_name)
              options[:instance_variable_name]
            elsif name
              :"@#{name}"
            end
          end

          #
          # The raw default value for this resource.
          #
          # Does not coerce or validate the default. Does not evaluate lazy values.
          #
          # Defaults to `lazy { name }` if name_property is true; otherwise defaults to
          # `nil`
          #
          def default
            return options[:default] if options.key?(:default)
            return Chef::DelayedEvaluator.new { name } if name_property?
            nil
          end

          #
          # Whether this is part of the resource's natural identity or not.
          #
          # @return [Boolean]
          #
          def identity?
            options[:identity]
          end

          #
          # Whether this is part of desired state or not.
          #
          # Defaults to true.
          #
          # @return [Boolean]
          #
          def desired_state?
            return true unless options.key?(:desired_state)
            options[:desired_state]
          end

          #
          # Whether this is name_property or not.
          #
          # @return [Boolean]
          #
          def name_property?
            options[:name_property]
          end

          #
          # Whether this property has a default value.
          #
          # @return [Boolean]
          #
          def has_default?
            options.key?(:default) || name_property?
          end

          #
          # Whether this property is required or not.
          #
          # @return [Boolean]
          #
          def required?
            options[:required]
          end

          #
          # Validation options.  (See Chef::Mixin::ParamsValidate#validate.)
          #
          # @return [Hash<Symbol,Object>]
          #
          def validation_options
            @validation_options ||= options.reject do |k, _v|
              [:declared_in, :name, :instance_variable_name, :desired_state, :identity, :default, :name_property, :coerce, :required].include?(k)
            end
          end

          #
          # Handle the property being called.
          #
          # The base implementation does the property get-or-set:
          #
          # ```ruby
          # resource.myprop # get
          # resource.myprop value # set
          # ```
          #
          # Subclasses may implement this with any arguments they want, as long as
          # the corresponding DSL calls it correctly.
          #
          # @param resource [Chef::Resource] The resource to get the property from.
          # @param value The value to set (or NOT_PASSED if it is a get).
          #
          # @return The current value of the property. If it is a `set`, lazy values
          #   will be returned without running, validating or coercing. If it is a
          #   `get`, the non-lazy, coerced, validated value will always be returned.
          #
          def call(resource, value = NOT_PASSED)
            return get(resource) if value == NOT_PASSED

            if value.nil?
              # In Chef 12, value(nil) does a *get* instead of a set, so we
              # warn if the value would have been changed. In Chef 13, it will be
              # equivalent to value = nil.
              result = get(resource)

              # Warn about this becoming a set in Chef 13.
              begin
                input_to_stored_value(resource, value)
                # If nil is valid, and it would change the value, warn that this will change to a set.
                unless result.nil?
                  Chef.log_deprecation("An attempt was made to change #{name} from #{result.inspect} to nil by calling #{name}(nil). In Chef 12, this does a get rather than a set. In Chef 13, this will change to set the value to nil.")
                end
              rescue Chef::Exceptions::DeprecatedFeatureError
                raise
              rescue
                # If nil is invalid, warn that this will become an error.
                Chef.log_deprecation("nil is an invalid value for #{self}. In Chef 13, this warning will change to an error. Error: {$ERROR_INFO}")
              end

              result
            else
              # Anything else, such as myprop(value) is a set
              set(resource, value)
            end
          end

          #
          # Get the property value from the resource, handling lazy values,
          # defaults, and validation.
          #
          # - If the property's value is lazy, it is evaluated, coerced and validated.
          # - If the property has no value, and is required, raises ValidationFailed.
          # - If the property has no value, but has a lazy default, it is evaluated,
          #   coerced and validated. If the evaluated value is frozen, the resulting
          # - If the property has no value, but has a default, the default value
          #   will be returned and frozen. If the default value is lazy, it will be
          #   evaluated, coerced and validated, and the result stored in the property.
          # - If the property has no value, but is name_property, `resource.name`
          #   is retrieved, coerced, validated and stored in the property.
          # - Otherwise, `nil` is returned.
          #
          # @param resource [Chef::Resource] The resource to get the property from.
          #
          # @return The value of the property.
          #
          # @raise Chef::Exceptions::ValidationFailed If the value is invalid for
          #   this property, or if the value is required and not set.
          #
          def get(resource)
            # If it's set, return it (and evaluate any lazy values)
            if is_set?(resource)
              value = get_value(resource)
              value = stored_value_to_output(resource, value)

            else
              # We are getting the default value.

              # If the user does something like this:
              #
              # ```
              # class MyResource < Chef::Resource
              #   property :content
              #   action :create do
              #     file '/x.txt' do
              #       content content
              #     end
              #   end
              # end
              # ```
              #
              # It won't do what they expect. This checks whether you try to *read*
              # `content` while we are compiling the resource.
              if resource.respond_to?(:resource_initializing) &&
                 resource.resource_initializing &&
                 resource.respond_to?(:enclosing_provider) &&
                 resource.enclosing_provider &&
                 resource.enclosing_provider.new_resource &&
                 resource.enclosing_provider.new_resource.respond_to?(name)
                Chef::Log.warn("#{Chef::Log.caller_location}: property #{name} is declared in both #{resource} and #{resource.enclosing_provider}. Use new_resource.#{name} instead. At #{Chef::Log.caller_location}")
              end

              if has_default?
                # If we were able to cache the stored_default, grab it.
                value = if defined?(@stored_default)
                          @stored_default
                        else
                          # Otherwise, we have to validate it now.
                          input_to_stored_value(resource, default, is_default: true)
                end
                value = stored_value_to_output(resource, value, is_default: true)

                # If the value is mutable (non-frozen), we set it on the instance
                # so that people can mutate it.  (All constant default values are
                # frozen.)
                set_value(resource, value) if !value.frozen? && !value.nil?

                value

              elsif required?
                fail Chef::Exceptions::ValidationFailed, "#{name} is required"
              end
            end
          end

          #
          # Set the value of this property in the given resource.
          #
          # Non-lazy values are coerced and validated before being set. Coercion
          # and validation of lazy values is delayed until they are first retrieved.
          #
          # @param resource [Chef::Resource] The resource to set this property in.
          # @param value The value to set.
          #
          # @return The value that was set, after coercion (if lazy, still returns
          #   the lazy value)
          #
          # @raise Chef::Exceptions::ValidationFailed If the value is invalid for
          #   this property.
          #
          def set(resource, value)
            set_value(resource, input_to_stored_value(resource, value))
          end

          #
          # Find out whether this property has been set.
          #
          # This will be true if:
          # - The user explicitly set the value
          # - The property has a default, and the value was retrieved.
          #
          # From this point of view, it is worth looking at this as "what does the
          # user think this value should be." In order words, if the user grabbed
          # the value, even if it was a default, they probably based calculations on
          # it. If they based calculations on it and the value changes, the rest of
          # the world gets inconsistent.
          #
          # @param resource [Chef::Resource] The resource to get the property from.
          #
          # @return [Boolean]
          #
          def is_set?(resource)
            value_is_set?(resource)
          end

          #
          # Reset the value of this property so that is_set? will return false and the
          # default will be returned in the future.
          #
          # @param resource [Chef::Resource] The resource to get the property from.
          #
          def reset(resource)
            reset_value(resource)
          end

          #
          # Coerce an input value into canonical form for the property.
          #
          # After coercion, the value is suitable for storage in the resource.
          # You must validate values after coercion, however.
          #
          # Does no special handling for lazy values.
          #
          # @param resource [Chef::Resource] The resource we're coercing against
          #   (to provide context for the coerce).
          # @param value The value to coerce.
          #
          # @return The coerced value.
          #
          # @raise Chef::Exceptions::ValidationFailed If the value is invalid for
          #   this property.
          #
          def coerce(resource, value)
            if options.key?(:coerce)
              # If we have no default value, `nil` is never coerced or validated
              unless !has_default? && value.nil?
                value = exec_in_resource(resource, options[:coerce], value)
              end
            end
            value
          end

          #
          # Validate a value.
          #
          # Calls Chef::Mixin::ParamsValidate#validate with #validation_options as
          # options.
          #
          # @param resource [Chef::Resource] The resource we're validating against
          #   (to provide context for the validate).
          # @param value The value to validate.
          #
          # @raise Chef::Exceptions::ValidationFailed If the value is invalid for
          #   this property.
          #
          def validate(resource, value)
            # If we have no default value, `nil` is never coerced or validated
            unless value.nil? && !has_default?
              if resource
                resource.validate({ name => value }, name => validation_options)
              else
                name = self.name || :property_type
                Chef::Mixin::ParamsValidate.validate({ name => value }, name => validation_options)
              end
            end
          end

          #
          # Derive a new Property that is just like this one, except with some added or
          # changed options.
          #
          # @param options [Hash<Symbol,Object>] List of options that would be passed
          #   to #initialize.
          #
          # @return [Property] The new property type.
          #
          def derive(**modified_options)
            # Since name_property, name_attribute and default override each other,
            # if you specify one of them in modified_options it overrides anything in
            # the original options.
            options = self.options
            if modified_options.key?(:name_property) ||
               modified_options.key?(:name_attribute) ||
               modified_options.key?(:default)
              options = options.reject { |k, _v| k == :name_attribute || k == :name_property || k == :default }
            end
            self.class.new(options.merge(modified_options))
          end

          #
          # Emit the DSL for this property into the resource class (`declared_in`).
          #
          # Creates a getter and setter for the property.
          #
          def emit_dsl
            # We don't create the getter/setter if it's a custom property; we will
            # be using the existing getter/setter to manipulate it instead.
            return unless instance_variable_name

            # We prefer this form because the property name won't show up in the
            # stack trace if you use `define_method`.
            declared_in.class_eval <<-EOM, __FILE__, __LINE__ + 1
        def #{name}(value=NOT_PASSED)
          raise "Property #{name} of \#{self} cannot be passed a block! If you meant to create a resource named #{name} instead, you'll need to first rename the property." if block_given?
          self.class.properties[#{name.inspect}].call(self, value)
        end
        def #{name}=(value)
          raise "Property #{name} of \#{self} cannot be passed a block! If you meant to create a resource named #{name} instead, you'll need to first rename the property." if block_given?
          self.class.properties[#{name.inspect}].set(self, value)
        end
      EOM
          rescue SyntaxError
            # If the name is not a valid ruby name, we use define_method.
            declared_in.define_method(name) do |value = NOT_PASSED, &block|
              raise "Property #{name} of #{self} cannot be passed a block! If you meant to create a resource named #{name} instead, you'll need to first rename the property." if block
              self.class.properties[name].call(self, value)
            end
            declared_in.define_method("#{name}=") do |value, &block|
              raise "Property #{name} of #{self} cannot be passed a block! If you meant to create a resource named #{name} instead, you'll need to first rename the property." if block
              self.class.properties[name].set(self, value)
            end
          end

          protected

          #
          # The options this Property will use for get/set behavior and validation.
          #
          # @see #initialize for a list of valid options.
          #
          attr_reader :options

          #
          # Find out whether this type accepts nil explicitly.
          #
          # A type accepts nil explicitly if "is" allows nil, it validates as nil, *and* is not simply
          # an empty type.
          #
          # A type is presumed to accept nil if it does coercion (which must handle nil).
          #
          # These examples accept nil explicitly:
          # ```ruby
          # property :a, [ String, nil ]
          # property :a, [ String, NilClass ]
          # property :a, [ String, proc { |v| v.nil? } ]
          # ```
          #
          # This does not (because the "is" doesn't exist or doesn't have nil):
          #
          # ```ruby
          # property :x, String
          # ```
          #
          # These do not, even though nil would validate fine (because they do not
          # have "is"):
          #
          # ```ruby
          # property :a
          # property :a, equal_to: [ 1, 2, 3, nil ]
          # property :a, kind_of: [ String, NilClass ]
          # property :a, respond_to: [ ]
          # property :a, callbacks: { "a" => proc { |v| v.nil? } }
          # ```
          #
          # @param resource [Chef::Resource] The resource we're coercing against
          #   (to provide context for the coerce).
          #
          # @return [Boolean] Whether this value explicitly accepts nil.
          #
          # @api private
          def explicitly_accepts_nil?(resource)
            options.key?(:coerce) ||
              (options.key?(:is) && resource.send(:_pv_is, { name => nil }, name, options[:is], raise_error: false))
          end

          def get_value(resource)
            if instance_variable_name
              resource.instance_variable_get(instance_variable_name)
            else
              resource.send(name)
            end
          end

          def set_value(resource, value)
            if instance_variable_name
              resource.instance_variable_set(instance_variable_name, value)
            else
              resource.send(name, value)
            end
          end

          def value_is_set?(resource)
            if instance_variable_name
              resource.instance_variable_defined?(instance_variable_name)
            else
              true
            end
          end

          def reset_value(resource)
            if instance_variable_name
              if value_is_set?(resource)
                resource.remove_instance_variable(instance_variable_name)
              end
            else
              fail ArgumentError, "Property #{name} has no instance variable defined and cannot be reset"
            end
          end

          def exec_in_resource(resource, proc, *args)
            if resource
              value = if proc.arity > args.size
                        proc.call(resource, *args)
                      else
                        resource.instance_exec(*args, &proc)
              end
            else
              # If we don't have a resource yet, we can't exec in resource!
              fail Chef::Exceptions::CannotValidateStaticallyError, 'Cannot validate or coerce without a resource'
            end
          end

          def input_to_stored_value(resource, value, is_default: false)
            unless value.is_a?(DelayedEvaluator)
              value = coerce_and_validate(resource, value, is_default: is_default)
            end
            value
          end

          def stored_value_to_output(resource, value, is_default: false)
            # Crack open lazy values before giving the result to the user
            if value.is_a?(DelayedEvaluator)
              value = exec_in_resource(resource, value)
              value = coerce_and_validate(resource, value, is_default: is_default)
            end
            value
          end

          # Coerces and validates the value. If the value is a default, it will warn
          # the user that invalid defaults are bad mmkay, and return it as if it were
          # valid.
          def coerce_and_validate(resource, value, is_default: false)
            result = coerce(resource, value)
            begin
              # If the input is from a default, we need to emit an invalid default warning on validate.
              validate(resource, result)
            rescue Chef::Exceptions::CannotValidateStaticallyError
              # This one gets re-raised
              raise
            rescue
              # Anything else is just an invalid default: in those cases, we just
              # warn and return the (possibly coerced) value to the user.
              if is_default
                if value.nil?
                  Chef.log_deprecation("Default value nil is invalid for property #{self}. Possible fixes: 1. Remove 'default: nil' if nil means 'undefined'. 2. Set a valid default value if there is a reasonable one. 3. Allow nil as a valid value of your property (for example, 'property #{name.inspect}, [ String, nil ], default: nil'). Error: {$ERROR_INFO}")
                else
                  Chef.log_deprecation("Default value #{value.inspect} is invalid for property #{self}. In Chef 13 this will become an error: {$ERROR_INFO}.")
                end
              else
                raise
              end
            end

            result
          end
        end
      end
    end
  end
end
