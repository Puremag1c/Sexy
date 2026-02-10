defmodule SexyTest do
  use ExUnit.Case
  doctest Sexy

  test "greets the world" do
    assert Sexy.hello() == :world
  end
end
