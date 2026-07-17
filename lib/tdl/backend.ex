defmodule Sexy.TDL.Backend do
  @moduledoc """
  GenServer managing the Erlang Port to the `tdlib_json_cli` binary.

  Handles line-buffering of port output, ANSI stripping, and error parsing.
  Forwards complete JSON lines to `Sexy.TDL.Handler` and system/proxy events
  to the app process.

  Started automatically by `Sexy.TDL.Riser` — not called directly.

  ## Proxy support

  When opened with `proxy: true`, the binary is wrapped in `proxychains4`.
  Requires a `proxy.conf` file at `<tdlib_data_root>/<session>/proxy.conf`.
  """
  use GenServer

  alias Sexy.TDL.Registry

  require Logger

  defstruct [:name, :port, :buffer]

  @port_opts_proxy [:binary, :line, :exit_status, :use_stdio, :stderr_to_stdout, :hide]
  # :exit_status is essential: without it the death of the external binary is
  # completely invisible and the session silently zombies.
  @port_opts [:binary, :line, :exit_status, :stderr_to_stdout]

  def start_link({name, proxy}) do
    GenServer.start_link(__MODULE__, {name, proxy}, [])
  end

  def init({name, proxy}) do
    # The registry entry can be gone (session closed mid-restart) — stop
    # cleanly instead of crash-looping the whole Riser.
    case Registry.update(name, backend_pid: self()) do
      true ->
        case open_port(name, proxy) do
          {:ok, port} ->
            {:ok, %__MODULE__{name: name, buffer: "", port: port}}

          {:error, reason} ->
            # Fail fast: the error surfaces synchronously via Sexy.TDL.open/3.
            {:stop, {:port_failed, reason}}
        end

      false ->
        {:stop, :session_unregistered}
    end
  end

  def handle_call({:transmit, _msg}, _from, %{port: nil} = state) do
    {:reply, {:error, :no_port}, state}
  end

  def handle_call({:transmit, msg}, _from, state) do
    # Port.command, not raw send: writing to a dead port must fail loudly
    # (raw send is silently discarded), so the pair gets restarted.
    Port.command(state.port, msg <> "\n")
    {:reply, :ok, state}
  rescue
    ArgumentError -> {:stop, {:port_exited, :closed}, {:error, :no_port}, state}
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
    # Stop so the Riser's :one_for_all restarts the Backend/Handler pair with
    # a fresh port — that supervision exists exactly for this failure.
    {:stop, {:port_exited, status}, %{state | port: nil}}
  end

  def terminate(_reason, %{port: port}) when is_port(port) do
    Port.close(port)
  rescue
    # The port may already be closed (e.g. we are stopping because it died)
    ArgumentError -> :ok
  end

  def terminate(_reason, _state), do: :ok

  # Private

  defp open_port(name, enable_proxy) do
    # Pure lookup (config → env → cache) — this runs on every Riser restart,
    # so it must never touch the network; download happens at Sexy.TDL start.
    binary = Sexy.TDL.Binary.resolve!()
    data_root = Application.get_env(:sexy, :tdlib_data_root)

    try do
      port =
        if enable_proxy do
          proxy_conf = Path.join([data_root, name, "proxy.conf"])

          unless File.exists?(proxy_conf) do
            forward_system_event(name, :proxy_conf_missing, proxy_conf)
          end

          # quoted: the auto-resolved cache path may contain spaces
          cmd = "proxychains4 -f '#{proxy_conf}' '#{binary}'"
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

      json_line?(text) ->
        Logger.warning("#{name}: incoming message but no handler registered")

      (match?(%{code: 0}, error) or connection_noise?(text)) and not critical_error?(text) ->
        # tdlib retries these itself (ping timeout code 0, FLOOD_WAIT on
        # Connect::TCP → DcId) — the app can't act on them, so never forward or
        # warn. Surfacing them as errors floods the log and the pipeline when
        # the direct-connection IP is throttled by Telegram. critical_error?
        # is the escape hatch: a freeze/ban is delivered even if it somehow
        # rides a line with transport framing.
        Logger.debug("#{name}: TDLib internal: #{text}")

      error != :no_error and handler_pid ->
        # Real API/auth errors (ACCOUNT_FROZEN, FROZEN_METHOD_INVALID, method
        # FLOOD_WAIT…): deliver to the pipeline. The consumer logs and decides.
        send(handler_pid, {:backend, Jason.encode!(error)})
        Logger.debug("#{name}: TDLib error forwarded: code=#{error.code} reason=#{error.message}")

      true ->
        Logger.debug("#{name}: TDLib: #{text}")
    end
  end

  # System/proxy events go straight to the app process: the Handler added
  # nothing for them, and during restarts its registry pid can be stale.
  defp forward_proxy_event(name, text) do
    app_pid = Registry.get(name, :app_pid)
    if is_pid(app_pid), do: send(app_pid, {:proxy_event, text})
  end

  defp forward_system_event(name, type, details) do
    app_pid = Registry.get(name, :app_pid)
    if is_pid(app_pid), do: send(app_pid, {:system_event, type, details})
  end

  defp strip_ansi(text), do: Regex.replace(~r/\e\[[0-9;]*m/, text, "")

  defp json_line?(text), do: text |> String.trim_leading() |> String.starts_with?("{")

  # tdlib's connection/transport layer logs its own retries as "errors" (e.g.
  # FLOOD_WAIT on Connect::TCP → DcId). They carry transport framing that real
  # API/auth errors never do, so match on it to keep the noise out of the app.
  defp connection_noise?(text),
    do: String.contains?(text, "Connect::") or String.contains?(text, "DcId{")

  # Account-state errors the consumer pipeline must always act on (freeze/ban):
  # never suppressed as noise, even if the line also carries transport framing.
  defp critical_error?(text),
    do: String.contains?(text, ["FROZEN", "BANNED", "DEACTIVATED"])

  defp parse_tdlib_error(text) do
    # message is the rest of the line, not just [A-Z0-9_] — otherwise
    # "Error: 0: Ping timeout expired" truncates to "P".
    case Regex.run(~r/Error\s*:\s*(\d+)\s*:\s*(.+)/, text) do
      [_, code, reason] ->
        %{"@type": "error", code: String.to_integer(code), message: String.trim(reason)}

      _ ->
        :no_error
    end
  end
end
