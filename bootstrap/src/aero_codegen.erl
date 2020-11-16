%%% Generates Core Erlang code from the Aero AST.

-module(aero_codegen).

-export([generate/1]).

%% -----------------------------------------------------------------------------
%% Public API
%% -----------------------------------------------------------------------------

-spec generate(aero_expander:c_module()) -> {ok, binary()} | {error, term()}.
generate(CoreModule) ->
  CerlModule = gen_module(CoreModule),
  case compile:noenv_forms(CerlModule, [from_core, return_errors]) of
    {ok, _, Binary} ->
      {c_module, _, {c_path, _, [{c_var, _, Name}]}, _, _} = CoreModule,
      {ok, Name, Binary};
    {error, Errors, _} ->
      {error, {internal_cerl_compile, Errors}}
  end.

%% -----------------------------------------------------------------------------
%% Helper Functions
%% -----------------------------------------------------------------------------

gen_module({c_module, _, {c_path, _, [{c_var, _, Name}]}, Attrs, Defs}) ->
  CerlName = cerl:c_atom(Name),

  CerlAttrs =
    lists:map(fun(_Attr) ->
      % TODO: Implement.
      throw(unimplemented)
    end, Attrs),

  {CerlExports, CerlDefs} =
    lists:foldl(fun(Def, {AccExports, AccDefs}) ->
      case Def of
        {{c_path, _, [{c_var, _, FuncName}]}, Vis, {c_func, _, _, _, _, _} = Func} ->
          CerlDef = {cerl:c_fname(FuncName, arity(Func)), gen_expr(Func)},
          case Vis of
            c_vis_pub ->
              CerlExport = cerl:c_fname(FuncName, arity(Func)),
              {[CerlExport | AccExports], [CerlDef | AccDefs]};
            c_vis_priv ->
              {AccExports, [CerlDef | AccDefs]}
          end
      end
    end, {[], []}, Defs),

  cerl:c_module(CerlName, lists:reverse(CerlExports), CerlAttrs, lists:reverse(CerlDefs)).

gen_expr({c_block, _, [{c_letrec, _, {c_var, _, FuncName} = Var, _Type, Func}, Var]}) ->
  % Recursive functions are handled specially: the name of the recursive
  % function needs to also be bound inside a recursive function in Core
  % Erlang, e.g. binding `Name` to `'Name/1'`.
  CerlFuncName = cerl:c_fname(FuncName, arity(Func)),
  CerlFunc = gen_expr(Func),
  CerlFuncNew = cerl:c_fun(
    cerl:fun_vars(CerlFunc),
    cerl:c_let([cerl:c_var(FuncName)], CerlFunc, cerl:fun_body(CerlFunc))
  ),
  cerl:c_letrec([{CerlFuncName, CerlFuncNew}], CerlFuncName);
gen_expr({c_block, _, Exprs}) ->
  RevExprs = lists:reverse(Exprs),

  % Erlang "let"s go backwards, so we expand the inner parts first.
  lists:foldr(fun({c_let, _, Left, _Type, Right}, Inner) ->
    cerl:c_let([gen_expr(Left)], gen_expr(Right), Inner)
  end, gen_expr(hd(RevExprs)), tl(RevExprs));

gen_expr({c_bool_lit, _, Bool}) ->
  cerl:abstract(Bool);
gen_expr({c_int_lit, _, Integer}) ->
  cerl:abstract(Integer);
gen_expr({c_float_lit, _, Float}) ->
  cerl:abstract(Float);
gen_expr({c_atom_lit, _, Atom}) ->
  cerl:abstract(Atom);
gen_expr({c_str_lit, _, String}) ->
  cerl:abstract(String);

gen_expr({c_unit, _}) ->
  cerl:abstract(ok);

gen_expr({c_tuple, _, Exprs}) ->
  cerl:c_tuple([gen_expr(Expr) || Expr <- Exprs]);

gen_expr({c_cons, _, Head, Tail}) ->
  cerl:c_cons(gen_expr(Head), gen_expr(Tail));
gen_expr({c_nil, _}) ->
  cerl:c_nil();

gen_expr({c_dict, _, Pairs}) ->
  CerlPairs =
    lists:map(fun({Key, Value}) ->
      cerl:c_map_pair(gen_expr(Key), gen_expr(Value))
    end, Pairs),
  cerl:c_map(CerlPairs);

gen_expr({c_func, _, Args, _Result, _Where, Body}) ->
  CerlArgs = [cerl:c_var(Name) || {{c_var, _, Name}, _} <- Args],
  CerlBody = gen_expr(Body),

  cerl:c_fun(CerlArgs, CerlBody);

gen_expr({c_call, _, {c_path, _, [{c_var, _, Module}, {c_var, _, Function}]}, Args}) ->
  CerlModule = cerl:abstract(Module),
  CerlFunction = cerl:abstract(Function),
  CerlArgs = [gen_expr(Arg) || Arg <- Args],

  cerl:c_call(CerlModule, CerlFunction, CerlArgs);
gen_expr({c_call, _, {c_path, _, [{c_var, _, Function}]}, Args}) ->
  CerlFunction = cerl:c_fname(Function, length(Args)),
  CerlArgs = [gen_expr(Arg) || Arg <- Args],

  cerl:c_apply(CerlFunction, CerlArgs);
gen_expr({c_apply, _, {c_var, _, Function}, Args}) ->
  CerlFunction = cerl:c_var(Function),
  CerlArgs = [gen_expr(Arg) || Arg <- Args],

  cerl:c_apply(CerlFunction, CerlArgs);

gen_expr({c_var, _, VarName}) ->
  cerl:c_var(VarName);

% Occurs when a let is at the end of a block, binding is not used.
gen_expr({c_let, _, _Left, _Type, Right}) ->
  gen_expr(Right);

gen_expr({c_when, _, Clauses}) ->
  RevClauses = lists:reverse(Clauses),
  {{c_bool_lit, _, true}, LastExpr} = hd(RevClauses),

  % Checking if the condition is `true`, otherwise using a wildcard pattern to
  % continue with a nested Core Erlang `case`.
  lists:foldl(fun({Cond, Expr}, Inner) ->
    CerlClauses = [
      cerl:c_clause([cerl:abstract(true)], gen_expr(Expr)),
      cerl:c_clause([cerl:c_var(cerl_trees:next_free_variable_name(Inner))], Inner)
    ],
    cerl:c_case(gen_expr(Cond), CerlClauses)
  end, gen_expr(LastExpr), tl(RevClauses)).

arity({c_func, _, Args, _, _, _}) ->
  length(Args).
