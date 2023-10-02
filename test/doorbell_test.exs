defmodule DoorbellTest do
  use ExUnit.Case
  doctest Doorbell

  defmodule FakeController do
    use Doorbell

    # require Ding

    # @doorbell do
    #   # param(:name, :string)
    #   1
    # end

    # Ding.dong()

    @gate do
      arg(:shit)
      arg(:poop)
      arg(:junk)
    end

    def get_stuff(conn, %{"junk" => "idk"}) do
      json(conn, %{success: true})
    end

    # @gate do
    #   :shit
    # end
    def get_stuff(conn, params) do
      IO.inspect(params)
      json(conn, %{success: true})
    end

    # @doorbell do
    #   2
    # end
    # cry do
    #   :balls
    # end

    # @gate do
    #   :shit
    # end
    def get_more(conn, params) do
      IO.inspect(params)
      json(conn, %{success: true})
    end

    def wtf?(v) do
      IO.inspect(v)
      IO.puts("ONE ONE ONE")
    end

    defp json(conn, map) do
      Map.put(conn, :response, map)
    end
  end

  test "greets the world" do
    IO.puts("...................................START TEST")
    FakeController.__info__(:functions) |> IO.inspect()
    # IO.inspect(quote do: FakeController)
    FakeController.get_stuff(%{}, %{"junk" => "idk"}) |> IO.inspect()
    FakeController.get_stuff(%{}, %{"junk" => "idkw"}) |> IO.inspect()
    # FakeController._get_stuff(%{}, %{"junk" => "idk"}) |> IO.inspect()
    # FakeController.wtf?(3)
    # FakeController.wtf?(1)
    # FakeController.ding_dong() |> IO.inspect()
  end
end
