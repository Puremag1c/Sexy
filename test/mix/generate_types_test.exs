defmodule Mix.Tasks.Sexy.Tdl.GenerateTypesTest do
  use ExUnit.Case, async: false

  @tag :tmp_dir
  test "escapes hostile doc text and writes atomically", %{tmp_dir: tmp} do
    File.cd!(tmp, fn ->
      types = %{
        "evil" => %{
          "type" => "object",
          "url" => "https://example.com",
          "desc" => "Injected \#{System.halt(0)} and \"\"\" and a backslash \\ end",
          "fields" => [
            %{"name" => "f1", "type" => "string", "desc" => "also \#{1 + 1} here"}
          ]
        }
      }

      File.write!("types.json", Jason.encode!(types))
      Mix.Tasks.Sexy.Tdl.GenerateTypes.run([])

      object = File.read!("lib/tdl/object.ex")

      # interpolation in doc text must be escaped — otherwise it executes
      # at the consumer's compile time
      refute object =~ ~r/(?<!\\)#\{System/
      refute object =~ ~r/(?<!\\)#\{1/
      # the file is valid Elixir and the heredoc didn't break
      assert {:ok, _ast} = Code.string_to_quoted(object)
      assert object =~ "defmodule Evil do"

      # a malformed types.json must not destroy previously generated files
      File.write!("types.json", "not json at all")

      assert_raise Jason.DecodeError, fn ->
        Mix.Tasks.Sexy.Tdl.GenerateTypes.run([])
      end

      assert File.read!("lib/tdl/object.ex") == object
    end)
  end

  @tag :tmp_dir
  test "a non-identifier type/field name is rejected, not injected", %{tmp_dir: tmp} do
    File.cd!(tmp, fn ->
      types = %{
        "evil" => %{
          "type" => "object",
          "url" => "https://example.com",
          "desc" => "ok",
          # non-identifier name carrying an interpolation marker
          "fields" => [%{"name" => "x\#{System.halt(0)}", "type" => "int", "desc" => "d"}]
        }
      }

      File.write!("types.json", Jason.encode!(types))

      assert_raise RuntimeError, ~r/invalid identifier/, fn ->
        Mix.Tasks.Sexy.Tdl.GenerateTypes.run([])
      end
    end)
  end
end
