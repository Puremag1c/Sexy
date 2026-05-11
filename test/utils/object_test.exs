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
      assert obj.upload_type == nil
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

    test "upload_type :photo → photo_upload" do
      assert Object.detect_object_type(%Object{upload_type: :photo}) == "photo_upload"
    end

    test "upload_type :video → video_upload" do
      assert Object.detect_object_type(%Object{upload_type: :video}) == "video_upload"
    end

    test "upload_type :animation → animation_upload" do
      assert Object.detect_object_type(%Object{upload_type: :animation}) == "animation_upload"
    end

    test "upload_type :document → file" do
      assert Object.detect_object_type(%Object{upload_type: :document}) == "file"
    end

    test "upload_type wins over media file_id prefix" do
      assert Object.detect_object_type(%Object{upload_type: :photo, media: "AgACAgIAA"}) ==
               "photo_upload"
    end

    test "non-binary media does not crash → unknown" do
      assert Object.detect_object_type(%Object{media: {:photo, "/tmp/x.jpg"}}) == "unknown"
    end
  end
end
