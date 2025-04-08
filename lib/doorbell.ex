defmodule Doorbell do
  @moduledoc """
  Documentation for `Doorbell`.
  """

  @arg_opts ~w(required min max pre post truncate)a
  @use_opts ~w(error strict)a
  @valid_types ~w(string integer)a

  defmacro __using__(opts \\ []) do
    quote do
      {valid_opts, invalid_opts} = Keyword.split(unquote(opts), unquote(@use_opts))
      if invalid_opts != [], do: raise("Invalid options: #{inspect(invalid_opts)}")
      @doorbell_options valid_opts

      import Doorbell, only: [arg: 1, arg: 2, arg: 3]
      @on_definition {Doorbell, :on_definition}
      @before_compile {Doorbell, :before_compile}

      Module.register_attribute(__MODULE__, :endpoint, accumulate: true)
      Module.register_attribute(__MODULE__, :arg, accumulate: true)
      Module.register_attribute(__MODULE__, :endpointed_funs, accumulate: true)
    end
  end

  defmacro arg(name, type, opts) do
    extra_opts = Keyword.drop(opts, @arg_opts)
    is_valid_type = type in @valid_types

    quote do
      if unquote(extra_opts) != [] do
        raise "Extra opts: #{inspect(unquote(extra_opts))}"
      end

      if not unquote(is_valid_type) do
        raise "Invalid type: #{inspect(unquote(type))}"
      end

      @arg Map.merge(%{name: unquote(name), type: unquote(type)}, Enum.into(unquote(opts), %{}))
    end
  end

  defmacro arg(name) do
    quote do
      arg(unquote(name), :string, [])
    end
  end

  defmacro arg(name, type) when is_atom(type) do
    quote do
      arg(unquote(name), unquote(type), [])
    end
  end

  defmacro arg(name, opts) do
    quote do
      arg(unquote(name), :string, unquote(opts))
    end
  end

  def on_definition(env, :def, fun, [_conn, _params] = args, guards, body) do
    current_args = Module.get_attribute(env.module, :arg)

    opts =
      Keyword.merge(
        Module.get_attribute(env.module, :doorbell_options),
        [args: current_args, strict: Module.get_attribute(env.module, :strict)],
        fn _k, v1, v2 ->
          if is_nil(v2), do: v1, else: v2
        end
      )

    {last_fun, last_opts} =
      case Module.get_attribute(env.module, :endpointed_funs) do
        [{_env, _def, last_fun, _args, _guards, _body, last_opts} | _] ->
          {last_fun, last_opts}

        _ ->
          {nil, nil}
      end

    cond do
      current_args != [] ->
        Module.put_attribute(
          env.module,
          :endpointed_funs,
          {env, :def, fun, args, guards, body, opts}
        )

        Module.delete_attribute(env.module, :endpoint)
        Module.delete_attribute(env.module, :arg)
        Module.delete_attribute(env.module, :strict)

      fun == last_fun ->
        Module.put_attribute(
          env.module,
          :endpointed_funs,
          {env, :def, fun, args, guards, body, last_opts}
        )

      true ->
        nil
    end
  end

  def on_definition(_env, _kind, _fun, _args, _guards, _body), do: nil

  defp def_clause({_env, _kind, fun, args, guard, body, _opts}) do
    under_fun = :"_#{fun}"

    if guard == [] do
      quote do
        defp(unquote(under_fun)(:ok, unquote_splicing(args)), unquote(body))
      end
    else
      quote do
        Kernel.unquote(:defp)(
          unquote(under_fun)(:ok, unquote_splicing(args)) when unquote_splicing(guard),
          unquote(body)
        )
      end
    end
  end

  defmacro before_compile(env) do
    endpointed_funs = Module.get_attribute(env.module, :endpointed_funs)
    Module.delete_attribute(env.module, :endpointed_funs)

    grouped_endpointed_funs =
      Enum.group_by(endpointed_funs, fn {_env, _kind, fun, _args, _guards, _body, _opts} ->
        fun
      end)

    for {fun, funs} <- grouped_endpointed_funs do
      {_env, _kind, _fun, _args, _guard, _body, opts} = funs |> Enum.reverse() |> List.first()

      under_fun = :"_#{fun}"

      mopts = Macro.escape(opts)

      {one, two, three} =
        quote do
          defoverridable [{unquote(fun), 2}]

          def unquote(fun)(conn, params) do
            Doorbell.run(
              __MODULE__,
              conn,
              params,
              unquote(mopts),
              fn parsed_params ->
                unquote(under_fun)(:ok, conn, parsed_params)
              end,
              fn errors ->
                json(conn, %{errors: errors})
              end
            )
          end
        end

      new_funs =
        funs
        |> Enum.reverse()
        |> Enum.map(&def_clause/1)

      {one, two, three ++ new_funs}
    end
    |> Enum.reverse()
  end

  def run(mod, conn, params, opts, do_fun, else_fun) do
    arg_names = Enum.map(opts[:args], &to_string(&1.name))
    {parsed_params, param_errors} = parse_params(params, opts[:args])

    errors =
      if opts[:strict] do
        extra_params = Map.keys(params) -- arg_names
        if extra_params == [], do: [], else: param_errors ++ ["Extra params"]
      else
        param_errors
      end

    if errors == [] do
      do_fun.(parsed_params)
    else
      case opts[:error] do
        err_fun when is_atom(err_fun) and not is_nil(err_fun) ->
          apply(mod, err_fun, [conn, params, errors])

        {err_mod, err_fun} ->
          apply(err_mod, err_fun, [conn, params, errors])

        _ ->
          else_fun.(errors)
      end
    end
  end

  defp parse_params(original_params, args, errors \\ [], parsed_params \\ %{})
  defp parse_params(_original_params, [], errors, parsed_params), do: {parsed_params, errors}

  defp parse_params(original_params, [arg | args], errors, parsed_params) do
    if arg[:required] || Map.has_key?(original_params, to_string(arg.name)) do
      do_parse_params(original_params, arg, args, errors, parsed_params)
    else
      parse_params(original_params, args, errors, parsed_params)
    end
  end

  defp do_parse_params(original_params, arg, args, errors, parsed_params) do
    current_param = original_params[to_string(arg.name)]

    {parsed_param, _arg, param_errors} =
      {current_param, arg, []}
      |> do_preprocessor()
      |> parse_type()
      |> parse_required()
      |> parse_min()
      |> parse_max()
      |> do_truncate()
      |> do_postprocessor()

    new_parsed_params = Map.put(parsed_params, to_string(arg.name), parsed_param)
    new_errors = errors ++ param_errors
    parse_params(original_params, args, new_errors, new_parsed_params)
  end

  defp do_preprocessor({_p, a, _e} = t), do: run_processor(t, a[:pre])

  defp parse_type({param, %{type: :integer} = args, errors}) do
    case Integer.parse(param) do
      {int, _} -> {int, args, errors}
      _ -> {nil, args, errors}
    end
  end

  defp parse_type(tuple), do: tuple

  defp parse_required({nil, %{required: true} = arg, errors}) do
    {nil, arg, errors ++ ["Required param \"#{arg.name}\" missing"]}
  end

  defp parse_required(t), do: t

  defp parse_min({param, %{min: min} = a, errors}) do
    if min && param_size(param) < min do
      {param, a, errors ++ ["\"#{a.name}\" too small"]}
    else
      {param, a, errors}
    end
  end

  defp parse_min(t), do: t

  defp parse_max({param, %{max: max} = a, errors}) do
    if max && param_size(param) > max do
      {param, a, errors ++ ["\"#{a.name}\" too big"]}
    else
      {param, a, errors}
    end
  end

  defp parse_max(t), do: t

  defp do_truncate({param, %{truncate: i} = a, e} = t) when is_integer(i) and i > 0 do
    case param do
      <<result::binary-size(i), _::binary>> -> {result, a, e}
      _ -> t
    end
  end

  defp do_truncate(t), do: t

  defp do_postprocessor({_p, a, _e} = t), do: run_processor(t, a[:post])

  defp run_processor(t, nil), do: t

  defp run_processor({p, a, e}, {mod, fun}) do
    case apply(mod, fun, [p]) do
      {:ok, new_p} -> {new_p, a, e}
      {:error, error} -> {p, a, e ++ List.wrap(error)}
      _ -> raise "invalid processor response"
    end
  end

  defp param_size(s) when is_binary(s), do: String.length(s)
  defp param_size(i) when is_integer(i), do: i
  defp param_size(_), do: nil
end
