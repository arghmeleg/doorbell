defmodule DoorbellTest do
  use ExUnit.Case
  doctest Doorbell

  test "greets the world" do
    assert Doorbell.hello() == :world
  end
end
