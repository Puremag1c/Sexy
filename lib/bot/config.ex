defmodule Sexy.Bot.Config do
  @moduledoc false
  # Owns process-independent bot state: the persistent_term config entries and
  # the atomics ref holding the poller offset. Being the supervisor's first
  # child guarantees the config exists before the Poller starts and is erased
  # when the bot stops — a stopped bot must not keep sending with a stale token.
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    token = Keyword.fetch!(opts, :token)
    session = Keyword.fetch!(opts, :session)

    :persistent_term.put({Sexy.Bot, :api_url}, "https://api.telegram.org/bot#{token}")
    :persistent_term.put({Sexy.Bot, :session}, session)

    # The getUpdates offset lives outside the Poller so a poller crash never
    # replays the already-dispatched batch. Atomics, not persistent_term:
    # the value changes every poll and frequent persistent_term writes
    # trigger global GC. The ref survives bot restarts within the VM.
    if :persistent_term.get({Sexy.Bot, :offset_ref}, nil) == nil do
      :persistent_term.put({Sexy.Bot, :offset_ref}, :atomics.new(1, signed: true))
    end

    {:ok, :ok}
  end

  @impl true
  def terminate(_reason, _state) do
    :persistent_term.erase({Sexy.Bot, :api_url})
    :persistent_term.erase({Sexy.Bot, :session})
    # offset_ref stays: the offset must survive a bot restart in the same VM
  end
end
