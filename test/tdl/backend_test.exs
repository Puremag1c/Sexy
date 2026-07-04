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
