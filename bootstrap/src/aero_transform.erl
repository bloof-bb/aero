%%% Aero to Elixir AST conversions.

-module(aero_transform).

-export([transform/1]).

%% -----------------------------------------------------------------------------
%% Public API
%% -----------------------------------------------------------------------------

%% Convert the Aero AST into the Elixir AST.
transform({source, _Meta, Exprs}) ->
  % Source of an Aero file calls the `mod` macro. A require call to the Aero
  % kernel implemented in Elixir is inserted at the beginning of the source.
  KernelReq = {
    require,
    [{context, 'Elixir'}],
    [{'__aliases__', [{alias, false}], ['Aero', 'Kernel']}]
  },
  Module = ex_macro_call(mod, ['__source__' | lists:map(fun transform/1, Exprs)]),
  ex_block([KernelReq, Module]);
transform({block, _Meta, Exprs}) ->
  ex_block(lists:map(fun transform/1, Exprs));
transform({expand, _Meta, Macro, Args}) ->
  MacroName =
    case Macro of
      {ident, _, _} = Ident -> transform(Ident);
      {op, _, OpName} -> OpName
    end,
  ex_macro_call(MacroName, lists:map(fun transform/1, Args));
transform({ident, _Meta, Ident}) ->
  Safe = safe_ident(Ident),
  case zero_arg_macro(Safe) of
    true ->
      % Zero arg macros names are converted to macro calls of no arguments.
      ex_macro_call(Safe, []);
    false ->
      {safe_ident(Ident), [], 'Elixir'}
  end;
transform({atom_lit, _Meta, Atom}) ->
  Atom;
transform({string_lit, _Meta, String}) ->
  String;
transform({integer_lit, _Meta, Integer}) ->
  Integer.

%% -----------------------------------------------------------------------------
%% Helper Functions
%% -----------------------------------------------------------------------------

ex_block(Exprs) ->
  {'__block__', [], Exprs}.

ex_macro_call(Macro, Args) ->
  Callee = {
    '.',
    [],
    [{'__aliases__', [{alias, false}], ['Aero', 'Kernel']}, Macro]
  },
  {Callee, [], Args}.

%% Convert idents that are keywords in Elixir.
safe_ident(true) -> true_;
safe_ident(false) -> false_;
safe_ident(nil) -> nil_;
safe_ident('when') -> when_;
safe_ident('and') -> and_;
safe_ident('or') -> or_;
safe_ident(in) -> in_;
safe_ident(fn) -> fn_;
safe_ident(do) -> do_;
safe_ident('end') -> end_;
safe_ident('catch') -> catch_;
safe_ident(rescue) -> rescue_;
safe_ident('after') -> after_;
safe_ident(else) -> else_;
safe_ident('_') -> '__';
safe_ident(Other) -> Other.

%% Identifiers which are converted to macro calls.
zero_arg_macro(true_) -> true;
zero_arg_macro(false_) -> true;
zero_arg_macro(nil_) -> true;
zero_arg_macro(_) -> false.
