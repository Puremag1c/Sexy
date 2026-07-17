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
  test "generates modules straight from a td_api.tl schema", %{tmp_dir: tmp} do
    File.cd!(tmp, fn ->
      File.write!("td_api.tl", """
      double ? = Double;
      string ? = String;

      //@class MessageContent @description Contains the content of a message

      //@description A text message @text Text of the message
      //-with a continuation line @is_pinned True, if pinned
      messageText text:formattedText is_pinned:Bool ids:vector<int53> = MessageContent;

      ---functions---

      //@description Returns the current user
      getMe = User;
      """)

      Mix.Tasks.Sexy.Tdl.GenerateTypes.run(["td_api.tl"])

      object = File.read!("lib/tdl/object.ex")
      method = File.read!("lib/tdl/method.ex")

      # abstract @class and concrete type land in Object, function in Method
      assert object =~ "defmodule MessageContent do"
      assert object =~ ~s(defstruct "@type": "messageText")
      assert object =~ "text: nil, is_pinned: nil, ids: nil"
      assert method =~ "defmodule GetMe do"
      # //- continuation is folded into the description
      assert object =~ "with a continuation line"
      # docs table renders the legacy cosmetic types + the doxygen URL mangling
      assert object =~ "| is_pinned | bool |"
      assert object =~ "| ids | string[] |"
      assert object =~ "classtd_1_1td__api_1_1message_text.html"
      assert {:ok, _} = Code.string_to_quoted(object)
      assert {:ok, _} = Code.string_to_quoted(method)
    end)
  end

  @tag :tmp_dir
  test "an undocumented .tl definition fails loudly instead of being dropped", %{tmp_dir: tmp} do
    File.cd!(tmp, fn ->
      File.write!("td_api.tl", """
      double ? = Double;

      mystery x:int32 = Mystery;
      """)

      assert_raise Mix.Error, ~r/undocumented definition skipped: mystery/, fn ->
        Mix.Tasks.Sexy.Tdl.GenerateTypes.run(["td_api.tl"])
      end
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
