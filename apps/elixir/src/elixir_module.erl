-module(elixir_module).
-export([scope_for/2, transform/4, compile/5]).
-include("elixir.hrl").

% Returns the new module name based on the previous scope.
scope_for([], Name) -> Name;
scope_for(Scope, Name) -> ?ELIXIR_ATOM_CONCAT([Scope, "::", Name]).

%% MODULE BUILDING

% Build a template of an object or module used on compilation.
build_module(ElixirName) ->
  Name   = ?ELIXIR_ERL_MODULE(ElixirName),
  Mixins = default_mixins(ElixirName),
  Using  = default_using(ElixirName),
  Data   = default_data(),

  AttributeTable = ?ELIXIR_ATOM_CONCAT([a, Name]),
  ets:new(AttributeTable, [set, named_table, private]),

  ets:insert(AttributeTable, { mixins, Mixins }),
  ets:insert(AttributeTable, { using,  Using }),
  ets:insert(AttributeTable, { data,   Data }),

  #elixir_module__{name=Name, data=AttributeTable}.

default_mixins(ElixirName) ->
  case bootstrap_modules(ElixirName) of
    true  -> [];
    false -> ['Module::Using', 'Module::Behavior']
  end.

default_using(_) -> ['Module::Using'].
default_data()   -> orddict:new().

bootstrap_modules('Module::BlankSlate') -> true;
bootstrap_modules('Module::Definition') -> true;
bootstrap_modules('Module::Behavior')   -> true;
bootstrap_modules('Module::Using')      -> true;
bootstrap_modules(_)                    -> false.

%% TRANSFORMATION AND COMPILATION

% Generates module transform. It wraps the module definition into
% a function that will be invoked by compile/5 passing self as argument.
% We need to wrap them into anonymous functions so nested module
% definitions have the variable self shadowed.
transform(Line, ElixirName, Body, S) ->
  Filename = S#elixir_scope.filename,
  Clause = { clause, Line, [{var, Line, self}], [], Body },
  Fun = { 'fun', Line, { clauses, [Clause] } },
  Args = [{integer, Line, Line}, {string, Line, Filename},
    {var, Line, self}, {atom, Line, ElixirName}, Fun],
  ?ELIXIR_WRAP_CALL(Line, ?MODULE, compile, Args).

% Main entry point for compilation. Receives the function and
% execute it passing the module.
compile(Line, Filename, _Current, ElixirName, Fun) ->
  Module = build_module(ElixirName),
  MethodTable = elixir_def_method:new_method_table(ElixirName),

  try
    Result = Fun(Module),
    case bootstrap_modules(ElixirName) of
      true  -> [];
      false -> elixir_dispatch:dispatch(Module, '__defining__', [])
    end,
    compile_module(Line, Filename, ElixirName, Module, MethodTable),
    Result
  after
    ets:delete(?ELIXIR_ATOM_CONCAT([aex,ElixirName])),
    ets:delete(?ELIXIR_ATOM_CONCAT([mex,ElixirName]))
  end.

% Handle compilation logic specific to objects or modules.
compile_module(Line, Filename, ElixirName, #elixir_module__{name=Name, data=AttributeTable} = Module, MethodTable) ->
  RawMixins   = destructive_read(AttributeTable, mixins),
  Using       = destructive_read(AttributeTable, using),
  Data        = destructive_read(AttributeTable, data),
  TempMixins  = RawMixins -- Using,
  FinalMixins = [ElixirName|TempMixins],
  Bootstrap = bootstrap_modules(ElixirName),

  case Bootstrap of
    true  -> [];
    false -> elixir_def_method:flat_module(Line, TempMixins, MethodTable)
  end,

  {P0, Inherited, F0} = elixir_def_method:unwrap_stored_methods(MethodTable),

  { P1, F1 } = add_extra_function(Bootstrap, P0, F0, {'__mixins__',1},        mixins_function(Line, Module, FinalMixins)),
  { P2, F2 } = add_extra_function(Bootstrap, P1, F1, {'__module_name__',1},   module_name_function(Line, Module)),
  { P3, F3 } = add_extra_function(Bootstrap, P2, F2, {'__module__',1},        module_function(Line, Module, Data)),

  % Do not change this order:
  { P4, F4 } = add_extra_function(Bootstrap, P3, F3, {'__local_methods__',1}, local_methods_function(Line, P3)),
  { P5, F5 } = add_extra_function(Bootstrap, P4, F4, {'__mixin_methods__',1}, mixin_methods_function(Line, P4 ++ Inherited)),

  All = P5 ++ Inherited,
  Export = [{'__elixir_exported__',2},{'__elixir_respond_to__',2} | All],

  Base = [
    {attribute, Line, module, Name},
    {attribute, Line, file, {Filename,Line}},
    {attribute, Line, exfile, {Filename,Line}},
    {attribute, Line, compile, no_auto_import()},
    {attribute, Line, export, Export},
    exported_function(Line, Module), respond_to_function(Line, All) | F5
  ],

  Transform = fun(X, Acc) -> [transform_attribute(Line, X)|Acc] end,
  Forms = ets:foldr(Transform, Base, AttributeTable),
  load_form(Forms, Filename).

% Compile and load given forms as an Erlang module.
load_form(Forms, Filename) ->
  case compile:forms(Forms, [return]) of
    {ok, ModuleName, Binary, Warnings} ->
      case get(elixir_compiled) of
        Current when is_list(Current) ->
          put(elixir_compiled, [{ModuleName,Binary}|Current]);
        _ ->
          []
      end,
      format_warnings(Filename, Warnings),
      code:soft_purge(ModuleName),
      code:load_binary(ModuleName, Filename, Binary);
    {error, Errors, Warnings} ->
      format_warnings(Filename, Warnings),
      format_errors(Filename, Errors)
  end.

%% BUILD AND LOAD HELPERS

destructive_read(Table, Attribute) ->
  Value = ets:lookup_element(Table, Attribute, 2),
  ets:delete(Table, Attribute),
  Value.

%% ATTRIBUTES MANIPULATION

no_auto_import() ->
  {no_auto_import, [
    {size, 1}, {length, 1}, {error, 2}, {self, 1}, {put, 2},
    {get, 1}, {exit, 1}, {exit, 2}
  ]}.

transform_attribute(Line, X) ->
  {attribute, Line, element(1, X), element(2, X)}.

% EXTRA FUNCTIONS

add_extra_function(Bootstrap, Exported, Functions, Pair, Contents) ->
  case lists:member(Pair, Exported) of
    true ->
      case Bootstrap of
        true  -> { Exported, Functions };
        false -> elixir_errors:error({internal_method_overridden, Pair})
      end;
    false -> { [Pair|Exported], [Contents|Functions] }
  end.

exported_function(Line, #elixir_module__{name=Name}) ->
  { function, Line, '__elixir_exported__', 2,
    [{ clause, Line, [{var,Line,function},{var,Line,arity}], [], [
      ?ELIXIR_WRAP_CALL(
        Line, erlang, function_exported,
        [{atom,Line,Name},{var,Line,function},{var,Line,arity}]
      )
    ]}]
  }.

respond_to_function(Line, All) ->
  Clauses = lists:map(fun({Name,Arity}) ->
    { clause, Line, [{atom,Line,Name}, {integer,Line,Arity-1}], [], [{atom,Line,true}] }
  end, All),

  { function, Line, '__elixir_respond_to__', 2,
    Clauses ++ [{ clause, Line, [{var,Line,'_'},{var,Line,'_'}], [], [{atom,Line,false}] }]
  }.

local_methods_function(Line, Public) ->
  MixinMethods = {'__mixin_methods__',1},
  FinalPublic = [MixinMethods,{'__local_methods__',1}|lists:delete(MixinMethods,Public)],
  return_tuples_function(Line, '__local_methods__', FinalPublic).

mixin_methods_function(Line, Export) ->
  FinalExport = [{'__mixin_methods__',1}|Export],
  return_tuples_function(Line, '__mixin_methods__', FinalExport).

module_function(Line, #elixir_module__{name=Name}, Data) ->
  Snapshot = #elixir_module__{name=Name, data=Data},
  Reverse = elixir_tree_helpers:abstract_syntax(Snapshot),
  { function, Line, '__module__', 1,
    [{ clause, Line, [{var,Line,'_'}], [], [Reverse]}]
  }.

mixins_function(Line, _Module, Mixins) ->
  { MixinsTree, [] } = elixir_tree_helpers:build_list(fun(X,Y) -> {{atom,Line,X},Y} end, Mixins, Line, []),
  { function, Line, '__mixins__', 1,
    [{ clause, Line, [{var,Line,'_'}], [], [MixinsTree]}]
  }.

module_name_function(Line, #elixir_module__{name=Name}) ->
  { function, Line, '__module_name__', 1,
    [{ clause, Line, [{var,Line,'_'}], [], [{atom,Line,?ELIXIR_EX_MODULE(Name)}]}]
  }.

return_tuples_function(Line, MethodName, Tuples) ->
  { FinalTuples, [] } = elixir_tree_helpers:build_list(fun({Name,Arity},Y) ->
    {{tuple,Line,[{atom,Line,Name},{integer,Line,Arity-1}]},Y}
  end, Tuples, Line, []),
  { function, Line, MethodName, 1,
    [{ clause, Line, [{var,Line,'_'}], [], [FinalTuples]}]
  }.

% ERROR HANDLING

format_errors(_Filename, []) ->
  exit({nocompile, "compilation failed but no error was raised"});

format_errors(Filename, Errors) ->
  lists:foreach(fun ({_, Each}) ->
    lists:foreach(fun (Error) -> elixir_errors:handle_file_error(Filename, Error) end, Each)
  end, Errors).

format_warnings(Filename, Warnings) ->
  lists:foreach(fun ({_, Each}) ->
    lists:foreach(fun (Warning) -> elixir_errors:handle_file_warning(Filename, Warning) end, Each)
  end, Warnings).