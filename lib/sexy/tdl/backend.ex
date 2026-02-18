defmodule Sexy.TDL.Backend do
  @moduledoc false
  use GenServer

  alias Sexy.TDL.Registry

  require Logger

  defstruct [:name, :port, :buffer]

  @port_opts_proxy [:binary, :line, :exit_status, :use_stdio, :stderr_to_stdout, :hide]
  @port_opts [:binary, :line]

  def start_link({name, proxy}) do
    GenServer.start_link(__MODULE__, {name, proxy}, [])
  end

  def init({name, proxy}) do
    true = Registry.update(name, backend_pid: self())

    case open_port(name, proxy) do
      {:ok, port} ->
        {:ok, %__MODULE__{name: name, buffer: "", port: port}}

      {:error, reason} ->
        handler_pid = Registry.get(name, :handler_pid)
        if handler_pid, do: send(handler_pid, {:system_event, :port_failed, reason})
        {:ok, %__MODULE__{name: name, buffer: "", port: nil}}
    end
  end

  def handle_call({:transmit, _msg}, _from, %{port: nil} = state) do
    {:reply, {:error, :no_port}, state}
  end

  def handle_call({:transmit, msg}, _from, state) do
    data = msg <> "\n"
    result = Kernel.send(state.port, {self(), {:command, data}})
    {:reply, result, state}
  end

  def handle_info({_from, {:data, data}}, state) do
    case data do
      {_, "[proxychains]" <> text} ->
        forward_proxy_event(state.name, String.trim(text))
        {:noreply, state}

      {_, "error: no valid proxy found in config"} ->
        forward_proxy_event(state.name, "error: no valid proxy found in config")
        {:noreply, state}

      {:eol, tail} ->
        {new_state, msg} =
          if state.buffer != "" do
            {%{state | buffer: ""}, state.buffer <> tail}
          else
            {state, tail}
          end

        text = strip_ansi(msg)
        handle_line(text, state.name)

        {:noreply, new_state}

      {:noeol, part} ->
        {:noreply, %{state | buffer: state.buffer <> part}}

      _ ->
        Logger.warning("#{state.name}: unexpected port data: #{inspect(data)}")
        {:noreply, state}
    end
  end

  def handle_info({_port, {:exit_status, status}}, state) do
    Logger.warning("#{state.name}: port exited with status #{status}")
    forward_system_event(state.name, :port_exited, status)
    {:noreply, %{state | port: nil}}
  end

  def terminate(_reason, %{port: port}) when is_port(port) do
    Port.close(port)
  end

  def terminate(_reason, _state), do: :ok

  # Private

  defp open_port(name, enable_proxy) do
    binary = Application.get_env(:sexy, :tdlib_binary)
    data_root = Application.get_env(:sexy, :tdlib_data_root)

    unless binary do
      raise "Missing :sexy, :tdlib_binary config"
    end

    try do
      port =
        if enable_proxy do
          proxy_conf = Path.join([data_root, name, "proxy.conf"])

          unless File.exists?(proxy_conf) do
            forward_system_event(name, :proxy_conf_missing, proxy_conf)
          end

          cmd = "proxychains4 -f #{proxy_conf} #{binary}"
          Port.open({:spawn_executable, "/bin/sh"}, @port_opts_proxy ++ [args: ["-c", cmd]])
        else
          Port.open({:spawn_executable, binary}, @port_opts)
        end

      {:ok, port}
    rescue
      e ->
        Logger.error("#{name}: unable to start port: #{inspect(e)}")
        {:error, e}
    end
  end

  defp handle_line(text, name) do
    handler_pid = Registry.get(name, :handler_pid)
    error = parse_tdlib_error(text)

    cond do
      json_line?(text) and handler_pid ->
        send(handler_pid, {:backend, text})

      error != :no_error and handler_pid ->
        send(handler_pid, {:backend, Jason.encode!(error)})
        Logger.warning("#{name}: TDLib error: code=#{error.code} reason=#{error.message}")

      json_line?(text) ->
        Logger.warning("#{name}: incoming message but no handler registered")

      true ->
        Logger.warning("#{name}: unrecognized output: #{inspect(text)}")
    end
  end

  defp forward_proxy_event(name, text) do
    handler_pid = Registry.get(name, :handler_pid)
    if handler_pid, do: send(handler_pid, {:proxy_event, text})
  end

  defp forward_system_event(name, type, details) do
    handler_pid = Registry.get(name, :handler_pid)
    if handler_pid, do: send(handler_pid, {:system_event, type, details})
  end

  defp strip_ansi(text), do: Regex.replace(~r/\e\[[0-9;]*m/, text, "")

  defp json_line?(text), do: text |> String.trim_leading() |> String.starts_with?("{")

  defp parse_tdlib_error(text) do
    case Regex.run(~r/Error\s*:\s*(\d+)\s*:\s*([A-Z0-9_]+)/, text) do
      [_, code, reason] -> %{"@type": "error", code: String.to_integer(code), message: reason}
      _ -> :no_error
    end
  end
end
