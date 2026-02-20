defmodule Sexy.Bot.ScreenTest do
  use ExUnit.Case, async: true

  alias Sexy.Bot.Screen
  alias Sexy.Utils.Object

  describe "build/1 with single map" do
    test "returns Object struct with given fields" do
      result = Screen.build(%{chat_id: 123, text: "Hello"})
      assert %Object{} = result
      assert result.chat_id == 123
      assert result.text == "Hello"
    end

    test "fills default values for missing fields" do
      result = Screen.build(%{chat_id: 1})
      assert result.text == ""
      assert result.media == nil
      assert result.kb == %{inline_keyboard: []}
      assert result.entity == []
    end

    test "preserves all provided fields" do
      kb = %{inline_keyboard: [[%{text: "Go", callback_data: "/go"}]]}

      result =
        Screen.build(%{
          chat_id: 42,
          text: "Hi",
          media: "AgACPhoto",
          kb: kb,
          entity: [%{type: "bold"}],
          update_data: %{screen: "home"},
          file: "binary_content",
          filename: "doc.pdf"
        })

      assert result.chat_id == 42
      assert result.text == "Hi"
      assert result.media == "AgACPhoto"
      assert result.kb == kb
      assert result.entity == [%{type: "bold"}]
      assert result.update_data == %{screen: "home"}
      assert result.file == "binary_content"
      assert result.filename == "doc.pdf"
    end
  end

  describe "build/1 with list of maps" do
    test "returns list of Object structs" do
      result = Screen.build([%{chat_id: 1, text: "A"}, %{chat_id: 2, text: "B"}])
      assert length(result) == 2
      assert Enum.all?(result, &match?(%Object{}, &1))
      assert hd(result).chat_id == 1
      assert List.last(result).text == "B"
    end

    test "empty list returns empty list" do
      assert Screen.build([]) == []
    end
  end
end
