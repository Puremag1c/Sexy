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
        file: {:path, tmp},
        filename: "report.pdf"
      }

      result = Sender.deliver(object)
      assert result["ok"] == true
    end
  end

  # ── Photo upload ────────────────────────────────────────────

  describe "deliver/2 photo upload" do
    test "sends multipart via sendPhoto", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/sendPhoto", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ok_response(120))
      end)

      Bypass.expect(bypass, "POST", "/deleteMessage", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"ok" => true, "result" => true}))
      end)

      Sexy.Bot.SessionMock
      |> expect(:get_message_id, fn 123 -> 47 end)
      |> expect(:on_message_sent, fn 123, 120, "media", %{} -> :ok end)

      tmp = Path.join(System.tmp_dir!(), "sexy_sender_photo.jpg")
      File.write!(tmp, "fake-jpeg")
      on_exit(fn -> File.rm(tmp) end)

      object = %Object{
        chat_id: 123,
        text: "photo caption",
        upload_type: :photo,
        file: {:path, tmp},
        filename: "pic.jpg"
      }

      result = Sender.deliver(object)
      assert result["ok"] == true
    end
  end

  # ── Video upload ────────────────────────────────────────────

  describe "deliver/2 video upload" do
    test "sends multipart via sendVideo", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/sendVideo", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ok_response(121))
      end)

      Bypass.expect(bypass, "POST", "/deleteMessage", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"ok" => true, "result" => true}))
      end)

      Sexy.Bot.SessionMock
      |> expect(:get_message_id, fn 123 -> 46 end)
      |> expect(:on_message_sent, fn 123, 121, "media", %{} -> :ok end)

      tmp = Path.join(System.tmp_dir!(), "sexy_sender_video.mp4")
      File.write!(tmp, "fake-mp4")
      on_exit(fn -> File.rm(tmp) end)

      object = %Object{
        chat_id: 123,
        text: "video caption",
        upload_type: :video,
        file: {:path, tmp},
        filename: "clip.mp4"
      }

      result = Sender.deliver(object)
      assert result["ok"] == true
    end
  end

  # ── Animation upload ────────────────────────────────────────

  describe "deliver/2 animation upload" do
    test "sends multipart via sendAnimation", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/sendAnimation", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ok_response(122))
      end)

      Bypass.expect(bypass, "POST", "/deleteMessage", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"ok" => true, "result" => true}))
      end)

      Sexy.Bot.SessionMock
      |> expect(:get_message_id, fn 123 -> 45 end)
      |> expect(:on_message_sent, fn 123, 122, "media", %{} -> :ok end)

      tmp = Path.join(System.tmp_dir!(), "sexy_sender_anim.gif")
      File.write!(tmp, "fake-gif")
      on_exit(fn -> File.rm(tmp) end)

      object = %Object{
        chat_id: 123,
        text: "anim caption",
        upload_type: :animation,
        file: {:path, tmp},
        filename: "wave.gif"
      }

      result = Sender.deliver(object)
      assert result["ok"] == true
    end
  end

  # ── Document upload via upload_type ─────────────────────────

  describe "deliver/2 document upload via upload_type" do
    test "upload_type: :document routes to sendDocument", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/sendDocument", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ok_response(123))
      end)

      Bypass.expect(bypass, "POST", "/deleteMessage", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"ok" => true, "result" => true}))
      end)

      Sexy.Bot.SessionMock
      |> expect(:get_message_id, fn 123 -> 44 end)
      |> expect(:on_message_sent, fn 123, 123, "media", %{} -> :ok end)

      tmp = Path.join(System.tmp_dir!(), "sexy_sender_doc2.txt")
      File.write!(tmp, "test file")
      on_exit(fn -> File.rm(tmp) end)

      object = %Object{
        chat_id: 123,
        text: "doc caption",
        upload_type: :document,
        file: {:path, tmp},
        filename: "report.pdf"
      }

      result = Sender.deliver(object)
      assert result["ok"] == true
    end
  end

  # ── params passthrough ──────────────────────────────────────

  describe "deliver/2 params" do
    defp capture_body(bypass, path) do
      test_pid = self()

      Bypass.expect_once(bypass, "POST", path, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:body, body})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ok_response(500))
      end)
    end

    test "sendMessage carries params, nil values are omitted", %{bypass: bypass} do
      capture_body(bypass, "/sendMessage")

      %Object{
        chat_id: 123,
        text: "https://example.com",
        params: %{:link_preview_options => %{is_disabled: true}, "protect_content" => nil}
      }
      |> Sender.deliver(update_mid: false)

      assert_received {:body, body}
      decoded = Jason.decode!(body)
      assert decoded["link_preview_options"] == %{"is_disabled" => true}
      refute Map.has_key?(decoded, "protect_content")
      assert decoded["text"] == "https://example.com"
    end

    test "without params the body has only Sexy's keys", %{bypass: bypass} do
      capture_body(bypass, "/sendMessage")

      Sender.deliver(%Object{chat_id: 123, text: "hi"}, update_mid: false)

      assert_received {:body, body}

      assert body |> Jason.decode!() |> Map.keys() |> Enum.sort() ==
               ~w(chat_id entities parse_mode reply_markup text)
    end

    test "photo by file_id carries params", %{bypass: bypass} do
      capture_body(bypass, "/sendPhoto")

      %Object{chat_id: 123, media: "AgACPhotoId", params: %{has_spoiler: true}}
      |> Sender.deliver(update_mid: false)

      assert_received {:body, body}
      assert %{"photo" => "AgACPhotoId", "has_spoiler" => true} = Jason.decode!(body)
    end

    test "multipart upload carries params and entities", %{bypass: bypass} do
      capture_body(bypass, "/sendPhoto")

      %Object{
        chat_id: 123,
        text: "bold",
        entity: [%{type: "bold", offset: 0, length: 4}],
        upload_type: :photo,
        file: "fake-jpeg",
        filename: "p.jpg",
        params: %{has_spoiler: true, show_caption_above_media: false}
      }
      |> Sender.deliver(update_mid: false)

      assert_received {:body, body}
      assert form_field(body, "has_spoiler") == "true"
      assert form_field(body, "show_caption_above_media") == "false"
      assert form_field(body, "chat_id") == "123"

      assert Jason.decode!(form_field(body, "caption_entities")) == [
               %{"type" => "bold", "offset" => 0, "length" => 4}
             ]

      # entities given → no HTML parse mode (was hardcoded "HTML" before 0.12.0)
      assert form_field(body, "parse_mode") == ""
      assert body =~ "name=photo; filename=p.jpg\r\n\r\nfake-jpeg"
    end

    test "{:path, p} uploads the file's content, not the path", %{bypass: bypass} do
      capture_body(bypass, "/sendDocument")

      tmp = Path.join(System.tmp_dir!(), "sexy_sender_path.txt")
      File.write!(tmp, "REAL FILE CONTENT")
      on_exit(fn -> File.rm(tmp) end)

      %Object{chat_id: 123, upload_type: :document, file: {:path, tmp}, filename: "r.txt"}
      |> Sender.deliver(update_mid: false)

      assert_received {:body, body}
      assert body =~ "name=document; filename=r.txt"
      assert body =~ "REAL FILE CONTENT"
      refute body =~ tmp
    end

    # no Bypass expectation: the check runs before any request is sent
    test "{:path, p} to a missing file fails loudly" do
      import ExUnit.CaptureLog

      object = %Object{
        chat_id: 123,
        upload_type: :document,
        file: {:path, "/nonexistent/sexy.pdf"},
        filename: "sexy.pdf"
      }

      log =
        capture_log(fn ->
          assert %{"ok" => false, "description" => description} =
                   Sender.deliver(object, update_mid: false)

          assert description =~ "/nonexistent/sexy.pdf"
          assert description =~ "enoent"
        end)

      assert log =~ "Failed to send message"
    end

    test "params can't override what Sexy sets" do
      for {object, key} <- [
            {%Object{chat_id: 1, params: %{text: "x"}}, "text"},
            {%Object{chat_id: 1, params: %{"reply_markup" => %{}}}, "reply_markup"},
            {%Object{chat_id: 1, media: "AgAC", params: %{photo: "other"}}, "photo"},
            {%Object{
               chat_id: 1,
               upload_type: :video,
               file: "x",
               filename: "v.mp4",
               params: %{video: "y"}
             }, "video"}
          ] do
        error = assert_raise ArgumentError, fn -> Sender.deliver(object) end
        assert error.message =~ inspect([key])
      end
    end

    test "atom and string spelling of one key raises" do
      object = %Object{
        chat_id: 1,
        params: %{:protect_content => true, "protect_content" => false}
      }

      assert_raise ArgumentError, ~r/given twice/, fn -> Sender.deliver(object) end
    end

    # Value of a plain (non-file) form field in a raw multipart body.
    defp form_field(body, name) do
      [_, value] = Regex.run(~r/name="#{name}"\r\n(?:[^\r\n]+\r\n)*\r\n(.*?)\r\n--/s, body)
      value
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

      # 0.10.0: list delivery returns per-item responses instead of :ok
      assert [%{"ok" => true}, %{"ok" => true}] = Sender.deliver(objects)
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

  # ── List delivery returns per-item results ──────────────────

  describe "deliver/2 with a list" do
    test "returns per-item responses, partial failures visible", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/sendMessage", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        response =
          case Jason.decode!(body) do
            %{"chat_id" => 1} -> %{"ok" => true, "result" => %{"message_id" => 1}}
            %{"chat_id" => 2} -> %{"ok" => false, "error_code" => 403, "description" => "blocked"}
          end

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      objects = [%Object{chat_id: 1, text: "a"}, %Object{chat_id: 2, text: "b"}]
      assert [ok, error] = Sender.deliver(objects, update_mid: false)
      assert ok["ok"] == true
      assert error["ok"] == false
      assert error["description"] == "blocked"
    end
  end

  # ── 429 retry ───────────────────────────────────────────────

  describe "deliver/2 rate limiting" do
    test "retries once after retry_after on 429", %{bypass: bypass} do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      Bypass.expect(bypass, "POST", "/sendMessage", fn conn ->
        attempt = Agent.get_and_update(counter, fn n -> {n + 1, n + 1} end)

        response =
          if attempt == 1 do
            %{"ok" => false, "error_code" => 429, "parameters" => %{"retry_after" => 0}}
          else
            %{"ok" => true, "result" => %{"message_id" => 7}}
          end

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      result = Sender.deliver(%Object{chat_id: 9, text: "x"}, update_mid: false)
      assert result["ok"] == true
      assert Agent.get(counter, & &1) == 2
    end

    test "429 without parameters is returned as-is, no retry", %{bypass: bypass} do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      Bypass.expect(bypass, "POST", "/sendMessage", fn conn ->
        Agent.update(counter, &(&1 + 1))

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          429,
          Jason.encode!(%{"ok" => false, "error_code" => 429, "description" => "Too Many"})
        )
      end)

      result = Sender.deliver(%Object{chat_id: 9, text: "x"}, update_mid: false)
      assert result["ok"] == false
      assert Agent.get(counter, & &1) == 1
    end
  end
end
