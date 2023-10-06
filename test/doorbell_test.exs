defmodule DoorbellTest do
  use ExUnit.Case
  doctest Doorbell

  def json(conn, map) do
    Map.put(conn, :response, map)
  end

  test "pattern matching still works" do
    defmodule FakeController do
      use Doorbell
      import DoorbellTest, only: [json: 2]

      @gate do
        arg(:food)
      end

      def get_stuff(conn, %{"food" => "pumpkin"}) do
        json(conn, %{pumkin: :bad})
      end

      def get_stuff(conn, %{"food" => "pudding"}) do
        json(conn, %{pudding: :good})
      end

      def get_stuff(conn, _params) do
        json(conn, %{potato: :ok})
      end
    end

    %{response: response} = FakeController.get_stuff(%{}, %{"food" => "pudding"})
    assert response[:pudding] == :good
    %{response: response} = FakeController.get_stuff(%{}, %{})
    assert response[:potato] == :ok
  end

  test "invalid args are dropped" do
    defmodule FakeController do
      use Doorbell
      import DoorbellTest, only: [json: 2]

      @gate do
        arg(:user_id)
      end

      def get_stuff(conn, params) do
        json(conn, params)
      end
    end

    %{response: response} = FakeController.get_stuff(%{}, %{"user_id" => 22, "food" => "pudding"})
    assert Map.keys(response) == ["user_id"]
  end

  test "required args are required" do
    defmodule FakeController do
      use Doorbell
      import DoorbellTest, only: [json: 2]

      @gate do
        arg(:user_id, required: true)
      end

      def get_stuff(conn, params) do
        if params, do: raise("this should never be called")
        json(conn, params)
      end
    end

    %{response: response} = FakeController.get_stuff(%{}, %{})
    assert length(response[:errors]) == 1
  end

  test "min/max is respected for strings" do
    defmodule FakeController do
      use Doorbell
      import DoorbellTest, only: [json: 2]

      @gate do
        arg(:username, min: 3, max: 10)
      end

      def get_stuff(conn, params) do
        json(conn, params)
      end
    end

    %{response: response} = FakeController.get_stuff(%{}, %{username: "me"})
    assert length(response[:errors]) == 1

    %{response: response} = FakeController.get_stuff(%{}, %{username: "memeMEMEmeme"})
    assert length(response[:errors]) == 1
  end

  test "invalid options do not compile" do
    ast =
      quote do
        defmodule FakeController do
          use Doorbell
          import DoorbellTest, only: [json: 2]

          @gate do
            arg(:username, porcupine: 3)
          end

          def get_stuff(conn, params) do
            json(conn, params)
          end
        end
      end

    assert_raise RuntimeError, fn ->
      Code.eval_quoted(ast)
    end
  end
end
