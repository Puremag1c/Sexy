defmodule Sexy.TDLTest do
  # /bin/cat stands in for tdlib_json_cli: a real OS process behind a real Port.
  use ExUnit.Case, async: false

  alias Sexy.TDL
  alias Sexy.TDL.Registry

  setup do
    Application.put_env(:sexy, :tdlib_binary, "/bin/cat")
    Application.put_env(:sexy, :tdlib_data_root, System.tmp_dir!())
    start_supervised!(Sexy.TDL)

    on_exit(fn ->
      Application.delete_env(:sexy, :tdlib_binary)
      Application.delete_env(:sexy, :tdlib_data_root)
    end)

    :ok
  end

  defp wait_until(fun, tries \\ 100) do
    cond do
      fun.() ->
        :ok

      tries == 0 ->
        flunk("condition not met in time")

      true ->
        Process.sleep(20)
        wait_until(fun, tries - 1)
    end
  end

  test "close/1 actually terminates the session (no resurrection)" do
    assert {:ok, pid} = TDL.open("t1", %{}, app_pid: self())
    wait_until(fn -> is_pid(Registry.get("t1", :backend_pid)) end)

    assert :ok = TDL.close("t1")
    refute Process.alive?(pid)
    # give a would-be resurrection a moment to happen, then check it didn't
    Process.sleep(100)
    assert Registry.get("t1") == nil
    assert %{active: 0} = DynamicSupervisor.count_children(Sexy.TDL.AccountVisor)
    assert {:error, :not_found} = TDL.close("t1")
  end

  test "duplicate open returns {:error, {:already_started, pid}}" do
    assert {:ok, pid} = TDL.open("t2", %{}, app_pid: self())
    assert {:error, {:already_started, ^pid}} = TDL.open("t2", %{}, app_pid: self())
    assert :ok = TDL.close("t2")
  end

  test "open with a broken binary fails synchronously and cleans up" do
    Application.put_env(:sexy, :tdlib_binary, "/nonexistent/tdlib_json_cli")
    assert {:error, _reason} = TDL.open("t3", %{}, app_pid: self())
    assert Registry.get("t3") == nil
  end

  test "transmit to a stale/dead backend pid returns {:error, :no_backend}" do
    assert {:ok, _pid} = TDL.open("t4", %{}, app_pid: self())
    wait_until(fn -> is_pid(Registry.get("t4", :backend_pid)) end)

    # live backend: command written to the port → :ok
    assert :ok = TDL.transmit("t4", ~s({"@type":"getMe"}))

    dead = spawn(fn -> :ok end)
    wait_until(fn -> not Process.alive?(dead) end)
    Registry.update("t4", backend_pid: dead)

    assert {:error, :no_backend} = TDL.transmit("t4", ~s({"@type":"getMe"}))
    assert :ok = TDL.close("t4")
  end

  test "session supervisor death auto-drops the registry entry" do
    assert {:ok, pid} = TDL.open("t5", %{}, app_pid: self())
    wait_until(fn -> Registry.get("t5", :supervisor_pid) == pid end)

    Process.exit(pid, :kill)
    wait_until(fn -> Registry.get("t5") == nil end)
  end

  test "port death notifies the app and restarts the Backend/Handler pair" do
    assert {:ok, _pid} = TDL.open("t6", %{}, app_pid: self())
    wait_until(fn -> is_pid(Registry.get("t6", :backend_pid)) end)
    b1 = Registry.get("t6", :backend_pid)

    send(b1, {:fake_port, {:exit_status, 137}})

    assert_receive {:system_event, :port_exited, 137}, 1_000

    wait_until(fn ->
      b2 = Registry.get("t6", :backend_pid)
      is_pid(b2) and b2 != b1 and Process.alive?(b2)
    end)

    assert :ok = TDL.close("t6")
  end

  test "nested keyboard rows (vector<vector>) deserialize to structs" do
    # no cleanup needed: the ETS table dies with the supervised tree
    Registry.set("h1", %Registry{app_pid: self()})

    json =
      ~s({"@type":"replyMarkupInlineKeyboard","rows":[[{"@type":"inlineKeyboardButton","text":"Go"}]]})

    Sexy.TDL.Handler.handle_info({:backend, json}, "h1")

    assert_receive {:recv, %Sexy.TDL.Object.ReplyMarkupInlineKeyboard{rows: [[button]]}}
    assert %Sexy.TDL.Object.InlineKeyboardButton{text: "Go"} = button
  end

  test "unknown @type from tdlib is logged and dropped, not crashed" do
    Registry.set("h2", %Registry{app_pid: self()})

    Sexy.TDL.Handler.handle_info({:backend, ~s({"@type":"noSuchTypeEver","x":1})}, "h2")

    refute_receive {:recv, _}, 100
  end
end
