defmodule Doorbell do
  @moduledoc """
  Documentation for `Doorbell`.
  """

  defmacro __using__(_opts \\ []) do
    quote do
      import Doorbell, only: [arg: 1, arg: 2]
      @on_definition {Doorbell, :on_definition}
      @before_compile {Doorbell, :before_compile}

      Module.register_attribute(__MODULE__, :gate, accumulate: true)
      Module.register_attribute(__MODULE__, :arg, accumulate: true)
      Module.register_attribute(__MODULE__, :gated_funs, accumulate: true)
    end
  end

  @opts ~w(required min max pre post truncate)a

  defmacro arg(name, opts \\ []) do
    extra_opts = Keyword.drop(opts, @opts)

    quote do
      if unquote(extra_opts) != [] do
        raise "Extra opts!"
      end

      @arg Map.merge(%{name: unquote(name)}, Enum.into(unquote(opts), %{}))
    end
  end

  def on_definition(env, :def, fun, [_conn, _params] = args, guards, body) do
    current_args = Module.get_attribute(env.module, :arg)

    {last_fun, last_args} =
      case Module.get_attribute(env.module, :gated_funs) do
        [{_env, _def, last_fun, _args, _guards, _body, last_args} | _] ->
          {last_fun, last_args}

        _ ->
          {nil, nil}
      end

    cond do
      current_args != [] ->
        Module.put_attribute(
          env.module,
          :gated_funs,
          {env, :def, fun, args, guards, body, current_args}
        )

        Module.delete_attribute(env.module, :gate)
        Module.delete_attribute(env.module, :arg)

      fun == last_fun ->
        Module.put_attribute(
          env.module,
          :gated_funs,
          {env, :def, fun, args, guards, body, last_args}
        )

      true ->
        nil
    end
  end

  def on_definition(_env, _kind, _fun, _args, _guards, _body), do: nil

  def def_clause({_env, _kind, fun, args, guard, body, _gate_args}) do
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

  def def_error(fun, args) do
    under_fun = :"_#{fun}"

    quote do
      defp unquote(under_fun)(:error, unquote(hd(args))) do
        json(unquote(hd(args)), %{error: true})
      end
    end
  end

  defmacro before_compile(env) do
    gated_funs = Module.get_attribute(env.module, :gated_funs)
    Module.delete_attribute(env.module, :gated_funs)

    grouped_gated_funs =
      Enum.group_by(gated_funs, fn {_env, _kind, fun, _args, _guards, _body, _gate_body} ->
        fun
      end)

    for {fun, funs} <- grouped_gated_funs do
      {_env, _kind, _fun, args, _guard, _body, gate_args} = funs |> Enum.reverse() |> List.first()
      under_fun = :"_#{fun}"

      margs = Macro.escape(gate_args)

      {one, two, three} =
        quote do
          defoverridable [{unquote(fun), 2}]

          def unquote(fun)(conn, params) do
            args = unquote(margs)

            {parsed_params, errors} = Doorbell.parse_params(params, args)

            if errors == [] do
              unquote(under_fun)(:ok, conn, parsed_params)
            else
              conn
              |> json(%{errors: errors})
            end
          end
        end

      new_funs =
        funs
        |> Enum.reverse()
        |> Enum.map(&Doorbell.def_clause/1)
        |> Kernel.++([Doorbell.def_error(fun, args)])

      {one, two, three ++ new_funs}
    end
    |> Enum.reverse()
  end

  def parse_params(original_params, args, errors \\ [], parsed_params \\ %{})
  def parse_params(_original_params, [], errors, parsed_params), do: {parsed_params, errors}

  def parse_params(original_params, [arg | args], errors, parsed_params) do
    current_param = original_params[to_string(arg.name)]

    {parsed_param, _arg, param_errors} =
      {current_param, arg, []}
      |> do_preprocessor()
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

  def format_errors(errors) do
    [] ++
      Enum.map(errors[:missing_required_args] || [], &"required param \"#{&1}\" missing")
  end
end
