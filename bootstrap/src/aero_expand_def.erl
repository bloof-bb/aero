%%% Handles expansion for definitions.

-module(aero_expand_def).

-export([expand_def/2]).

%% -----------------------------------------------------------------------------
%% Public API
%% -----------------------------------------------------------------------------

%% Expand a definition.
-spec expand_def(aero_ast:ast(), aero_env:env()) -> {aero_core:c_def(), aero_env:env()}.

%% Private definitions.
expand_def({expand, Meta, {ident, _, func}, Args}, Env) ->
  expand_func_def(Args, Meta, c_vis_priv, Env);
expand_def({expand, Meta, {ident, _, const}, Args}, Env) ->
  expand_const_def(Args, Meta, c_vis_priv, Env);

%% Public definitions.
expand_def({expand, Meta, {ident, _, pub}, PubArgs}, Env) ->
  case PubArgs of
    [{expand, _, {ident, _, func}, Args}] ->
      expand_func_def(Args, Meta, c_vis_pub, Env);
    [{expand, _, {ident, _, const}, Args}] ->
      expand_const_def(Args, Meta, c_vis_pub, Env);
    _ ->
      throw({expand_error, {pub_invalid, aero_ast:meta(Meta)}})
  end;

%% Anything else...
expand_def(Def, _Env) ->
  throw({expand_error, {def_invalid, aero_ast:meta(Def)}}).

%% -----------------------------------------------------------------------------
%% Helper Functions
%% -----------------------------------------------------------------------------

expand_func_def([{expand, _, {op, _, '_=_'}, [FuncHead, FuncBody]}], FuncMeta, Vis, Env) ->
  % Function definition variant with assignment to an anonymous function on the right.
  Where = [],
  case FuncHead of
    {tag, _, {ident, _, _} = Ident, {expand, _, {op, _, Arrow}, [{args, _, Args}, Result]}}
        when Arrow =:= '_->_'; Arrow =:= '_->>_' ->
      % For function head.
      check_existing_def(Env, Ident),
      {DefEnv, Path} = aero_env:register_def(Env, Ident),

      {ArgTypes, ResultEnv} = aero_expand_type:expand_types(Args, aero_env:reset_counter(Env)),
      {ResultType, BodyEnv} = aero_expand_type:expand_type(Result, ResultEnv),

      % Expanding body and ensuring it gives a function.
      case aero_expand_expr:expand_expr(FuncBody, BodyEnv) of
        {c_func, _, ExprArgs, _, _, ExprBody} when length(ExprArgs) =:= length(ArgTypes) ->
          ExprVars = [element(1, Arg) || Arg <- ExprArgs],
          NewArgs = lists:zip(ExprVars, ArgTypes),

          Func = aero_core:c_func([], NewArgs, ResultType, Where, ExprBody),
          Def = aero_core:c_def_func([{counter, aero_env:counter(BodyEnv)}], Path, Vis, Func),

          {Def, DefEnv};
        {c_func, _, _, _, _, _} ->
          throw({expand_error, {func_def_eq_arity_mismatch, FuncMeta}});
        _ ->
          throw({expand_error, {func_def_eq_body_invalid, aero_ast:meta(FuncBody)}})
      end;
    _ ->
      throw({expand_error, {func_def_eq_head_invalid, aero_ast:meta(FuncHead)}})
  end;
expand_func_def([FuncHead, FuncBody], _FuncMeta, Vis, Env) ->
  % Function definition variant with assignment to an anonymous function on the right.
  {Path, Args, Result, Where, DefEnv, BodyEnv} = expand_func_def_head(FuncHead, Env),
  Body = expand_func_def_body(FuncBody, BodyEnv),

  Func = aero_core:c_func([], Args, Result, Where, Body),
  Def = aero_core:c_def_func([{counter, aero_env:counter(BodyEnv)}], Path, Vis, Func),

  {Def, DefEnv};
expand_func_def(_, FuncMeta, _, _) ->
  throw({expand_error, {func_def_invalid, FuncMeta}}).

expand_func_def_head(FuncHead, Env) ->
  expand_func_def_head(FuncHead, [], Env).

expand_func_def_head({expand, _, {op, _, '_where_'}, [FuncHeadLeft, Clause]}, Wheres, Env) ->
  {WhereTypes, HeadEnv} = aero_expand_type:expand_where_clauses(Wheres, Env),

  expand_func_def_head(FuncHeadLeft, [Clause | WhereTypes], HeadEnv);
expand_func_def_head({expand, FuncHeadMeta, {op, _, Arrow}, [{args, _, LeftArrowArgs}, Result]},
                     Where,
                     Env) when Arrow =:= '_->_'; Arrow =:= '_->>_' ->
  % TODO: check when pure.
  case LeftArrowArgs of
    [{expand, _, {op, _, '_(_)'}, [{ident, _, _} = Ident, {args, _, Args}]}] ->
      check_existing_def(Env, Ident),
      {DefEnv, Path} = aero_env:register_def(Env, Ident),

      {CoreArgs, ResultEnv} =
        lists:foldl(fun(Arg, {ArgAcc, EnvAcc}) ->
          case Arg of
            {tag, _, {ident, _, _} = ArgIdent, Type} ->
              {ArgEnv, ArgVar} = aero_env:register_var(EnvAcc, ArgIdent),
              {ArgType, NewEnv} = aero_expand_type:expand_type(Type, ArgEnv),

              {[{ArgVar, ArgType} | ArgAcc], NewEnv};
            _ ->
              throw({expand_error, {func_def_arg_invalid, aero_ast:meta(Arg)}})
          end
        end, {[], aero_env:reset_counter(Env)}, Args),
      {ResultType, BodyEnv} = aero_expand_type:expand_type(Result, ResultEnv),

      {Path, lists:reverse(CoreArgs), ResultType, Where, DefEnv, BodyEnv};
    _ ->
      throw({expand_error, {func_def_head_invalid, FuncHeadMeta}})
  end;
expand_func_def_head(FuncHead, _, _Env) ->
  throw({expand_error, {func_def_head_invalid, aero_ast:meta(FuncHead)}}).

expand_func_def_body({block, _, _} = Block, Env) ->
  aero_expand_expr:expand_expr(Block, Env);
expand_func_def_body(FuncBody, _Env) ->
  throw({expand_error, {func_def_body_invalid, aero_ast:meta(FuncBody)}}).

expand_const_def([{expand, _, {op, _, '_=_'}, [ConstLeft, ConstExpr]}], ConstMeta, Vis, Env) ->
  case ConstLeft of
    {tag, _, {ident, _, _} = Ident, TagType} ->
      check_existing_def(Env, Ident),
      {DefEnv, Path} = aero_env:register_def(Env, Ident),
      {Type, BodyEnv} = aero_expand_type:expand_type(TagType, aero_env:reset_counter(Env)),

      Expr = aero_expand_expr:expand_expr(ConstExpr, BodyEnv),
      Def = aero_core:c_def_const([{counter, aero_env:counter(BodyEnv)}], Path, Vis, Type, Expr),

      {Def, DefEnv};
    {ident, _, _} ->
      throw({expand_error, {const_def_missing_type, ConstMeta}});
    _ ->
      throw({expand_error, {const_def_invalid, ConstMeta}})
  end;
expand_const_def(_, ConstMeta, _, _) ->
  throw({expand_error, {const_def_invalid, ConstMeta}}).

check_existing_def(Env, Ident) ->
  case aero_env:lookup_def(Env, Ident) of
    undefined -> ok;
    Def       -> throw({expand_error, {def_exists, aero_ast:meta(Ident), Def}})
  end.
