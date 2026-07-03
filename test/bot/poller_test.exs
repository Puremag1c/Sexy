defmodule Sexy.Bot.PollerTest do
  use ExUnit.Case, async: false

  alias Sexy.Bot.Poller

  defmodule TestSession do
    @behaviour Sexy.Bot.Session

    defp notify(event, payload) do
      send(:persistent_term.get({__MODULE__, :test_pid}), {:called, event, payload})
    end

    @impl true
    def get_message_id(_chat_id), do: nil
    @impl true
    def on_message_sent(_c, _m, _t, _u), do: :ok
    @impl true
    def handle_command(%{message: %{text: "/boom"}}), do: raise("boom")
    def handle_command(u), do: notify(:handle_command, u)
    @impl true
    def handle_query(u), do: notify(:handle_query, u)
    @impl true
    def handle_message(%{message: %{text: "slow"}} = u) do
      Process.sleep(80)
      notify(:handle_message, u)
    end

    def handle_message(u), do: notify(:handle_message, u)
    @impl true
    def handle_chat_member(u), do: notify(:handle_chat_member, u)
    @impl true
    def handle_poll(u), do: notify(:handle_poll, u)
    @impl true
    def handle_transit(chat_id, cmd, query), do: notify(:handle_transit, {chat_id, cmd, query})
    @impl true
    def handle_pre_checkout(u), do: notify(:handle_pre_checkout, u)
    @impl true
    def handle_successful_payment(u), do: notify(:handle_successful_payment, u)
  end

  defmodule MinimalSession do
    # only the required callbacks — all optional ones absent
    @behaviour Sexy.Bot.Session

    defp notify(event, payload) do
      send(
        :persistent_term.get({Sexy.Bot.PollerTest.TestSession, :test_pid}),
        {:called, event, payload}
      )
    end

    @impl true
    def get_message_id(_chat_id), do: nil
    @impl true
    def on_message_sent(_c, _m, _t, _u), do: :ok
    @impl true
    def handle_command(u), do: notify(:handle_command, u)
    @impl true
    def handle_query(u), do: notify(:handle_query, u)
    @impl true
    def handle_message(u), do: notify(:handle_message, u)
    @impl true
    def handle_chat_member(u), do: notify(:handle_chat_member, u)
  end

  setup do
    bypass = Bypass.open()
    :persistent_term.put({Sexy.Bot, :api_url}, "http://localhost:#{bypass.port}")
    :persistent_term.put({Sexy.Bot, :session}, TestSession)
    :persistent_term.put({Sexy.Bot, :offset_ref}, :atomics.new(1, signed: true))
    :persistent_term.put({TestSession, :test_pid}, self())

    start_supervised!(
      {PartitionSupervisor, child_spec: Sexy.Bot.Dispatcher, name: Sexy.Bot.Dispatchers}
    )

    on_exit(fn ->
      for k <- [:api_url, :session, :offset_ref], do: :persistent_term.erase({Sexy.Bot, k})
      :persistent_term.erase({TestSession, :test_pid})
    end)

    %{bypass: bypass}
  end

  defp expect_updates(bypass, updates) do
    Bypass.expect_once(bypass, "POST", "/getUpdates", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"ok" => true, "result" => updates}))
    end)
  end

  defp stub_api(bypass, path, tag, test_pid) do
    Bypass.stub(bypass, "POST", path, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:api, tag, Jason.decode!(body)})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"ok" => true, "result" => true}))
    end)
  end

  # ── Offset handling ─────────────────────────────────────────

  describe "offset handling" do
    test "empty poll keeps the current offset", %{bypass: bypass} do
      expect_updates(bypass, [])
      assert {:noreply, 500} = Poller.handle_cast(:update, 500)
    end

    test "transport error keeps the current offset", %{bypass: bypass} do
      Bypass.down(bypass)
      assert {:noreply, 500} = Poller.handle_cast(:update, 500)
    end

    test "offset survives a poller restart", %{bypass: bypass} do
      expect_updates(bypass, [%{update_id: 100, message: %{text: "hi", chat: %{id: 1}}}])
      assert {:noreply, 101} = Poller.handle_cast(:update, 0)

      # A restarted poller must resume from the saved offset, not 0
      assert {:ok, 101} = Poller.init(:ok)
      assert_receive :poll
    end
  end

  # ── Routing table (one fixture per row) ─────────────────────

  describe "update routing" do
    test "routes every update type to the right callback", %{bypass: bypass} do
      updates = [
        %{update_id: 1, message: %{text: "/start", chat: %{id: 1}}},
        %{update_id: 2, message: %{text: "hello", chat: %{id: 1}}},
        %{update_id: 3, message: %{photo: [], chat: %{id: 1}}},
        %{update_id: 4, message: %{successful_payment: %{}, chat: %{id: 1}}},
        %{update_id: 5, callback_query: %{id: "q1", data: "/go", message: %{chat: %{id: 1}}}},
        %{update_id: 6, pre_checkout_query: %{id: "pc1"}},
        %{update_id: 7, poll: %{id: "p1"}},
        %{update_id: 8, poll_answer: %{poll_id: "p1"}},
        %{update_id: 9, my_chat_member: %{chat: %{id: 1}}}
      ]

      expect_updates(bypass, updates)
      assert {:noreply, 10} = Poller.handle_cast(:update, 0)

      assert_receive {:called, :handle_command, %{update_id: 1}}
      assert_receive {:called, :handle_message, %{update_id: 2}}
      assert_receive {:called, :handle_message, %{update_id: 3}}
      assert_receive {:called, :handle_successful_payment, %{update_id: 4}}
      assert_receive {:called, :handle_query, %{update_id: 5}}
      assert_receive {:called, :handle_pre_checkout, %{update_id: 6}}
      assert_receive {:called, :handle_poll, %{update_id: 7}}
      assert_receive {:called, :handle_poll, %{update_id: 8}}
      assert_receive {:called, :handle_chat_member, %{update_id: 9}}
    end

    test "same-chat updates are processed in order (slow handler first)", %{bypass: bypass} do
      updates = [
        %{update_id: 50, message: %{text: "slow", chat: %{id: 7}}},
        %{update_id: 51, message: %{text: "fast", chat: %{id: 7}}}
      ]

      expect_updates(bypass, updates)
      Poller.handle_cast(:update, 0)

      # serial per-chat dispatch: the slow update must finish first
      assert_receive {:called, :handle_message, %{update_id: first}}, 1_000
      assert_receive {:called, :handle_message, %{update_id: second}}, 1_000
      assert {first, second} == {50, 51}
    end

    test "a crashing handler doesn't stop the partition queue", %{bypass: bypass} do
      updates = [
        # no :text key → handle_message; make it crash via a poison fixture:
        # TestSession.handle_command raises only for this marker
        %{update_id: 60, message: %{text: "/boom", chat: %{id: 8}}},
        %{update_id: 61, message: %{text: "after", chat: %{id: 8}}}
      ]

      expect_updates(bypass, updates)
      Poller.handle_cast(:update, 0)

      assert_receive {:called, :handle_message, %{update_id: 61}}, 1_000
    end

    test "callback_query without :data routes to handle_query and doesn't kill the batch",
         %{bypass: bypass} do
      updates = [
        %{update_id: 20, callback_query: %{id: "q", message: %{chat: %{id: 1}}}},
        %{update_id: 21, message: %{text: "after", chat: %{id: 1}}}
      ]

      expect_updates(bypass, updates)
      assert {:noreply, 22} = Poller.handle_cast(:update, 0)

      assert_receive {:called, :handle_query, %{update_id: 20}}
      assert_receive {:called, :handle_message, %{update_id: 21}}
    end
  end

  # ── Fallbacks for absent optional callbacks ─────────────────

  describe "session without optional callbacks" do
    test "pre_checkout is auto-approved, poll is ignored, batch continues", %{bypass: bypass} do
      :persistent_term.put({Sexy.Bot, :session}, MinimalSession)
      stub_api(bypass, "/answerPreCheckoutQuery", :pre_checkout_answer, self())

      updates = [
        %{update_id: 70, pre_checkout_query: %{id: "pc9", from: %{id: 3}}},
        %{update_id: 71, poll: %{id: "p9"}},
        %{update_id: 72, message: %{text: "after", chat: %{id: 3}}}
      ]

      expect_updates(bypass, updates)
      assert {:noreply, 73} = Poller.handle_cast(:update, 0)

      # missing handle_pre_checkout → library must approve within 10s or the payment dies
      assert_receive {:api, :pre_checkout_answer,
                      %{"pre_checkout_query_id" => "pc9", "ok" => true}}

      # missing handle_poll → logged and ignored, no crash; the batch continues
      assert_receive {:called, :handle_message, %{update_id: 72}}
    end
  end

  # ── Built-in routes ─────────────────────────────────────────

  describe "built-in callback routes" do
    test "/_delete deletes the message and answers; malformed data only answers",
         %{bypass: bypass} do
      stub_api(bypass, "/deleteMessage", :delete, self())
      stub_api(bypass, "/answerCallbackQuery", :answer, self())

      updates = [
        %{
          update_id: 30,
          callback_query: %{id: "q1", data: "/_delete mid=77", message: %{chat: %{id: 5}}}
        },
        %{
          update_id: 31,
          callback_query: %{id: "q2", data: "/_delete", message: %{chat: %{id: 5}}}
        }
      ]

      expect_updates(bypass, updates)
      Poller.handle_cast(:update, 0)

      assert_receive {:api, :delete, %{"chat_id" => 5, "message_id" => 77}}
      assert_receive {:api, :answer, %{"callback_query_id" => "q1"}}
      assert_receive {:api, :answer, %{"callback_query_id" => "q2"}}
      refute_receive {:api, :delete, _}
    end

    test "/_transit checks handle_transit and params before deleting", %{bypass: bypass} do
      stub_api(bypass, "/deleteMessage", :delete, self())
      stub_api(bypass, "/answerCallbackQuery", :answer, self())

      updates = [
        %{
          update_id: 40,
          callback_query: %{
            id: "q1",
            data: "/_transit mid=9-cmd=order-id=42",
            message: %{chat: %{id: 5}}
          }
        },
        %{
          update_id: 41,
          callback_query: %{id: "q2", data: "/_transit mid=9", message: %{chat: %{id: 5}}}
        }
      ]

      expect_updates(bypass, updates)
      Poller.handle_cast(:update, 0)

      assert_receive {:called, :handle_transit, {5, "order", %{id: 42}}}
      assert_receive {:api, :delete, %{"chat_id" => 5, "message_id" => 9}}
      assert_receive {:api, :answer, %{"callback_query_id" => "q1"}}
      # malformed /_transit (no cmd): answered, nothing deleted, no callback
      assert_receive {:api, :answer, %{"callback_query_id" => "q2"}}
      refute_receive {:api, :delete, _}
      refute_receive {:called, :handle_transit, _}
    end
  end
end
