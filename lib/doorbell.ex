defmodule Doorbell do
  @moduledoc """
  Documentation for `Doorbell`.
  """

  defmacro __using__(_opts \\ []) do
    quote do
      @on_definition {Doorbell, :on_definition}
      @before_compile {Doorbell, :before_compile}

      Module.register_attribute(__MODULE__, :gated_funs, accumulate: true)
      Module.register_attribute(__MODULE__, :gate, accumulate: true)
    end
  end

  def on_definition(env, :def, fun, [_conn, _params] = args, guards, body) do
    IO.puts("------------on_definition-------------")
    # IO.inspect(Map.keys(env), width: :infinity)
    IO.inspect(fun)

    current_gate = Module.get_attribute(env.module, :gate)

    IO.inspect(current_gate)

    {last_fun, last_gate} =
      case Module.get_attribute(env.module, :gated_funs) do
        [{_env, _def, last_fun, _args, _guards, _body, last_gate} | _] ->
          {last_fun, last_gate}

        _ ->
          {nil, nil}
      end

    cond do
      current_gate != [] ->
        Module.put_attribute(
          env.module,
          :gated_funs,
          {env, :def, fun, args, guards, body, current_gate}
        )

        Module.delete_attribute(env.module, :gate)

      fun == last_fun ->
        IO.puts("SAME FUNNNNNNNN")

        Module.put_attribute(
          env.module,
          :gated_funs,
          {env, :def, fun, args, guards, body, last_gate}
        )

      true ->
        nil
    end
  end

  def on_definition(_env, _kind, _fun, _args, _guards, _body), do: nil

  # https://stackoverflow.com/questions/42929471/elixir-macro-rewriting-module-methods-and-global-using-macro
  def def_clause({env, _kind, fun, args, guard, body, _gate_body}) do
    IO.inspect(fun, label: "def clause fun")
    under_fun = :"_#{fun}"

    case guard do
      [] ->
        quote do
          # Kernel.def(Macro.escape(:"_#{unquote(fun)}"), unquote(args), unquote(body))
          # Macro.escape(:"_#{unquote(fun)}")(unquote_splicing(args), unquote(body))
          # def(Macro.escape(:"_#{unquote(fun)}")(unquote_splicing(args), unquote(body)))
          # def(unquote(fun)(unquote_splicing(args)), unquote(body)) # works
          # def(Macro.escape(:"_#{fun}")(unquote_splicing(args)), unquote(body))
          defp(unquote(under_fun)(unquote_splicing(args)), unquote(body))

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

    IO.inspect(env.module)

    gated_funs = Module.get_attribute(env.module, :gated_funs)
    Module.delete_attribute(env.module, :gated_funs)

    grouped_gated_funs =
      Enum.group_by(gated_funs, fn {_env, _kind, fun, _args, _guards, _body, _gate_body} ->
        fun
      end)

    for {fun, funs} <- grouped_gated_funs do
      {env, _kind, _fun, args, guard, body, gate_body} = funs |> Enum.reverse() |> List.first()
      under_fun = :"_#{fun}"

      {one, two, three} =
        quote do
          defoverridable [{unquote(fun), 2}]

          # def thing(), do: :thing

          def unquote(fun)(conn, params) do
            # IO.puts(".............")
            IO.inspect(unquote(gate_body))
            # IO.puts("waaaaaa")
            # unquote(body)
            # apply(__MODULE__, :"_#{unquote(fun)}", [conn, params])
            unquote(under_fun)(conn, params)
          end
        end
        |> IO.inspect()

      # |> IO.inspect(label: "pre = quoted")
      # |> Kernel.++(Enum.map(funs, &Doorbell.def_clause/1))
      {one, two, three ++ (funs |> Enum.reverse() |> Enum.map(&Doorbell.def_clause/1))}
    end
    |> IO.inspect()
    |> Enum.reverse()
  end
end
