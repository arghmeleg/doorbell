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

  @opts ~w(required min max pre post)a

  defmacro arg(name, opts \\ []) do
    extra_opts = Keyword.drop(opts, @opts)

    quote do
      if unquote(extra_opts) != [] do
        raise "Extra opts!"
      end

      @arg %{name: unquote(name), required: unquote(opts)[:required], min: unquote(opts)[:min]}
    end
  end

  def on_definition(env, :def, fun, [_conn, _params] = args, guards, body) do
    IO.puts("------------on_definition-------------")
    # IO.inspect(Map.keys(env), width: :infinity)
    IO.inspect(fun)

    current_args = Module.get_attribute(env.module, :arg)

    IO.inspect(current_args, label: "content args")

    {last_fun, last_args} =
      case Module.get_attribute(env.module, :gated_funs) do
        [{_env, _def, last_fun, _args, _guards, _body, last_args} | _] ->
          {last_fun, last_args}

        _ ->
          {nil, nil}
      end

    cond do
      current_args != [] ->
        # gate_args = Module.get_attribute(env.module, :arg)

        Module.put_attribute(
          env.module,
          :gated_funs,
          {env, :def, fun, args, guards, body, current_args}
        )

        Module.delete_attribute(env.module, :gate)
        Module.delete_attribute(env.module, :arg)

      fun == last_fun ->
        IO.puts("SAME FUNNNNNNNN")

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

  # https://stackoverflow.com/questions/42929471/elixir-macro-rewriting-module-methods-and-global-using-macro
  def def_clause({env, _kind, fun, args, guard, body, _gate_args}) do
    # IO.inspect(fun, label: "def clause fun")
    # IO.inspect(args, label: "def clause args")
    # IO.inspect(body, label: "def clause body")
    under_fun = :"_#{fun}"

    case guard do
      [] ->
        quote do
          # Kernel.def(Macro.escape(:"_#{unquote(fun)}"), unquote(args), unquote(body))
          # Macro.escape(:"_#{unquote(fun)}")(unquote_splicing(args), unquote(body))
          # def(Macro.escape(:"_#{unquote(fun)}")(unquote_splicing(args), unquote(body)))
          # def(unquote(fun)(unquote_splicing(args)), unquote(body)) # works
          # def(Macro.escape(:"_#{fun}")(unquote_splicing(args)), unquote(body))
          defp(unquote(under_fun)(:ok, unquote_splicing(args)), unquote(body))

          defp unquote(under_fun)(:error, unquote_splicing(args)) do
            json(unquote(hd(args)), %{error: true})
          end

          # Kernel.def(:"_#{fun}", (unquote_splicing(args)), unquote(body))
        end

      _ ->
        quote do
          # def(
          #   :"_#{fun}"(unquote_splicing(args)) when unquote_splicing(guard),
          #   unquote(body)
          # )
        end
    end
  end

  defmacro before_compile(env) do
    IO.puts("~~~~~~before_compile~~~~~~~~")

    [
      :function,
      :functions,
      :line,
      :module,
      :file,
      :context,
      :aliases,
      :lexical_tracker,
      :context_modules,
      :macro_aliases,
      :versioned_vars,
      :tracers,
      :requires,
      :macros,
      :__struct__
    ]

    # IO.inspect(env.module)

    gated_funs = Module.get_attribute(env.module, :gated_funs)
    Module.delete_attribute(env.module, :gated_funs)

    grouped_gated_funs =
      Enum.group_by(gated_funs, fn {_env, _kind, fun, _args, _guards, _body, _gate_body} ->
        fun
      end)

    for {fun, funs} <- grouped_gated_funs do
      {env, _kind, _fun, args, guard, body, gate_args} = funs |> Enum.reverse() |> List.first()
      under_fun = :"_#{fun}"

      arg_names = Enum.map(gate_args, &to_string(&1.name))
      required_args = gate_args |> Enum.filter(& &1.required) |> Enum.map(&to_string(&1.name))

      margs = Macro.escape(gate_args)

      {one, two, three} =
        quote do
          defoverridable [{unquote(fun), 2}]

          def unquote(fun)(conn, params) do
            args = unquote(margs)

            missing_required_args = unquote(required_args) -- Map.keys(params)

            parsed_params = Map.take(params, unquote(arg_names))

            if missing_required_args == [] do
              unquote(under_fun)(:ok, conn, parsed_params)
            else
              errors = Doorbell.format_errors(%{missing_required_args: missing_required_args})

              conn
              |> json(%{errors: errors})
            end
          end
        end

      {one, two, three ++ (funs |> Enum.reverse() |> Enum.map(&Doorbell.def_clause/1))}
    end
    # |> IO.inspect()
    |> Enum.reverse()
  end

  def format_errors(errors) do
    [] ++
      Enum.map(errors[:missing_required_args] || [], &"required param \"#{&1}\" missing")
  end
end
