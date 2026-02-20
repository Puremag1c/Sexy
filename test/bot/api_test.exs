defmodule Sexy.Bot.ApiTest do
  use ExUnit.Case

  alias Sexy.Bot.Api

  setup do
    bypass = Bypass.open()
    :persistent_term.put({Sexy.Bot, :api_url}, "http://localhost:#{bypass.port}")
    on_exit(fn -> :persistent_term.erase({Sexy.Bot, :api_url}) end)
    %{bypass: bypass}
  end

  # ── send_message/2 ──────────────────────────────────────────

  describe "send_message/2" do
    test "sends correct POST body and decodes response", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/sendMessage", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["chat_id"] == 123
        assert decoded["text"] == "Hello"
        assert decoded["parse_mode"] == "HTML"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"ok" => true, "result" => %{"message_id" => 1}}))
      end)

      result = Api.send_message(123, "Hello")
      assert result["ok"] == true
      assert result["result"]["message_id"] == 1
    end
  end

  # ── send_message/1 ──────────────────────────────────────────

  describe "send_message/1" do
    test "sends pre-encoded body", %{bypass: bypass} do
      body = Jason.encode!(%{chat_id: 456, text: "Pre-encoded"})

      Bypass.expect_once(bypass, "POST", "/sendMessage", fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(raw)
        assert decoded["chat_id"] == 456
        assert decoded["text"] == "Pre-encoded"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"ok" => true, "result" => %{"message_id" => 2}}))
      end)

      result = Api.send_message(body)
      assert result["ok"] == true
    end
  end

  # ── send_document/5 ─────────────────────────────────────────

  describe "send_document/5" do
    test "sends multipart upload", %{bypass: bypass} do
      tmp = Path.join(System.tmp_dir!(), "sexy_test_doc.txt")
      File.write!(tmp, "test file content")

      on_exit(fn -> File.rm(tmp) end)

      Bypass.expect_once(bypass, "POST", "/sendDocument", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"ok" => true, "result" => %{"message_id" => 3}}))
      end)

      result = Api.send_document(123, tmp, "test.pdf", "caption", "{}")
      assert result["ok"] == true
    end
  end

  # ── delete_message/2 ────────────────────────────────────────

  describe "delete_message/2" do
    test "sends correct delete request", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/deleteMessage", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["chat_id"] == 123
        assert decoded["message_id"] == 42

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"ok" => true, "result" => true}))
      end)

      result = Api.delete_message(123, 42)
      assert result["ok"] == true
    end
  end

  # ── get_updates/1 ───────────────────────────────────────────

  describe "get_updates/1" do
    test "returns {:ok, results} on success", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/getUpdates", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["offset"] == 100

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"ok" => true, "result" => [%{"update_id" => 101}]})
        )
      end)

      assert {:ok, [%{update_id: 101}]} = Api.get_updates(100)
    end

    test "returns {:error, reason} on HTTP error", %{bypass: bypass} do
      Bypass.down(bypass)
      assert {:error, _reason} = Api.get_updates(0)
    end
  end

  # ── get_me/0 ────────────────────────────────────────────────

  describe "get_me/0" do
    test "sends GET request", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/getMe", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"ok" => true, "result" => %{"id" => 12345, "is_bot" => true}})
        )
      end)

      result = Api.get_me()
      assert result["ok"] == true
      assert result["result"]["id"] == 12345
    end
  end

  # ── answer_callback/3 ──────────────────────────────────────

  describe "answer_callback/3" do
    test "sends correct body", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/answerCallbackQuery", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["callback_query_id"] == "abc123"
        assert decoded["text"] == "Done!"
        assert decoded["show_alert"] == true

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"ok" => true, "result" => true}))
      end)

      result = Api.answer_callback("abc123", "Done!", true)
      assert result["ok"] == true
    end
  end

  # ── answer_callback/1 (map) ────────────────────────────────

  describe "answer_callback/1" do
    test "encodes map and sends", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/answerCallbackQuery", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["callback_query_id"] == "xyz"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"ok" => true, "result" => true}))
      end)

      result = Api.answer_callback(%{callback_query_id: "xyz"})
      assert result["ok"] == true
    end
  end

  # ── request/2 ───────────────────────────────────────────────

  describe "request/2" do
    test "sends arbitrary method", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/sendSticker", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"ok" => true, "result" => %{"message_id" => 99}}))
      end)

      body = Jason.encode!(%{chat_id: 1, sticker: "sticker_id"})
      result = Api.request(body, "sendSticker")
      assert result["ok"] == true
    end
  end

  # ── Error handling ──────────────────────────────────────────

  describe "error handling" do
    test "HTTP failure returns error map", %{bypass: bypass} do
      Bypass.down(bypass)
      result = Api.send_message(123, "fail")
      assert result["ok"] == false
      assert result["description"] =~ "HTTP error"
    end

    test "Telegram API error is returned as-is", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/sendMessage", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          400,
          Jason.encode!(%{"ok" => false, "description" => "Bad Request: chat not found"})
        )
      end)

      result = Api.send_message(123, "test")
      assert result["ok"] == false
      assert result["description"] =~ "chat not found"
    end
  end
end
