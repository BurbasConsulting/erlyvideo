% A bunch of helpers to help to deal with errors in Elixir source code.
% This is not exposed in the Elixir language.
-module(elixir_errors).
-export([error/1, file_format/3, syntax_error/3, syntax_error/4, handle_file_warning/2,
  handle_file_error/2, format_error/2, format_error/1]).
-include("elixir.hrl").

error(Reason) -> erlang:error(Reason).

file_format(Line, Filename, Message) ->
  lists:flatten(io_lib:format("~ts:~w: ~ts", [Filename, Line, Message])).

syntax_error(Line, Filename, Token) ->
  syntax_error(Line, Filename, Token, "").

syntax_error(Line, Filename, user, Token) ->
  syntax_error(Line, Filename, Token, "");

syntax_error(Line, Filename, Error, Token) ->
  Message = if
    (Token == []) and (Error == "syntax error before:") -> <<"syntax error">>;
    is_atom(Error) -> atom_to_binary(Error, utf8);
    true -> iolist_to_binary(Error)
  end,
  elixir_errors:error({badsyntax, {Line, iolist_to_binary(Filename), Message, iolist_to_binary(Token)}}).

% Handle warnings

handle_file_warning(_Filename, {_Line,_,{unused_var,self}}) ->
  [];

handle_file_warning(Filename, {Line,Module,{unused_var,Var} = Desc}) ->
  case hd(atom_to_list(Var)) == $X of
    true  -> [];
    false -> io:format(file_format(Line, Filename, format_error(Module, Desc)) ++ [$\n])
  end;

handle_file_warning(_Filename, {_Line,_,nomatch_clause_type}) ->
  [];

handle_file_warning(Filename, {Line,Module,Desc}) ->
  Message = format_error(Module, Desc),
  io:format(file_format(Line, Filename, Message) ++ [$\n]).

% Handle errors

handle_file_error(Filename, {Line,Module,Desc}) ->
  elixir_errors:error({badform, { Line, list_to_binary(Filename), Module, Desc }}).

% Format each error or warning in the format { Line, Module, Desc }

format_error(_, {undefined_function, {Name, Arity}}) ->
  io_lib:format("undefined local method ~s/~w", [Name, Arity-1]);

format_error(_, {changed_visibility,{Name,Visibility}}) ->
  io_lib:format("method ~s already defined with visibility ~s", [Name, Visibility]);

format_error(_, {unused_function, {Name, Arity}}) ->
  io_lib:format("unused local method ~s/~w", [Name, Arity-1]);

format_error(_, {unbound_variable, Name}) ->
  io_lib:format("variable '~s' is unbound", [atom_to_list(Name)]);

format_error([], Desc) ->
  io_lib:format("~p", [Desc]);

format_error(Module, Desc) ->
  Module:format_error(Desc).

format_error(Desc) -> format_error([], Desc).