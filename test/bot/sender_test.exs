defmodule Sexy.Bot.SenderTest do
  use ExUnit.Case

  import Mox

  alias Sexy.Bot.Sender
  alias Sexy.Utils.Object

  setup :verify_on_exit!

  setup do
    bypass = Bypass.open()
    :persistent_term.put({Sexy.Bot, :api_url}, "http://localhost:#{bypass.port}")
    :persistent_term.put({Sexy.Bot, :session}, Sexy.Bot.SessionMock)

    on_exit(fn ->
      :persistent_term.erase({Sexy.Bot, :api_url})
      :persistent_term.erase({Sexy.Bot, :session})
    end)

    %{bypass: bypass}
  end

  defp ok_response(mid) do
    Jason.encode!(%{"ok" => true, "result" => %{"message_id" => mid}})
  end

  # ── Text message ────────────────────────────────────────────

  describe "deliver/2 text message" do
    test "sends sendMessage and updates screen", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/sendMessage", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ok_response(100))
      end)

      # delete old message
      Bypass.expect(bypass, "POST", "/deleteMessage", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"ok" => true, "result" => true}))
      end)

      Sexy.Bot.SessionMock
      |> expect(:get_message_id, fn 123 -> 50 end)
      |> expect(:on_message_sent, fn 123, 100, "txt", %{} -> :ok end)

      object = %Object{chat_id: 123, text: "Hello"}
      result = Sender.deliver(object)
      assert result["ok"] == true
    end
  end

  # ── Photo message ───────────────────────────────────────────

  describe "deliver/2 photo message" do
    test "sends via request/sendPhoto and updates screen", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/sendPhoto", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ok_response(101))
      end)

      Bypass.expect(bypass, "POST", "/deleteMessage", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"ok" => true, "result" => true}))
      end)

      Sexy.Bot.SessionMock
      |> expect(:get_message_id, fn 123 -> 49 end)
      |> expect(:on_message_sent, fn 123, 101, "media", %{} -> :ok end)

      object = %Object{chat_id: 123, text: "photo caption", media: "AgACPhotoId"}
      result = Sender.deliver(object)
      assert result["ok"] == true
    end
  end

  # ── Document upload ─────────────────────────────────────────

  describe "deliver/2 document upload" do
    test "sends multipart via sendDocument", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/sendDocument", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ok_response(102))
      end)

      Bypass.expect(bypass, "POST", "/deleteMessage", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"ok" => true, "result" => true}))
      end)

      Sexy.Bot.SessionMock
      |> expect(:get_message_id, fn 123 -> 48 end)
      |> expect(:on_message_sent, fn 123, 102, "media", %{} -> :ok end)

      tmp = Path.join(System.tmp_dir!(), "sexy_sender_test.txt")
      File.write!(tmp, "test file")
      on_exit(fn -> File.rm(tmp) end)

      object = %Object{
        chat_id: 123,
        text: "doc caption",
        media: "file",
        file: tmp,
        filename: "report.pdf"
      }

      result = Sender.deliver(object)
      assert result["ok"] == true
    end
  end

  # ── update_mid: false ───────────────────────────────────────

  describe "deliver/2 with update_mid: false" do
    test "sends but does not call session", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/sendMessage", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ok_response(200))
      end)

      # No session mock expectations — should not be called

      object = %Object{chat_id: 123, text: "no update"}
      result = Sender.deliver(object, update_mid: false)
      assert result["ok"] == true
    end
  end

  # ── nil chat_id ─────────────────────────────────────────────

  describe "deliver/2 with nil chat_id" do
    test "logs warning and returns without HTTP call", %{bypass: _bypass} do
      import ExUnit.CaptureLog

      log =
        capture_log(fn ->
          Sender.deliver(%Object{chat_id: nil, text: "orphan"})
        end)

      assert log =~ "chat_id is nil"
    end
  end

  # ── List of objects ─────────────────────────────────────────

  describe "deliver/2 with list" do
    test "delivers each object", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/sendMessage", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ok_response(300))
      end)

      Sexy.Bot.SessionMock
      |> expect(:get_message_id, 2, fn _chat_id -> nil end)
      |> expect(:on_message_sent, 2, fn _cid, 300, "txt", %{} -> :ok end)

      objects = [
        %Object{chat_id: 1, text: "first"},
        %Object{chat_id: 2, text: "second"}
      ]

      assert :ok = Sender.deliver(objects)
    end
  end

  # ── API error ───────────────────────────────────────────────

  describe "deliver/2 on API error" do
    test "logs error and does not update screen", %{bypass: bypass} do
      import ExUnit.CaptureLog

      Bypass.expect_once(bypass, "POST", "/sendMessage", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          400,
          Jason.encode!(%{"ok" => false, "description" => "Bad Request: chat not found"})
        )
      end)

      log =
        capture_log(fn ->
          object = %Object{chat_id: 999, text: "fail"}
          result = Sender.deliver(object)
          assert result["ok"] == false
        end)

      assert log =~ "Failed to send message"
    end
  end

  # ── No old message to delete ────────────────────────────────

  describe "deliver/2 when no old message exists" do
    test "skips delete, still saves new mid", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/sendMessage", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ok_response(400))
      end)

      Sexy.Bot.SessionMock
      |> expect(:get_message_id, fn 123 -> nil end)
      |> expect(:on_message_sent, fn 123, 400, "txt", %{} -> :ok end)

      object = %Object{chat_id: 123, text: "fresh"}
      result = Sender.deliver(object)
      assert result["ok"] == true
    end
  end
end
