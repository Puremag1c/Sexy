defmodule Sexy.Utils.BotTest do
  use ExUnit.Case, async: true

  alias Sexy.Utils.Bot

  # ── get_command_name/1 ───────────────────────────────────────

  describe "get_command_name/1" do
    test "extracts command name from /command" do
      assert Bot.get_command_name("/start") == "start"
    end

    test "extracts command name ignoring query" do
      assert Bot.get_command_name("/buy id=42-page=1") == "buy"
    end

    test "works without leading slash" do
      assert Bot.get_command_name("help") == "help"
    end
  end

  # ── parse_comand_and_query/1 ─────────────────────────────────

  describe "parse_comand_and_query/1" do
    test "returns {command, query_map}" do
      assert Bot.parse_comand_and_query("/buy id=42-amount=100") ==
               {"buy", %{id: 42, amount: 100}}
    end

    test "returns empty query for command without params" do
      assert Bot.parse_comand_and_query("/start") == {"start", %{}}
    end
  end

  # ── extract_msg/1 ────────────────────────────────────────────

  describe "extract_msg/1" do
    test "extracts from message key" do
      update = %{message: %{text: "hello", chat: %{id: 1}}}
      assert Bot.extract_msg(update) == %{text: "hello", chat: %{id: 1}}
    end

    test "extracts from callback_query.message" do
      update = %{callback_query: %{message: %{text: "cb", chat: %{id: 2}}, data: "/cmd"}}
      assert Bot.extract_msg(update) == %{text: "cb", chat: %{id: 2}}
    end

    test "returns input as-is when no message or callback_query" do
      update = %{text: "raw", chat: %{id: 3}}
      assert Bot.extract_msg(update) == update
    end
  end

  # ── extract_user_obj/1 ──────────────────────────────────────

  describe "extract_user_obj/1" do
    test "extracts from callback_query.from" do
      update = %{callback_query: %{from: %{id: 10, first_name: "Alice"}, data: "/cmd"}}
      assert Bot.extract_user_obj(update) == %{id: 10, first_name: "Alice"}
    end

    test "extracts from message.from" do
      update = %{message: %{from: %{id: 20, first_name: "Bob"}, text: "hi"}}
      assert Bot.extract_user_obj(update) == %{id: 20, first_name: "Bob"}
    end

    test "falls back to obj.from" do
      update = %{from: %{id: 30, first_name: "Charlie"}}
      assert Bot.extract_user_obj(update) == %{id: 30, first_name: "Charlie"}
    end
  end

  # ── get_message_type/1 ──────────────────────────────────────

  describe "get_message_type/1" do
    test "detects text" do
      assert Bot.get_message_type(%{text: "hello"}) == "text"
    end

    test "detects photo" do
      assert Bot.get_message_type(%{photo: [%{file_id: "abc"}]}) == "photo"
    end

    test "detects video" do
      assert Bot.get_message_type(%{video: %{file_id: "v1"}}) == "video"
    end

    test "detects animation" do
      assert Bot.get_message_type(%{animation: %{file_id: "a1"}}) == "animation"
    end

    test "detects document" do
      assert Bot.get_message_type(%{document: %{file_id: "d1"}}) == "document"
    end

    test "detects sticker" do
      assert Bot.get_message_type(%{sticker: %{file_id: "s1"}}) == "sticker"
    end

    test "detects voice" do
      assert Bot.get_message_type(%{voice: %{file_id: "v1"}}) == "voice"
    end

    test "detects audio" do
      assert Bot.get_message_type(%{audio: %{file_id: "au1"}}) == "audio"
    end

    test "detects contact" do
      assert Bot.get_message_type(%{contact: %{phone_number: "123"}}) == "contact"
    end

    test "detects video_note" do
      assert Bot.get_message_type(%{video_note: %{file_id: "vn1"}}) == "video_note"
    end

    test "returns unknown for empty message" do
      assert Bot.get_message_type(%{}) == "unknown"
    end

    test "extracts from message wrapper" do
      assert Bot.get_message_type(%{message: %{photo: [%{file_id: "p1"}]}}) == "photo"
    end

    test "priority: video_note over text" do
      assert Bot.get_message_type(%{video_note: %{}, text: "caption"}) == "video_note"
    end
  end

  # ── wrap_text/1 and wrap_text/3 ─────────────────────────────

  describe "wrap_text/1" do
    test "wraps text in decorative lines" do
      result = Bot.wrap_text("Hello")
      assert result =~ "Hello"
      assert result =~ "<code>"
      assert result =~ "━━━"
    end
  end

  describe "wrap_text/3" do
    test "wraps text in HTML tag without lines" do
      result = Bot.wrap_text("Hello", "b", false)
      assert result == "<b>Hello</b>"
    end

    test "wraps text in HTML tag with lines" do
      result = Bot.wrap_text("Hello", "b", true)
      assert result =~ "<b>Hello</b>"
      assert result =~ "<code>"
    end

    test "default lines parameter is false" do
      result = Bot.wrap_text("Hi", "i")
      assert result == "<i>Hi</i>"
    end
  end

  # ── get_photo_id/1 ──────────────────────────────────────────

  describe "get_photo_id/1" do
    test "single photo" do
      assert Bot.get_photo_id([%{file_id: "small"}]) == "small"
    end

    test "two photos returns second (larger)" do
      photos = [%{file_id: "small"}, %{file_id: "medium"}]
      assert Bot.get_photo_id(photos) == "medium"
    end

    test "three photos returns third" do
      photos = [%{file_id: "s"}, %{file_id: "m"}, %{file_id: "large"}]
      assert Bot.get_photo_id(photos) == "large"
    end

    test "four photos returns fourth (highest res)" do
      photos = [%{file_id: "s"}, %{file_id: "m"}, %{file_id: "l"}, %{file_id: "xl"}]
      assert Bot.get_photo_id(photos) == "xl"
    end
  end

  # ── paginate/3 ──────────────────────────────────────────────

  describe "paginate/3" do
    test "returns first page" do
      items = Enum.to_list(1..50)
      assert Bot.paginate(items, 1, 10) == Enum.to_list(1..10)
    end

    test "returns second page" do
      items = Enum.to_list(1..50)
      assert Bot.paginate(items, 2, 10) == Enum.to_list(11..20)
    end

    test "returns last partial page" do
      items = Enum.to_list(1..25)
      assert Bot.paginate(items, 3, 10) == Enum.to_list(21..25)
    end

    test "returns empty list for page beyond range" do
      items = Enum.to_list(1..10)
      assert Bot.paginate(items, 5, 10) == []
    end

    test "page_index < 1 treated as first page" do
      items = Enum.to_list(1..20)
      assert Bot.paginate(items, 0, 10) == Enum.to_list(1..10)
    end

    test "page size larger than list" do
      items = Enum.to_list(1..5)
      assert Bot.paginate(items, 1, 100) == Enum.to_list(1..5)
    end
  end
end
