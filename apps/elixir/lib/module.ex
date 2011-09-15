module Module
  module BlankSlate
  end

  % This module keeps all the methods that are automatically
  % generated on compilation time but needs to be available
  % during module definition.
  module Definition
    def __module_name__
      [_,_|name] = Erlang.atom_to_list(Erlang.element(2, self))
      Erlang.list_to_atom(name)
    end

    def __mixins__
      Erlang.elixir_module_behavior.mixins(self)
    end

    def __module__
      self
    end

    def __local_methods__
      []
    end

    def __mixin_methods__
      Erlang.elixir_methods.mixin_methods(self)
    end
  end

  % This module is included temporarily during method
  % definition with the *using* feature.
  module Using
    def mixin(module)
      Erlang.elixir_module_using.mixin(self, module)
    end

    def using(module)
      Erlang.elixir_module_using.using(self, module)
    end

    def __using__
      Erlang.ets.lookup_element(Erlang.element(3, self), 'using, 2)
    end

    % Delegate the given methods to the given expression.
    %
    % ## Examples
    %
    %     module Counter
    %       def one; 1; end
    %       def two; 2; end
    %       def three; 3; end
    %       def sum(a, b) a+b; end
    %     end
    %
    %     module Delegator
    %       delegate ['one/0, 'two/0, 'three/0, 'sum/2], 'to: "Counter"
    %     end
    %
    %     Delegator.one       % => 1
    %     Delegator.sum(1, 2) % => 3
    %
    % Notice that the value given to 'to can be any expression:
    %
    %     module Three
    %       delegate ['abs/0], 'to: "(2-5)"
    %     end
    %
    %     Three.abs  % => 3
    %
    def delegate(pairs, options)
      object = options['to]

      pairs.each do ({name, arity})
        args = arity.times [], do (i, acc)
          ["x#{i}"|acc]
        end

        args_string = args.join(",")

        module_eval __FILE__, __LINE__ + 1, ~~ELIXIR
  def #{name}(#{args_string})
    #{object}.#{name}(#{args_string})
  end
~~
      end
    end

    % Receives a list of names and define a method for each name that
    % reads its respective instance variable.
    %
    % ## Example
    %
    %     module Car
    %       attr_reader ['color]
    %
    %       def initialize(color)
    %         @('color: color)
    %       end
    %     end
    %
    %     car = Car.new 'red
    %     car.color   % => 'red
    %
    def attr_reader(names)
      names.each do (name)
        module_eval __FILE__, __LINE__ + 1, ~~ELIXIR
  def #{name}
    @#{name}
  end
~~
      end
    end

    def attr_writer(names)
      names.each do (name)
        module_eval __FILE__, __LINE__ + 1, ~~ELIXIR
  def #{name}(value)
    @('#{name}, value)
  end
~~
      end
    end

    def attr_accessor(names)
      attr_reader names
      attr_writer names
    end

    % Returns the current method visibility.
    def __visibility__
      Erlang.elixir_module_using.get_visibility(self)
    end

    % Mark all methods defined next as public.
    def public
      Erlang.elixir_module_using.set_visibility(self, 'public)
    end

    % Mark all methods defined next as private.
    def private
      Erlang.elixir_module_using.set_visibility(self, 'private)
    end

    % Receives a file, line and evaluates the given string in the context
    % of the module. This is good for dynamic method definition:
    %
    % ## Examples
    %
    %     module MyMethods
    %
    %       ["foo", "bar", "baz"].each -> (m)
    %         self.module_eval __FILE__, __LINE__ + 1, ~~ELIXIR
    %       def #{m}
    %         @#{m}
    %       end
    %     ~~
    %       end
    %
    %     end
    % 
    def module_eval(file, line, string)
      Erlang.elixir_module_using.module_eval(self, string, file, line)
    end

    % Allow to add a method to the module using Erlang's abstract form.
    % The method automatically receives self as first argument.
    def define_erlang_method(file, line, method, arity, clauses)
      Erlang.elixir_module_using.define_erlang_method(self, file, line, method, arity, clauses)
    end

    % Alias a local method. Aliasing a method defined in another module is done
    % by delegation.
    def alias_local(old, new, arity)
      Erlang.elixir_module_using.alias_local(self, __FILE__, old, new, arity)
    end
  end

  module Behavior
    %% INTROSPECTION METHODS

    % The following methods are generated automatically:
    % def __module__()
    % def __module_name__()
    % def __mixins__()
    % def __local_methods__()
    % def __mixin_methods__()

    def __module__?
      Erlang.elixir_module_behavior.is_module(self)
    end

    def inspect
      name = self.__module_name__
      if __module__?
        name.to_s
      else
        "<##{name} #{get_ivars.inspect}>"
      end
    end

    def to_s
      self.inspect
    end

    %% INTERNAL VARIABLE METHODS

    def get_ivar(name)
      Erlang.elixir_module_behavior.get_ivar(self, name)
    end

    % Returns an `OrderedDict` with all variable names and values.
    %
    % ## Example
    %
    %     module Foo
    %       def __bound__
    %         @('bar: 1, 'baz: 2)
    %       end
    %     end
    %
    %     #Foo().get_ivars % => { 'bar: 1, 'baz: 2 }
    %
    def get_ivars
      OrderedDict.new Erlang.elixir_module_behavior.data(self)
    end

    def set_ivar(name, value)
      Erlang.elixir_module_behavior.set_ivar(self, name, value)
    end

    def set_ivars(value)
      Erlang.elixir_module_behavior.set_ivars(self, value)
    end

    def update_ivar(name, fun)
      Erlang.elixir_module_behavior.update_ivar(self, name, fun)
    end

    def remove_ivar(name)
      Erlang.elixir_module_behavior.remove_ivar(self, name)
    end

    %% DYNAMIC DISPATCHING

    def __bind__(to, args := [])
      Erlang.elixir_module_behavior.bind(self, to, args)
    end

    def respond_to?(method, arity)
      case self
      match { 'elixir_slate__, mod, _ }
        Erlang.apply(mod, '__elixir_respond_to__, [method, arity])
      match { 'elixir_module__, mod, data }
        case Erlang.is_atom(data)
        match true
          __mixin_methods__.include?({method, arity})
        else
          Erlang.apply(mod, '__elixir_respond_to__, [method, arity])
        end
      else
        mod = Erlang.elixir_dispatch.builtin_mixin(self)
        Erlang.apply(mod, '__elixir_respond_to__, [method, arity])
      end
    end

    def send(method, args := [])
      Erlang.elixir_dispatch.dispatch(self, method, args)
    end

    def __send__(method, args := [])
      Erlang.elixir_dispatch.dispatch(self, method, args)
    end

    %% EXCEPTION RELATED

    def error(reason)
      Erlang.error(reason)
    end

    def throw(reason)
      Erlang.throw(reason)
    end

    def exit(reason)
      Erlang.exit(reason)
    end

    %% MODULE HOOKS

    % Hook invoked whenever this module is added as a mixin.
    % It receives the target module where the mixin is being added
    % as parameter and must return an module of the same kind.
    %
    % ## Example
    %
    % As an example, let's simply create a module that sets an
    % instance variable on the target object:
    %
    %     module Foo
    %       def __mixed_in__(base)
    %         base.set_ivar('baz, 13)
    %       end
    %     end
    %
    %     module Baz
    %       mixin Foo
    %       IO.puts @baz   % => 13
    %     end
    %
    def __mixed_in__(base)
      base
    end

    % Hook invoked whenever a module is added as with *using*.
    def __using__(base)
      base
    end

    % Hook invoked whenever a module is bound.
    def __bound__
      self
    end

    % Hook invoked whenever a module is on definition.
    def __defining__
      self
    end
  end

  % Returns a blank slate.
  def blank_slate
    {'elixir_slate__, 'exModule::BlankSlate, []}
  end

  % Returns the stacktrace filtered with Elixir specifics.
  def stacktrace
    filter_stacktrace Erlang.get_stacktrace
  end

  def eval(code)
    { result, _ } = Erlang.elixir.eval(code.to_char_list)
    result
  end

  def eval(code, binding)
    { result, _ } = Erlang.elixir.eval(code.to_char_list, binding.to_list)
    result
  end

  def eval(file, line, code, binding)
    { result, _ } = Erlang.elixir.eval(code.to_char_list, binding.to_list, file.to_char_list, line)
    result
  end

  % Set the following methods to private.
  Erlang.elixir_module_using.set_visibility(self, 'private)

  def filter_stacktrace(stacktrace)
    filter_stacktrace(stacktrace, [])
  end

  def filter_stacktrace([{raw_module, function, raw_arity}|t], buffer)
    if filtered = filter_stacktrace_module(raw_module.to_char_list)
      module = filtered
      arity = if Erlang.is_integer(raw_arity)
        raw_arity - 1
      else
        raw_arity
      end
    else
      module = raw_module
      arity = raw_arity
    end

    filter_stacktrace t, [{module, function, arity}|buffer]
  end

  def filter_stacktrace([], buffer)
    buffer.reverse
  end

  def filter_stacktrace_module([$e, $x, h|t]) when h >= $A andalso h <= $Z
    Atom.from_char_list [h|t]
  end

  def filter_stacktrace_module(_)
    nil
  end
end