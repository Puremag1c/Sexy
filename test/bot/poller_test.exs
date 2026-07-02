defmodule Sexy.Bot.PollerTest do
  use ExUnit.Case

  alias Sexy.Bot.Poller

  setup do
    bypass = Bypass.open()
    :persistent_term.put({Sexy.Bot, :api_url}, "http://localhost:#{bypass.port}")
    on_exit(fn -> :persistent_term.erase({Sexy.Bot, :api_url}) end)
    %{bypass: bypass}
  end

  # handle_cast/2 is called directly: the empty and error paths never dispatch
  # updates, so no Session is needed. These guard the offset-reset bug (B6).

  describe "handle_cast(:update, offset)" do
    test "empty poll keeps the current offset", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/getUpdates", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"ok" => true, "result" => []}))
      end)

      assert {:noreply, 500, _timeout} = Poller.handle_cast(:update, 500)
    end

    test "transport error keeps the current offset (was reset to 0)", %{bypass: bypass} do
      Bypass.down(bypass)

      assert {:noreply, 500, _timeout} = Poller.handle_cast(:update, 500)
    end
  end
end
