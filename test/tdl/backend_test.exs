defmodule Sexy.TDL.BackendTest do
  # Backend's line handling is pure logic driven by handle_info/2 — no port
  # needed. These lock the parsing edge cases (buffer reassembly, ANSI, error
  # parse) that would silently corrupt TDLib messages if they broke.
  use ExUnit.Case, async: false

  alias Sexy.TDL.{Backend, Registry}

  setup do
    start_supervised!(Registry)
    # both handler_pid (JSON lines) and app_pid (proxy/system events) = test pid
    Registry.set("b", %Registry{name: "b", handler_pid: self(), app_pid: self()})
    %{state: %Backend{name: "b", port: :fake, buffer: ""}}
  end

  test "reassembles a JSON line split across noeol/eol fragments", %{state: state} do
    {:noreply, buffered} = Backend.handle_info({:p, {:data, {:noeol, ~s({"a")}}}, state)
    assert buffered.buffer == ~s({"a")

    Backend.handle_info({:p, {:data, {:eol, ~s(:1})}}}, buffered)
    assert_receive {:backend, ~s({"a":1})}
  end

  test "clears the buffer after flushing a completed line", %{state: state} do
    {:noreply, buffered} = Backend.handle_info({:p, {:data, {:noeol, "{"}}}, state)
    {:noreply, flushed} = Backend.handle_info({:p, {:data, {:eol, "}"}}}, buffered)
    assert flushed.buffer == ""
  end

  test "strips ANSI escape codes before forwarding", %{state: state} do
    Backend.handle_info({:p, {:data, {:eol, "\e[32m{\"x\":1}\e[0m"}}}, state)
    assert_receive {:backend, ~s({"x":1})}
  end

  test "parses a TDLib error line into a structured error", %{state: state} do
    Backend.handle_info({:p, {:data, {:eol, "Error: 400: CHAT_NOT_FOUND"}}}, state)
    assert_receive {:backend, json}
    assert %{"code" => 400, "message" => "CHAT_NOT_FOUND"} = Jason.decode!(json)
  end

  test "captures a multi-word error message in full (not truncated)", %{state: state} do
    Backend.handle_info({:p, {:data, {:eol, "Error: 401: Unauthorized: bot token bad"}}}, state)
    assert_receive {:backend, json}
    assert %{"code" => 401, "message" => "Unauthorized: bot token bad"} = Jason.decode!(json)
  end

  test "code 0 is a TDLib internal diagnostic — not forwarded as an error", %{state: state} do
    Backend.handle_info({:p, {:data, {:eol, "Error: 0: Ping timeout expired"}}}, state)
    refute_receive {:backend, _}, 100
  end

  test "drops tdlib's connection-transport noise, not real errors", %{state: state} do
    # FLOOD_WAIT on Connect::TCP is tdlib retrying its own connection — it waits
    # and reconnects itself, so forwarding it just floods the app pipeline with
    # unactionable fake errors. Real API errors (parsed above) still forward;
    # the discriminator is the Connect::/DcId transport framing they never carry.
    for line <- [
          "[Error: 420: FLOOD_WAIT_30] from Session:2:main::Connect::TCP::[1.2.3.4:443] to DcId{2}",
          "[ 3][t 0][ts][Client.cpp:600]\tCreate client 1"
        ],
        do: Backend.handle_info({:p, {:data, {:eol, line}}}, state)

    refute_receive {:backend, _}, 100
  end

  test "a freeze/ban is forwarded even if the line carries transport framing", %{state: state} do
    # Safety net: the discriminator must never swallow an actionable account
    # state error, whatever framing tdlib wraps it in.
    line =
      "[Error: 420: ACCOUNT_FROZEN] from Session:2:main::Connect::TCP::[1.2.3.4:443] to DcId{2}"

    Backend.handle_info({:p, {:data, {:eol, line}}}, state)

    assert_receive {:backend, json}
    assert json =~ "ACCOUNT_FROZEN"
  end

  test "forwards proxychains output as a proxy event to app_pid", %{state: state} do
    Backend.handle_info({:p, {:data, {:eol, "[proxychains] DLL init"}}}, state)
    assert_receive {:proxy_event, "DLL init"}
  end

  test "transmit into a dead port returns :no_port and stops for restart", %{state: state} do
    # Port.command on a non-port raises ArgumentError -> handled as a dead port
    assert {:stop, {:port_exited, :closed}, {:error, :no_port}, _} =
             Backend.handle_call({:transmit, "cmd"}, self(), state)
  end

  test "transmit with no port returns :no_port" do
    assert {:reply, {:error, :no_port}, _} =
             Backend.handle_call({:transmit, "cmd"}, self(), %Backend{name: "b", port: nil})
  end
end
