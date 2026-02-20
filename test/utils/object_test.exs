defmodule Sexy.Utils.ObjectTest do
  use ExUnit.Case, async: true

  alias Sexy.Utils.Object

  describe "struct defaults" do
    test "has expected default values" do
      obj = %Object{}
      assert obj.chat_id == nil
      assert obj.text == ""
      assert obj.media == nil
      assert obj.kb == %{inline_keyboard: []}
      assert obj.entity == []
      assert obj.update_data == %{}
      assert obj.file == nil
      assert obj.filename == nil
    end
  end

  describe "detect_object_type/1" do
    test "nil media → txt" do
      assert Object.detect_object_type(%Object{media: nil}) == "txt"
    end

    test "\"file\" media → file" do
      assert Object.detect_object_type(%Object{media: "file"}) == "file"
    end

    test "media starting with A → photo" do
      assert Object.detect_object_type(%Object{media: "AgACAgIAA"}) == "photo"
    end

    test "media starting with B → video" do
      assert Object.detect_object_type(%Object{media: "BAACAgIAA"}) == "video"
    end

    test "media starting with C → animation" do
      assert Object.detect_object_type(%Object{media: "CgACAgIAA"}) == "animation"
    end

    test "media with unknown prefix → unknown" do
      assert Object.detect_object_type(%Object{media: "ZZZ"}) == "unknown"
    end
  end
end
