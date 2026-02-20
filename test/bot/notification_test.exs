defmodule Sexy.Bot.NotificationTest do
  use ExUnit.Case

  import Mox

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

  defp ok_msg(mid) do
    Jason.encode!(%{"ok" => true, "result" => %{"message_id" => mid}})
  end

  defp ok_true do
    Jason.encode!(%{"ok" => true, "result" => true})
  end

  # ── Overlay mode (default) ──────────────────────────────────

  describe "notify/3 overlay mode" do
    test "sends message + adds dismiss button", %{bypass: bypass} do
      # Sender.deliver calls sendMessage (update_mid: false for overlay)
      Bypass.expect(bypass, "POST", "/sendMessage", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ok_msg(500))
      end)

      # edit_reply_markup to add dismiss button
      Bypass.expect(bypass, "POST", "/editMessageReplyMarkup", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["chat_id"] == 123
        assert decoded["message_id"] == 500

        kb = decoded["reply_markup"]["inline_keyboard"]
        # Should have dismiss row with "OK" button
        assert length(kb) >= 1

        dismiss_row = List.last(kb)
        [dismiss_btn] = dismiss_row
        assert dismiss_btn["text"] == "OK"
        assert dismiss_btn["callback_data"] =~ "/_delete mid=500"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ok_true())
      end)

      # overlay mode does NOT call session (update_mid: false)

      result = Sexy.Bot.Notification.notify(123, %{text: "Notification!"})
      assert result["ok"] == true
    end
  end

  # ── Replace mode ────────────────────────────────────────────

  describe "notify/3 replace mode" do
    test "sends with update_mid and no dismiss button", %{bypass: bypass} do
      # Sender.deliver with update_mid: true → needs session
      Bypass.expect(bypass, "POST", "/sendMessage", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ok_msg(501))
      end)

      Sexy.Bot.SessionMock
      |> expect(:get_message_id, fn 123 -> nil end)
      |> expect(:on_message_sent, fn 123, 501, "txt", %{} -> :ok end)

      # No editReplyMarkup expected (no buttons in replace mode without navigate)

      result = Sexy.Bot.Notification.notify(123, %{text: "Replaced!"}, replace: true)
      assert result["ok"] == true
    end
  end

  # ── Navigate option ─────────────────────────────────────────

  describe "notify/3 with navigate" do
    test "adds transit button + dismiss button", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/sendMessage", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ok_msg(502))
      end)

      Bypass.expect(bypass, "POST", "/editMessageReplyMarkup", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        kb = decoded["reply_markup"]["inline_keyboard"]

        # First row: navigate button
        [[nav_btn] | _rest] = kb
        assert nav_btn["text"] == "View Order"
        assert nav_btn["callback_data"] =~ "/_transit"
        assert nav_btn["callback_data"] =~ "cmd=order"
        assert nav_btn["callback_data"] =~ "mid=502"

        # Last row: dismiss
        dismiss_row = List.last(kb)
        [dismiss_btn] = dismiss_row
        assert dismiss_btn["text"] == "OK"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ok_true())
      end)

      result =
        Sexy.Bot.Notification.notify(123, %{text: "New order"},
          navigate: {"View Order", "/order id=42"}
        )

      assert result["ok"] == true
    end
  end

  # ── Navigate with function ──────────────────────────────────

  describe "notify/3 with navigate function" do
    test "calls function with mid for custom callback_data", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/sendMessage", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ok_msg(503))
      end)

      Bypass.expect(bypass, "POST", "/editMessageReplyMarkup", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        kb = decoded["reply_markup"]["inline_keyboard"]
        [[nav_btn] | _] = kb
        assert nav_btn["text"] == "Details"
        assert nav_btn["callback_data"] == "/show mid=503"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ok_true())
      end)

      result =
        Sexy.Bot.Notification.notify(123, %{text: "Alert"},
          navigate: {"Details", fn mid -> "/show mid=#{mid}" end}
        )

      assert result["ok"] == true
    end
  end

  # ── Extra buttons ───────────────────────────────────────────

  describe "notify/3 with extra_buttons" do
    test "extra buttons are appended after dismiss", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/sendMessage", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ok_msg(504))
      end)

      Bypass.expect(bypass, "POST", "/editMessageReplyMarkup", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        kb = decoded["reply_markup"]["inline_keyboard"]

        # dismiss row + extra row
        assert length(kb) == 2
        # First row: dismiss (since no navigate)
        # Second row: extra button
        extra_row = List.last(kb)
        [extra_btn] = extra_row
        assert extra_btn["text"] == "More"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ok_true())
      end)

      result =
        Sexy.Bot.Notification.notify(123, %{text: "Info"},
          extra_buttons: [[%{text: "More", callback_data: "/more"}]]
        )

      assert result["ok"] == true
    end
  end

  # ── Custom dismiss_text ─────────────────────────────────────

  describe "notify/3 with custom dismiss_text" do
    test "uses custom text for dismiss button", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/sendMessage", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ok_msg(505))
      end)

      Bypass.expect(bypass, "POST", "/editMessageReplyMarkup", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        kb = decoded["reply_markup"]["inline_keyboard"]
        dismiss_row = List.last(kb)
        [dismiss_btn] = dismiss_row
        assert dismiss_btn["text"] == "Got it"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ok_true())
      end)

      result =
        Sexy.Bot.Notification.notify(123, %{text: "Done!"}, dismiss_text: "Got it")

      assert result["ok"] == true
    end
  end
end
