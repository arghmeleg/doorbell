defmodule DoorbellTest do
  use ExUnit.Case
  doctest Doorbell
  Code.put_compiler_option(:ignore_module_conflict, true)

  def json(conn, map) do
    Map.put(conn, :response, map)
  end

  test "pattern matching still works" do
    defmodule FakeController do
      use Doorbell
      import DoorbellTest, only: [json: 2]

      @endpoint do
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

      @endpoint do
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

      @endpoint do
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

      @endpoint do
        arg(:username, min: 3, max: 10)
      end

      def get_stuff(conn, params) do
        json(conn, params)
      end
    end

    %{response: response} = FakeController.get_stuff(%{}, %{"username" => "me"})
    assert length(response[:errors]) == 1

    %{response: response} = FakeController.get_stuff(%{}, %{"username" => "memeMEMEmeme"})
    assert length(response[:errors]) == 1
  end

  test "invalid options do not compile" do
    ast =
      quote do
        defmodule FakeController do
          use Doorbell
          import DoorbellTest, only: [json: 2]

          @endpoint do
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

  test "truncate truncates long text" do
    defmodule FakeController do
      use Doorbell
      import DoorbellTest, only: [json: 2]

      @endpoint do
        arg(:username, truncate: 5)
      end

      def get_stuff(conn, params) do
        json(conn, params)
      end
    end

    %{response: response} = FakeController.get_stuff(%{}, %{"username" => "memeMEMEmeme"})
    assert response["username"] == "memeM"
  end

  test "preprocessors work" do
    defmodule FakeController do
      use Doorbell
      import DoorbellTest, only: [json: 2]

      @endpoint do
        arg(:username, min: 3, pre: {__MODULE__, :preprocess})
      end

      def get_stuff(conn, params) do
        json(conn, params)
      end

      def preprocess(arg) do
        {:ok, arg <> "a"}
      end
    end

    %{response: response} = FakeController.get_stuff(%{}, %{"username" => "aa"})
    assert response["username"] == "aaa"
  end

  test "postprocessors work" do
    defmodule FakeController do
      use Doorbell
      import DoorbellTest, only: [json: 2]

      @endpoint do
        arg(:username, max: 3, post: {__MODULE__, :postprocess})
      end

      def get_stuff(conn, params) do
        json(conn, params)
      end

      def postprocess(arg) do
        {:ok, arg <> "a"}
      end
    end

    %{response: response} = FakeController.get_stuff(%{}, %{"username" => "aaaa"})
    assert length(response[:errors]) == 1

    %{response: response} = FakeController.get_stuff(%{}, %{"username" => "aaa"})
    assert response["username"] == "aaaa"
  end

  test "strict mode errors with extra params" do
    defmodule FakeController do
      use Doorbell
      import DoorbellTest, only: [json: 2]

      @endpoint do
        @strict true
        arg(:username)
      end

      def get_stuff(conn, params) do
        json(conn, params)
      end
    end

    %{response: response} = FakeController.get_stuff(%{}, %{"password" => "123"})
    assert length(response[:errors]) == 1
  end

  test "guards still work" do
    defmodule FakeController do
      use Doorbell
      import DoorbellTest, only: [json: 2]

      @endpoint do
        arg(:username)
      end

      def get_stuff(conn, %{"username" => uname}) when uname == "admin" do
        json(conn, %{cannot_be_admin: true})
      end
    end

    %{response: response} = FakeController.get_stuff(%{}, %{"username" => "admin"})
    assert response[:cannot_be_admin]
  end

  test "customizeable on_error function with atom function name" do
    defmodule FakeController do
      use Doorbell, on_error: :my_error
      import DoorbellTest, only: [json: 2]

      @endpoint do
        arg(:username, required: true)
      end

      def get_stuff(conn, params) do
        raise "This should not get called"
        json(conn, params)
      end

      def my_error(_conn, _params, errors) do
        {:my_custom_error, errors}
      end
    end

    assert {:my_custom_error, errors} = FakeController.get_stuff(%{}, %{"ubernumb" => "damin"})
    assert length(errors) == 1
  end

  test "customizeable on_error function with {mod, fun}" do
    defmodule FakeController do
      use Doorbell, on_error: {__MODULE__, :my_error}
      import DoorbellTest, only: [json: 2]

      @endpoint do
        arg(:username, required: true)
      end

      def get_stuff(conn, params) do
        raise "This should not get called"
        json(conn, params)
      end

      def my_error(_conn, _params, errors) do
        {:my_custom_error, errors}
      end
    end

    assert {:my_custom_error, errors} = FakeController.get_stuff(%{}, %{"ubernumb" => "damin"})
    assert length(errors) == 1
  end

  test "strict mode is globally configurable" do
    defmodule FakeController do
      use Doorbell, strict: true
      import DoorbellTest, only: [json: 2]

      @endpoint do
        arg(:username)
      end

      def get_stuff(conn, params) do
        assert false
        json(conn, params)
      end
    end

    %{response: response} = FakeController.get_stuff(%{}, %{"password" => "123"})
    assert length(response[:errors]) == 1
  end

  test "can parse integers" do
    defmodule FakeController do
      use Doorbell
      import DoorbellTest, only: [json: 2]

      @endpoint do
        arg(:page, :integer)
      end

      def get_stuff(conn, params) do
        assert params["page"] == 123
        json(conn, params)
      end
    end

    %{response: response} = FakeController.get_stuff(%{}, %{"page" => "123"})
    refute response[:errors]
  end

  test "omits omitted params" do
    defmodule FakeController do
      use Doorbell
      import DoorbellTest, only: [json: 2]

      @endpoint do
        arg(:page, :integer)
      end

      def get_stuff(conn, params) do
        refute Map.has_key?(params, "page")
        json(conn, params)
      end
    end

    %{response: response} = FakeController.get_stuff(%{}, %{})
    refute response[:errors]
  end

  test "allows args to be renamed" do
    defmodule FakeController do
      use Doorbell
      import DoorbellTest, only: [json: 2]

      @endpoint do
        arg(:page, :integer, as: "p")
      end

      def get_stuff(conn, params) do
        assert params["page"] == 42
        json(conn, params)
      end
    end

    %{response: response} = FakeController.get_stuff(%{}, %{"p" => "42", "page" => "33"})
    refute response[:errors]
  end

  test "atomize" do
    defmodule FakeController do
      use Doorbell
      import DoorbellTest, only: [json: 2]

      @endpoint do
        arg(:page, :integer, as: "p")
      end

      def get_stuff(conn, params) do
        assert params["page"] == 42
        json(conn, params)
      end
    end

    %{response: response} = FakeController.get_stuff(%{}, %{"p" => "42", "page" => "33"})
    refute response[:errors]
  end
end
