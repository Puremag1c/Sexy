defmodule Sexy.TDL.Handler do
  @moduledoc """
  GenServer that deserializes TDLib JSON into Elixir structs and forwards them to the app.

  Receives raw JSON strings from `Sexy.TDL.Backend`, decodes them, and recursively
  converts nested `@type` objects into the corresponding `Sexy.TDL.Object.*` structs.

  Started automatically by `Sexy.TDL.Riser` — not called directly.

  ## Event types

  The handler forwards deserialized objects to `app_pid` as `{:recv, struct}`
  (e.g. `%Sexy.TDL.Object.UpdateNewMessage{}`). System and proxy events
  (`{:system_event, type, details}`, `{:proxy_event, text}`) are sent to
  `app_pid` directly by `Sexy.TDL.Backend`.
  """
  use GenServer

  alias Sexy.TDL.Registry

  require Logger

  @backend_verbosity_level 2

  def start_link(session_name) do
    GenServer.start_link(__MODULE__, session_name, [])
  end

  def init(session) do
    # The registry entry can be gone (session closed mid-restart) — stop
    # cleanly instead of crash-looping the whole Riser.
    case Registry.update(session, handler_pid: self()) do
      true -> {:ok, session}
      false -> {:stop, :session_unregistered}
    end
  end

  # Messages from Backend
  def handle_info({:backend, text}, session) do
    case Jason.decode(text) do
      {:ok, json} ->
        keys = Map.keys(json)

        cond do
          "@cli" in keys -> handle_cli(json, session)
          "@type" in keys -> handle_object(json, session)
          true -> Logger.warning("#{session}: unknown JSON structure received")
        end

      {:error, _} ->
        Logger.warning("#{session}: invalid JSON from backend: #{inspect(text)}")
    end

    {:noreply, session}
  end

  def terminate(_reason, _session) do
    Logger.warning("TDL Handler closing")
  end

  # Private

  defp handle_cli(json, session) do
    event = json |> Map.get("@cli") |> Map.get("event")
    Logger.debug("#{session}: CLI event #{event}")

    case event do
      "client_created" -> set_backend_verbosity(@backend_verbosity_level, session)
      _ -> :ok
    end
  end

  defp handle_object(json, session) do
    type = Map.get(json, "@type")

    try do
      struct = recursive_match(json, "Elixir.Sexy.TDL.Object.")
      forward_to_app(session, {:recv, struct})
    rescue
      _ -> Logger.warning("#{session}: no matching object for type #{inspect(type)}")
    end
  end

  defp forward_to_app(session, message) do
    case Registry.get(session, :app_pid) do
      pid when is_pid(pid) ->
        if Process.alive?(pid), do: send(pid, message)

      _ ->
        nil
    end
  end

  defp set_backend_verbosity(level, session) do
    backend_pid = Registry.get(session, :backend_pid)

    if backend_pid do
      GenServer.call(backend_pid, {:transmit, "verbose #{level}"})
      Logger.debug("#{session}: backend verbosity set to #{level}")
    end
  end

  defp recursive_match(json, prefix) when is_map(json) do
    struct = match_object(json, prefix)

    struct
    |> Map.from_struct()
    |> Enum.reduce(struct, fn
      {key, value}, acc when is_map(value) and not is_struct(value) ->
        %{acc | key => recurse_if_typed(value, prefix)}

      {key, value}, acc when is_list(value) ->
        %{acc | key => Enum.map(value, &recurse_if_typed(&1, prefix))}

      _, acc ->
        acc
    end)
  end

  defp recurse_if_typed(item, prefix) when is_map(item) do
    if Map.has_key?(item, "@type"),
      do: recursive_match(item, prefix),
      else: item
  end

  # vector<vector<T>> fields (e.g. inline keyboard rows) nest lists in lists
  defp recurse_if_typed(item, prefix) when is_list(item),
    do: Enum.map(item, &recurse_if_typed(&1, prefix))

  defp recurse_if_typed(item, _prefix), do: item

  # ponytail: titlecase_once moved to Sexy.Utils (shared with generate_types)

  defp match_object(json, prefix) do
    type =
      json
      |> Map.get("@type")
      |> Sexy.Utils.titlecase_once()

    module = String.to_existing_atom(prefix <> type)
    empty = struct(module)

    Enum.reduce(Map.to_list(empty), empty, fn {k, _}, acc ->
      case Map.fetch(json, Atom.to_string(k)) do
        {:ok, v} -> %{acc | k => v}
        :error -> acc
      end
    end)
  end
end
